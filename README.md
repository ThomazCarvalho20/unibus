# UniBus

Piloto de transporte universitário com aplicativo Android, painel web e servidor PocketBase com SQLite.

O estudante recebe um Nametag, aceita o convite da empresa e consulta as viagens das suas rotas. O administrador cadastra veículos, rotas e viagens, e o motorista acompanha a lista de passageiros. Presença e embarque são registrados separadamente. Cada empresa tem seus próprios vínculos e dados operacionais.

## Rodar no Windows

Use Flutter com Dart 3.13, Android SDK e PocketBase 0.40.6. Baixe o executável no [release oficial](https://github.com/pocketbase/pocketbase/releases/tag/v0.40.6), coloque-o em `server/.local` e execute os comandos a partir da raiz do projeto.

```powershell
flutter pub get
flutter build web --dart-define=UNIBUS_LOCAL_HTTP=true --output=server/pb_public
.\server\.local\pocketbase.exe serve --http=0.0.0.0:8090 --dir=server/pb_data --hooksDir=server/pb_hooks --migrationsDir=server/pb_migrations --publicDir=server/pb_public --automigrate=false
```

O painel do UniBus fica em `http://localhost:8090`. Abra o link de instalação mostrado pelo PocketBase para cadastrar o superusuário. Use o painel técnico em `http://localhost:8090/_/` para criar a primeira empresa.

1. Cadastre uma conta comum pelo UniBus para administrar a empresa e copie seu Nametag.
2. No painel técnico, crie um registro em `companies` com o nome da empresa. Em `memberships`, relacione a empresa à conta criada, com `role = admin` e `status = active`.
3. Crie contas para um motorista e um estudante pelo UniBus. Na conta da empresa, convide os dois pelos Nametags e aceite cada convite na conta correspondente.
4. Na empresa, cadastre veículo e rota, vincule o estudante à rota e agende uma viagem com o motorista.
5. No Android, confirme presença como estudante. Inicie a viagem como motorista, registre o embarque e encerre a viagem. Atualize a tela para consultar o histórico.

## Instalar no Android

```powershell
flutter build apk --debug --dart-define=UNIBUS_LOCAL_HTTP=true
```

Copie `build/app/outputs/flutter-apk/app-debug.apk` para o aparelho e instale. Para teste com dados fictícios, conecte o celular e o computador ao mesmo Wi-Fi e informe `http://IP-DO-COMPUTADOR:8090` na tela de login. O firewall do computador precisa permitir acesso à porta 8090 na rede privada. No emulador Android, use `http://10.0.2.2:8090`.

## Acesso pela internet

Hospede o executável com `server/pb_hooks`, `server/pb_migrations` e o painel compilado em um servidor com disco persistente. Configure um endereço HTTPS e reinício automático. Restrinja o acesso ao painel técnico a quem opera o servidor e configure backups do SQLite. A documentação do [PocketBase](https://pocketbase.io/docs/going-to-production/) descreve opções de TLS, proxy e backup.

```powershell
flutter build web --output=server/pb_public
flutter build apk --dart-define=UNIBUS_URL=https://seu-servidor
```

O APK para HTTPS aceita a URL na tela de login. O projeto usa a chave de depuração nas compilações locais. Configure a sua chave de assinatura antes de distribuir uma versão final.

## Limites do piloto

As viagens são cadastradas manualmente, e a confirmação não reserva assento. A aprovação da empresa ocorre por convite. A tela permite atualizar os dados manualmente. GPS, mapas, notificações push e sincronização offline ficam para a próxima fase.
