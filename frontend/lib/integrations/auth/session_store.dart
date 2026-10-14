import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:hu_accomponist/integrations/auth/auth_user.dart';

/// What stays on the device between launches so the person is still signed
/// in: the bearer token, and who it belongs to (so the app can open straight
/// into itself without waiting for the network).
class StoredSession {
  final String token;
  final AuthUser user;
  const StoredSession({required this.token, required this.user});
}

/// Where the session is kept. An interface so tests don't touch a keychain.
abstract class SessionStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}

/// The Keychain on iOS and macOS, encrypted preferences elsewhere. The token
/// is a credential, so unlike the app's other settings it never goes in
/// shared_preferences.
class SecureSessionStore implements SessionStore {
  const SecureSessionStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(
      // The data-protection keychain needs a keychain-sharing entitlement
      // that this app's macOS target doesn't declare.
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'auth.token';
  static const _userKey = 'auth.user';

  @override
  Future<StoredSession?> read() async {
    final token = await _storage.read(key: _tokenKey);
    final user = await _storage.read(key: _userKey);
    if (token == null || token.isEmpty || user == null) return null;
    try {
      return StoredSession(
        token: token,
        user: AuthUser.fromJson(jsonDecode(user) as Map<String, dynamic>),
      );
    } on Object {
      // A half-written or older-format entry: treat as signed out.
      return null;
    }
  }

  @override
  Future<void> write(StoredSession session) async {
    await _storage.write(key: _tokenKey, value: session.token);
    await _storage.write(
      key: _userKey,
      value: jsonEncode(session.user.toJson()),
    );
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }
}
