import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'dashboard.dart';

void main() => runApp(const UniBus());

class UniBus extends StatefulWidget {
  const UniBus({super.key});

  @override
  State<UniBus> createState() => _UniBusState();
}

class _UniBusState extends State<UniBus> {
  static const configuredUrl = String.fromEnvironment('UNIBUS_URL');
  static const allowLocalHttp = bool.fromEnvironment('UNIBUS_LOCAL_HTTP');

  final _form = GlobalKey<FormState>();
  final _server = TextEditingController(
    text: configuredUrl.isNotEmpty
        ? configuredUrl
        : kIsWeb
        ? Uri.base.origin
        : '',
  );
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  Api? _api;
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final url = Uri.tryParse(_server.text.trim());
    if (url == null ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        (url.scheme != 'https' && !(allowLocalHttp && url.scheme == 'http'))) {
      setState(() => _error = 'Informe um endereço válido do servidor HTTPS.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = Api(url);
      if (_register) {
        await api.register(
          _name.text.trim(),
          _email.text.trim(),
          _password.text,
        );
      } else {
        await api.login(_email.text.trim(), _password.text);
      }
      if (mounted) {
        _password.clear();
        setState(() => _api = api);
      }
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UniBus',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: _api == null
          ? Scaffold(
              appBar: AppBar(title: const Text('UniBus')),
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Form(
                    key: _form,
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          _register ? 'Criar conta' : 'Entrar',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        _field(
                          _server,
                          'Endereço do servidor',
                          type: TextInputType.url,
                        ),
                        if (_register) _field(_name, 'Nome'),
                        _field(
                          _email,
                          'E-mail',
                          type: TextInputType.emailAddress,
                        ),
                        _field(_password, 'Senha', password: true),
                        if (_error case final error?) ...[
                          const SizedBox(height: 12),
                          Text(
                            error,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: Text(
                            _busy
                                ? 'Aguarde…'
                                : _register
                                ? 'Cadastrar'
                                : 'Entrar',
                          ),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _register = !_register;
                                  _error = null;
                                }),
                          child: Text(
                            _register ? 'Já tenho conta' : 'Criar conta',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : Dashboard(api: _api!, onLogout: () => setState(() => _api = null)),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? type,
    bool password = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextFormField(
        controller: controller,
        enabled: !_busy,
        obscureText: password,
        keyboardType: type,
        decoration: InputDecoration(labelText: label),
        validator: (value) =>
            value!.trim().isEmpty ? 'Campo obrigatório' : null,
      ),
    );
  }
}
