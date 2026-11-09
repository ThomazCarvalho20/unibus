import 'dart:convert';

import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class Api {
  Api(this.baseUrl);

  final Uri baseUrl;
  String? _token;

  Future<Json> _request(String path, {Json? body}) async {
    final uri = baseUrl.resolve(path);
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': ?_token,
    };
    final response =
        await (body == null
                ? http.get(uri, headers: headers)
                : http.post(uri, headers: headers, body: jsonEncode(body)))
            .timeout(const Duration(seconds: 12));
    final result = jsonDecode(utf8.decode(response.bodyBytes)) as Json;
    if (response.statusCode >= 400) {
      throw ApiError(result['message'] as String? ?? 'Falha na operação.');
    }
    return result;
  }

  Future<void> register(String name, String email, String password) async {
    await _request(
      '/api/unibus/register',
      body: {'name': name, 'email': email, 'password': password},
    );
    await login(email, password);
  }

  Future<void> login(String email, String password) async {
    final result = await _request(
      '/api/collections/users/auth-with-password',
      body: {'identity': email.toLowerCase(), 'password': password},
    );
    _token = result['token'] as String;
  }

  Future<Json> dashboard() => _request('/api/unibus/dashboard');

  Future<void> action(String name, Json data) async {
    await _request('/api/unibus/action/$name', body: data);
  }
}

class ApiError implements Exception {
  ApiError(this.message);
  final String message;
}

List<Json> records(Json parent, String key) =>
    (parent[key] as List? ?? const []).cast<Json>();

String describeError(Object error) => error is ApiError
    ? error.message
    : 'Não foi possível concluir. Verifique a conexão e tente novamente.';
