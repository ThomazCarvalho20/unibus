import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';

typedef Input = ({String key, String label, Map<String, String>? options});

Input input(String key, String label, [Map<String, String>? options]) =>
    (key: key, label: label, options: options);

const roles = {
  'admin': 'Administrador',
  'driver': 'Motorista',
  'representative': 'Representante',
  'student': 'Estudante',
};
const statusLabels = {
  'active': 'Em andamento',
  'scheduled': 'Agendada',
  'cancelled': 'Cancelada',
  'finished': 'Encerrada',
  'pending': 'Pendente',
  'confirmed': 'Presença confirmada',
  'absent': 'Ausência informada',
  'suspended': 'Suspenso',
};

class Dashboard extends StatefulWidget {
  const Dashboard({super.key, required this.api, required this.onLogout});

  final Api api;
  final VoidCallback onLogout;

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  Json? _data;
  bool _busy = false;
  String? _error;
  String? _company;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run([String? action, Json data = const {}]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (action != null) await widget.api.action(action, data);
      final result = await widget.api.dashboard();
      if (mounted) setState(() => _data = result);
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(
    Json company,
    String action,
    String title,
    List<Input> fields,
  ) async {
    final data = await showDialog<Json>(
      context: context,
      builder: (context) => _Editor(title: title, fields: fields),
    );
    if (data == null || !mounted) return;
    if (action == 'vehicle') {
      final capacity = int.tryParse(data['capacity'] as String);
      if (capacity == null || capacity < 1 || capacity > 200) {
        setState(
          () => _error = 'A capacidade precisa ser um número de 1 a 200.',
        );
        return;
      }
      data['capacity'] = capacity;
    }
    if (action == 'trip') {
      final departure = DateTime.tryParse(data['departure'] as String);
      if (departure == null) {
        setState(
          () => _error = 'Informe data e horário no formato AAAA-MM-DD HH:MM.',
        );
        return;
      }
      data['departure'] = departure.toUtc().toIso8601String();
    }
    await _run(action, {...data, 'company': company['id']});
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: const Text('UniBus'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _run,
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: widget.onLogout,
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (data != null) ..._content(data),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(Json data) {
    final user = data['user'] as Json;
    final companies = records(data, 'companies');
    final active = companies
        .where((company) => company['status'] == 'active')
        .toList();
    final selected =
        active.where((company) => company['id'] == _company).firstOrNull ??
        active.firstOrNull;
    return [
      Text(
        'Olá, ${user['name']}',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('Nametag  ${user['nametag']}'),
        trailing: IconButton(
          icon: const Icon(Icons.copy),
          tooltip: 'Copiar Nametag',
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: user['nametag'] as String),
            );
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Nametag copiado')));
            }
          },
        ),
      ),
      for (final invite in companies.where(
        (company) => company['status'] == 'pending',
      ))
        Card(
          child: ListTile(
            title: Text('Convite de ${invite['name']}'),
            subtitle: Text(roles[invite['role']]!),
            trailing: FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run('accept', {'company': invite['id']}),
              child: const Text('Aceitar'),
            ),
          ),
        ),
      if (selected == null)
        const Text(
          'Compartilhe seu Nametag com a empresa para receber um convite.',
        )
      else ...[
        DropdownButtonFormField<String>(
          key: ValueKey(selected['id']),
          initialValue: selected['id'] as String,
          decoration: const InputDecoration(labelText: 'Empresa'),
          items: active
              .map(
                (company) => DropdownMenuItem(
                  value: company['id'] as String,
                  child: Text('${company['name']} · ${roles[company['role']]}'),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => _company = value),
        ),
        if (selected['role'] == 'admin') _admin(selected),
        const SizedBox(height: 16),
        Text('Rotas e viagens', style: Theme.of(context).textTheme.titleLarge),
        if (records(selected, 'routes').isEmpty)
          const Text('Nenhuma rota disponível.'),
        for (final route in records(selected, 'routes'))
          _route(selected, route),
      ],
    ];
  }

  Map<String, String> _options(Iterable<Json> data) => {
    for (final item in data) item['id'] as String: item['name'] as String,
  };

  Widget _admin(Json company) {
    final members = records(company, 'members');
    final vehicles = records(company, 'vehicles');
    final routes = records(company, 'routes');
    final drivers = members.where(
      (item) => item['role'] == 'driver' && item['status'] == 'active',
    );
    final students = members.where(
      (item) => item['role'] == 'student' && item['status'] == 'active',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _button(
              'Convidar',
              () => _edit(company, 'invite', 'Convidar por Nametag', [
                input('nametag', 'Nametag'),
                input('role', 'Perfil', {...roles}..remove('admin')),
              ]),
            ),
            _button(
              'Cadastrar veículo',
              () => _edit(company, 'vehicle', 'Novo veículo', [
                input('name', 'Nome'),
                input('plate', 'Placa'),
                input('capacity', 'Capacidade'),
              ]),
            ),
            _button(
              'Cadastrar rota',
              () => _edit(company, 'route', 'Nova rota', [
                input('name', 'Nome'),
                input('stops', 'Paradas em ordem'),
              ]),
            ),
            _button(
              'Vincular aluno à rota',
              routes.isEmpty || students.isEmpty
                  ? null
                  : () => _edit(company, 'assign', 'Vincular estudante', [
                      input('route', 'Rota', _options(routes)),
                      input('student', 'Estudante', _options(students)),
                    ]),
            ),
            _button(
              'Agendar viagem',
              routes.isEmpty || vehicles.isEmpty || drivers.isEmpty
                  ? null
                  : () => _edit(company, 'trip', 'Agendar viagem', [
                      input('route', 'Rota', _options(routes)),
                      input('vehicle', 'Veículo', _options(vehicles)),
                      input('driver', 'Motorista', _options(drivers)),
                      input('direction', 'Sentido', {
                        'outbound': 'Ida',
                        'return': 'Volta',
                      }),
                      input('departure', 'Saída (AAAA-MM-DD HH:MM)'),
                    ]),
            ),
          ],
        ),
        ExpansionTile(
          title: Text('Pessoas (${members.length})'),
          children: [
            for (final member in members)
              ListTile(
                title: Text(member['name'] as String),
                subtitle: Text(
                  '${roles[member['role']]} · ${member['status'] == 'active' ? 'Ativo' : statusLabels[member['status']]}',
                ),
                trailing:
                    member['role'] == 'admin' || member['status'] == 'suspended'
                    ? null
                    : _button(
                        'Suspender',
                        () => _run('suspend', {
                          'company': company['id'],
                          'user': member['id'],
                        }),
                      ),
              ),
          ],
        ),
        ExpansionTile(
          title: Text('Veículos (${vehicles.length})'),
          children: [
            for (final vehicle in vehicles)
              ListTile(
                title: Text(vehicle['name'] as String),
                subtitle: Text(
                  '${vehicle['plate']} · ${vehicle['capacity']} lugares',
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _route(Json company, Json route) {
    final trips = records(route, 'trips')
      ..sort(
        (a, b) =>
            (a['departure'] as String).compareTo(b['departure'] as String),
      );
    return Card(
      child: ExpansionTile(
        key: PageStorageKey(route['id']),
        title: Text(route['name'] as String),
        subtitle: Text(route['stops'] as String),
        children: [
          if (trips.isEmpty)
            const ListTile(title: Text('Nenhuma viagem cadastrada.')),
          for (final trip in trips) _trip(company, trip),
        ],
      ),
    );
  }

  Widget _trip(Json company, Json trip) {
    final role = company['role'];
    final status = trip['status'];
    final student = role == 'student';
    final canOperate = role == 'admin' || role == 'driver';
    final passengers = records(trip, 'passengers');
    final confirmed = passengers
        .where((passenger) => passenger['attendance'] == 'confirmed')
        .length;
    final boarded = passengers
        .where((passenger) => passenger['boarding'] != null)
        .length;
    final pending = passengers
        .where((passenger) => passenger['attendance'] == 'pending')
        .length;
    final tripKey = {'trip': trip['id']};
    final direction = trip['direction'] == 'outbound' ? 'Ida' : 'Volta';
    return ExpansionTile(
      key: PageStorageKey(trip['id']),
      title: Text('$direction · ${_time(trip['departure'])}'),
      subtitle: Text(
        '${statusLabels[status]} · ${trip['vehicle']} (${trip['plate']}) · ${trip['driver']}',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        if (!student)
          Text(
            '${passengers.length} vinculados · $confirmed confirmados · $pending pendentes · $boarded embarcados · ${trip['capacity']} lugares',
          ),
        Wrap(
          spacing: 8,
          children: [
            if (student && status == 'scheduled') ...[
              _button(
                'Confirmar presença',
                () => _run('attendance', {...tripKey, 'status': 'confirmed'}),
              ),
              _button(
                'Informar ausência',
                () => _run('attendance', {...tripKey, 'status': 'absent'}),
              ),
            ],
            if (canOperate && status == 'scheduled')
              _button(
                'Iniciar viagem',
                () => _run('trip_status', {...tripKey, 'status': 'active'}),
              ),
            if (canOperate && status == 'active')
              _button(
                'Encerrar viagem',
                () => _run('trip_status', {...tripKey, 'status': 'finished'}),
              ),
            if (canOperate && (status == 'active' || status == 'scheduled'))
              _button(
                'Cancelar viagem',
                () => _run('trip_status', {...tripKey, 'status': 'cancelled'}),
              ),
          ],
        ),
        for (final passenger in passengers)
          ListTile(
            title: Text(
              student ? 'Minha presença' : passenger['name'] as String,
            ),
            subtitle: Text(_passengerStatus(passenger)),
            trailing: status == 'active' && passenger['boarding'] == null
                ? _button(
                    'Embarque',
                    () => _run('boarding', {
                      ...tripKey,
                      'student': passenger['id'],
                    }),
                  )
                : null,
          ),
      ],
    );
  }

  String _passengerStatus(Json passenger) {
    final attendance = statusLabels[passenger['attendance']];
    final boarding = passenger['boarding'] as Json?;
    if (boarding == null) return '$attendance · Embarque pendente';
    return '$attendance · Embarque em ${_time(boarding['time'])}, por ${boarding['actor']}';
  }

  String _time(dynamic value) {
    final date = DateTime.tryParse(value.toString())?.toLocal();
    if (date == null) return 'Horário indisponível';
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatCompactDate(date)} ${TimeOfDay.fromDateTime(date).format(context)}';
  }

  Widget _button(String label, VoidCallback? onPressed) =>
      OutlinedButton(onPressed: _busy ? null : onPressed, child: Text(label));
}

class _Editor extends StatefulWidget {
  const _Editor({required this.title, required this.fields});

  final String title;
  final List<Input> fields;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final _form = GlobalKey<FormState>();
  final Json _values = {};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final field in widget.fields)
                  if (field.options case final options?)
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(labelText: field.label),
                      items: options.entries
                          .map(
                            (option) => DropdownMenuItem(
                              value: option.key,
                              child: Text(option.value),
                            ),
                          )
                          .toList(),
                      validator: (value) =>
                          value == null ? 'Selecione uma opção' : null,
                      onChanged: (value) => _values[field.key] = value,
                    )
                  else
                    TextFormField(
                      decoration: InputDecoration(labelText: field.label),
                      validator: (value) =>
                          value!.trim().isEmpty ? 'Campo obrigatório' : null,
                      onChanged: (value) => _values[field.key] = value.trim(),
                    ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (_form.currentState!.validate()) Navigator.pop(context, _values);
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
