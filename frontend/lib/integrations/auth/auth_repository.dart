import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:hu_accomponist/integrations/auth/auth_user.dart';
import 'package:hu_accomponist/integrations/server/api_client.dart';

/// A successful sign-in or registration.
class AuthResult {
  final String token;
  final AuthUser user;
  const AuthResult({required this.token, required this.user});
}

/// The accounts API (backend/accounts), as the app uses it. Every failure is
/// an [ApiException] whose message is worded for the person.
abstract class AuthRepository {
  Future<AuthResult> register({
    required String email,
    required String password,
    String name = '',
  });
  Future<AuthResult> login({required String email, required String password});

  /// Throws [ApiException] with status 401 once the token is no longer valid.
  Future<AuthUser> me(String token);
  Future<void> logout(String token);
  Future<void> deleteAccount(String token);

  /// Everything the server holds about the account, as pretty-printed JSON.
  Future<String> exportData(String token);
}

class ApiAuthRepository implements AuthRepository {
  const ApiAuthRepository({this.client = const ApiClient()});

  final ApiClient client;

  static Map<String, String> _bearer(String token) => {
    'Authorization': 'Bearer $token',
  };

  @override
  Future<AuthResult> register({
    required String email,
    required String password,
    String name = '',
  }) async {
    final response = await client.postJson('/api/auth/register', {
      'email': email,
      'password': password,
      'name': name,
    });
    return _result(ApiClient.ensureOk(response));
  }

  @override
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final response = await client.postJson('/api/auth/login', {
      'email': email,
      'password': password,
    });
    return _result(ApiClient.ensureOk(response));
  }

  @override
  Future<AuthUser> me(String token) async {
    final response = await client.getJson(
      '/api/auth/me',
      headers: _bearer(token),
    );
    final body = jsonDecode(
      utf8.decode(ApiClient.ensureOk(response).bodyBytes),
    );
    return AuthUser.fromJson((body as Map<String, dynamic>)['user']);
  }

  @override
  Future<void> logout(String token) async {
    ApiClient.ensureOk(
      await client.postJson('/api/auth/logout', {}, headers: _bearer(token)),
    );
  }

  @override
  Future<void> deleteAccount(String token) async {
    ApiClient.ensureOk(
      await client.delete('/api/auth/account', headers: _bearer(token)),
    );
  }

  @override
  Future<String> exportData(String token) async {
    final response = await client.getJson(
      '/api/auth/export',
      headers: _bearer(token),
    );
    return utf8.decode(ApiClient.ensureOk(response).bodyBytes);
  }

  static AuthResult _result(http.Response response) {
    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return AuthResult(
      token: body['token'] as String,
      user: AuthUser.fromJson(body['user'] as Map<String, dynamic>),
    );
  }
}
