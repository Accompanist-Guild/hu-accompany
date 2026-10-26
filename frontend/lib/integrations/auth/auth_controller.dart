import 'package:flutter/foundation.dart';

import 'package:hu_accomponist/integrations/auth/auth_repository.dart';
import 'package:hu_accomponist/integrations/auth/auth_user.dart';
import 'package:hu_accomponist/integrations/auth/session_store.dart';
import 'package:hu_accomponist/integrations/server/api_client.dart';

enum AuthStatus {
  /// Reading the stored session; the app is still on its splash.
  restoring,
  signedOut,
  signedIn,
}

/// Who is signed in, for the whole app.
///
/// The session lives in the [SessionStore], so it survives restarts until
/// [signOut] (or [deleteAccount]) clears it. Opening the app trusts the
/// stored session straight away, so it works offline and doesn't wait on the
/// server; the token is checked in the background, and only an explicit
/// rejection (401) signs the person out. A server that merely can't be
/// reached never does.
class AuthController extends ChangeNotifier {
  AuthController({
    required SessionStore store,
    required AuthRepository repository,
    this.onAccountDeleted,
  }) : _store = store,
       _repository = repository;

  final SessionStore _store;
  final AuthRepository _repository;

  /// Run after an account is deleted, to forget what was kept for it on this
  /// device (the onboarding flag).
  final Future<void> Function()? onAccountDeleted;

  AuthStatus _status = AuthStatus.restoring;
  AuthUser? _user;
  String? _token;

  AuthStatus get status => _status;
  AuthUser? get user => _user;

  /// The bearer token for calls made on the person's behalf outside the
  /// accounts API (the Guides editor). Null when signed out.
  String? get token => _token;

  Future<void> restore() async {
    StoredSession? stored;
    try {
      stored = await _store.read();
    } on Object catch (e) {
      // A keychain that can't be read is the same as no session.
      debugPrint('[auth] could not read the stored session: $e');
    }
    if (stored == null) {
      _set(AuthStatus.signedOut);
      return;
    }
    _token = stored.token;
    _user = stored.user;
    _set(AuthStatus.signedIn);
    await _verify(stored.token);
  }

  Future<void> _verify(String token) async {
    try {
      final fresh = await _repository.me(token);
      if (_token != token) return; // signed out or in again meanwhile
      _user = fresh;
      await _store.write(StoredSession(token: token, user: fresh));
      notifyListeners();
    } on ApiException catch (e) {
      if (e.status == 401 && _token == token) await _forget();
    }
  }

  /// Throws [ApiException] with a message for the person when it fails.
  Future<void> signIn({required String email, required String password}) async {
    await _begin(await _repository.login(email: email, password: password));
  }

  Future<void> register({
    required String email,
    required String password,
    String name = '',
  }) async {
    await _begin(
      await _repository.register(email: email, password: password, name: name),
    );
  }

  Future<void> _begin(AuthResult result) async {
    await _store.write(StoredSession(token: result.token, user: result.user));
    _token = result.token;
    _user = result.user;
    _set(AuthStatus.signedIn);
  }

  /// Signs out on this device at once, then tells the server (best effort: a
  /// server that can't be reached must not keep the person signed in).
  Future<void> signOut() async {
    final token = _token;
    await _forget();
    if (token == null) return;
    try {
      await _repository.logout(token);
    } on ApiException catch (e) {
      debugPrint('[auth] server sign-out failed: ${e.message}');
    }
  }

  /// Deletes the account on the server, then forgets it here. Throws
  /// [ApiException] and changes nothing if the server doesn't confirm.
  Future<void> deleteAccount() async {
    final token = _token;
    if (token == null) return;
    await _repository.deleteAccount(token);
    await _forget();
    await onAccountDeleted?.call();
  }

  /// The account's data as JSON text, for the person to keep.
  Future<String> exportData() async {
    final token = _token;
    if (token == null) {
      throw const ApiException('Sign in to export your data.');
    }
    return _repository.exportData(token);
  }

  Future<void> _forget() async {
    _token = null;
    _user = null;
    try {
      await _store.clear();
    } on Object catch (e) {
      debugPrint('[auth] could not clear the stored session: $e');
    }
    _set(AuthStatus.signedOut);
  }

  void _set(AuthStatus status) {
    _status = status;
    notifyListeners();
  }
}
