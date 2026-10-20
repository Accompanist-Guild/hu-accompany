import 'package:hu_accomponist/integrations/auth/auth_repository.dart';
import 'package:hu_accomponist/integrations/auth/auth_user.dart';
import 'package:hu_accomponist/integrations/auth/session_store.dart';
import 'package:hu_accomponist/integrations/links/link_opener.dart';
import 'package:hu_accomponist/integrations/server/api_client.dart';

const ada = AuthUser(id: 1, email: 'ada@example.com', name: 'Ada');

class MemorySessionStore implements SessionStore {
  MemorySessionStore([this.session]);

  StoredSession? session;

  @override
  Future<StoredSession?> read() async => session;

  @override
  Future<void> write(StoredSession session) async => this.session = session;

  @override
  Future<void> clear() async => session = null;
}

/// Answers like the accounts API, from a list of what was asked. A test makes
/// a call fail by setting the matching `*Error`.
class FakeAuthRepository implements AuthRepository {
  final List<String> calls = [];

  ApiException? loginError;
  ApiException? registerError;
  ApiException? meError;
  ApiException? logoutError;
  ApiException? deleteError;
  AuthUser me_ = ada;

  @override
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    calls.add('login $email');
    if (loginError != null) throw loginError!;
    return AuthResult(token: 'token-1', user: ada);
  }

  @override
  Future<AuthResult> register({
    required String email,
    required String password,
    String name = '',
  }) async {
    calls.add('register $email $name');
    if (registerError != null) throw registerError!;
    return AuthResult(
      token: 'token-2',
      user: AuthUser(id: 2, email: email, name: name),
    );
  }

  @override
  Future<AuthUser> me(String token) async {
    calls.add('me $token');
    if (meError != null) throw meError!;
    return me_;
  }

  @override
  Future<void> logout(String token) async {
    calls.add('logout $token');
    if (logoutError != null) throw logoutError!;
  }

  @override
  Future<void> deleteAccount(String token) async {
    calls.add('delete $token');
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<String> exportData(String token) async {
    calls.add('export $token');
    return '{"account": {"email": "ada@example.com"}}';
  }
}

class FakeLinkOpener implements LinkOpener {
  final List<String> opened = [];
  final List<({String to, String subject, String body})> emails = [];
  bool canOpen = true;
  bool canEmail = true;

  @override
  Future<bool> openWeb(String url) async {
    opened.add(url);
    return canOpen;
  }

  @override
  Future<bool> composeEmail({
    required String to,
    String subject = '',
    String body = '',
  }) async {
    emails.add((to: to, subject: subject, body: body));
    return canEmail;
  }
}
