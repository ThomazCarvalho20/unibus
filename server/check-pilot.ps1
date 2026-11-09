$ErrorActionPreference = 'Stop'
$server = Split-Path -Parent $PSCommandPath
$exe = Join-Path $server '.local/pocketbase.exe'
$testData = Join-Path $server ('.local/check-' + [guid]::NewGuid().ToString('N'))
$base = 'http://127.0.0.1:18091'
$email = 'superuser@example.test'
$secret = [guid]::NewGuid().ToString('N')

function Request($Method, $Path, $Data = $null, $Token = '', $Expected = 200) {
    $options = @{
        Method = $Method
        Uri = "$base$Path"
        SkipHttpErrorCheck = $true
        StatusCodeVariable = 'statusCode'
    }
    if ($Data -ne $null) {
        $options.ContentType = 'application/json; charset=utf-8'
        $options.Body = $Data | ConvertTo-Json -Depth 8 -Compress
    }
    if ($Token) { $options.Headers = @{ Authorization = $Token } }
    $result = Invoke-RestMethod @options
    if ($statusCode -ne $Expected) {
        throw "$Method ${Path}: HTTP $statusCode, esperado $Expected. $($result | ConvertTo-Json -Depth 8 -Compress)"
    }
    return $result
}

function Register($Name) {
    $identity = $Name.ToLowerInvariant() + '@example.test'
    $record = Request POST '/api/unibus/register' @{ name = $Name; email = $identity; password = $secret } '' 201
    $auth = Request POST '/api/collections/users/auth-with-password' @{ identity = $identity; password = $secret }
    return @{ id = $record.id; nametag = $record.nametag; token = $auth.token }
}

function Action($Account, $Name, $Data, $Expected = 200) {
    $null = Request POST "/api/unibus/action/$Name" $Data $Account.token $Expected
}

Push-Location $server
try {
    & $exe superuser create $email $secret "--dir=$testData" '--migrationsDir=pb_migrations'
    if ($LASTEXITCODE) { throw 'Falha ao preparar o banco de teste.' }
    $hooks = Join-Path $server 'pb_hooks'
    $migrations = Join-Path $server 'pb_migrations'
    $outLog = Join-Path $testData 'serve.out'
    $errLog = Join-Path $testData 'serve.err'
    $processOptions = @{
        FilePath = $exe
        ArgumentList = @('serve', '--http=127.0.0.1:18091', ('"--dir=' + $testData + '"'),
            ('"--hooksDir=' + $hooks + '"'), ('"--migrationsDir=' + $migrations + '"'), '--automigrate=false', '--dev')
        PassThru = $true
        WindowStyle = 'Hidden'
        RedirectStandardOutput = $outLog
        RedirectStandardError = $errLog
    }
    $process = Start-Process @processOptions
    $ready = $false
    for ($retry = 0; $retry -lt 20 -and !$ready; $retry++) {
        try { $null = Request GET '/api/health'; $ready = $true }
        catch { Start-Sleep -Milliseconds 250 }
    }
    if (!$ready) {
        Get-Content $outLog, $errLog
        throw 'O PocketBase de teste não respondeu.'
    }
    $root = Request POST '/api/collections/_superusers/auth-with-password' @{ identity = $email; password = $secret }
    $admin = Register 'Admin'
    $driver = Register 'Motorista'
    $student = Register 'Estudante'
    $outside = Register 'Outro'
    $company = (Request POST '/api/collections/companies/records' @{ name = 'Piloto' } $root.token).id
    $otherCompany = (Request POST '/api/collections/companies/records' @{ name = 'Outra empresa' } $root.token).id
    $null = Request POST '/api/collections/memberships/records' @{
        company = $company; user = $admin.id; role = 'admin'; status = 'active'
    } $root.token
    $null = Request POST '/api/collections/memberships/records' @{
        company = $otherCompany; user = $outside.id; role = 'admin'; status = 'active'
    } $root.token

    Action $admin invite @{ company = $company; nametag = $driver.nametag; role = 'driver' }
    Action $admin invite @{ company = $company; nametag = $student.nametag; role = 'student' }
    Action $driver accept @{ company = $company }
    Action $student accept @{ company = $company }
    Action $admin route @{ company = $company; name = 'Centro'; stops = 'Praça, Campus' }
    Action $admin vehicle @{ company = $company; name = 'Ônibus 1'; plate = 'TST1A23'; capacity = 40 }
    Action $outside route @{ company = $company; name = 'Invasão'; stops = 'Praça' } 403

    $panel = (Request GET '/api/unibus/dashboard' $null $admin.token).companies[0]
    $route = $panel.routes[0].id
    $vehicle = $panel.vehicles[0].id
    Action $admin assign @{ company = $company; route = $route; student = $student.id }
    Action $admin trip @{
        company = $company; route = $route; vehicle = $vehicle
        driver = $driver.id; direction = 'outbound'; departure = '2026-11-15T19:00:00.000Z'
    }
    $trip = (Request GET '/api/unibus/dashboard' $null $student.token).companies[0].routes[0].trips[0].id
    Action $student attendance @{ trip = $trip; status = 'confirmed' }
    Action $outside attendance @{ trip = $trip; student = $student.id; status = 'absent' } 403
    Action $student boarding @{ trip = $trip } 400
    Action $driver trip_status @{ trip = $trip; status = 'active' }
    Action $driver boarding @{ trip = $trip; student = $student.id }
    Action $driver boarding @{ trip = $trip; student = $student.id }
    Action $driver trip_status @{ trip = $trip; status = 'finished' }
    $result = (Request GET '/api/unibus/dashboard' $null $student.token).companies[0].routes[0].trips[0]
    $boardings = Request GET '/api/collections/boardings/records' $null $root.token
    if ($result.status -ne 'finished' -or $result.passengers[0].attendance -ne 'confirmed' -or
        $result.passengers[0].boarding.actor -ne 'Motorista' -or $boardings.totalItems -ne 1) {
        throw 'O histórico ou o registro de embarque ficou inconsistente.'
    }
    Write-Output 'Piloto validado: convite, isolamento, viagem, presença e embarque sem duplicidade.'
} catch {
    if ($outLog -and (Test-Path $outLog)) {
        Select-String -Path $outLog -Pattern 'ERROR.*unibus/action' -Context 0,2
    }
    throw
} finally {
    if ($process -and !$process.HasExited) { Stop-Process -Id $process.Id }
    Pop-Location
}
