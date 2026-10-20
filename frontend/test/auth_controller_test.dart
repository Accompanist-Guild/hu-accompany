import 'package:flutter_test/flutter_test.dart';

import 'package:hu_accomponist/integrations/auth/auth_controller.dart';
import 'package:hu_accomponist/integrations/auth/auth_user.dart';
import 'package:hu_accomponist/integrations/auth/session_store.dart';
import 'package:hu_accomponist/integrations/server/api_client.dart';

import 'support/auth_fakes.dart';

void main() {
  late MemorySessionStore store;
  late FakeAuthRepository repository;
  late int deletedCallbacks;
  late AuthController auth;

  setUp(() {
    store = MemorySessionStore();
    repository = FakeAuthRepository();
    deletedCallbacks = 0;
    auth = AuthController(
      store: store,
      repository: repository,
      onAccountDeleted: () async => deletedCallbacks++,
    );
  });

  tearDown(() => auth.dispose());

  test(
    'starts out restoring, and with no stored session is signed out',
    () async {
      expect(auth.status, AuthStatus.restoring);
      await auth.restore();
      expect(auth.status, AuthStatus.signedOut);
      expect(repository.calls, isEmpty);
    },
  );

  test(
    'a stored session is signed in after a restart, and then checked',
    () async {
      store.session = const StoredSession(token: 'saved', user: ada);
      await auth.restore();
      expect(auth.status, AuthStatus.signedIn);
      expect(auth.user, ada);
      expect(repository.calls, ['me saved']);
    },
  );

  test(
    'the token being rejected signs the person out and forgets it',
    () async {
      store.session = const StoredSession(token: 'revoked', user: ada);
      repository.meError = const ApiException(
        'Please sign in again.',
        status: 401,
      );
      await auth.restore();
      expect(auth.status, AuthStatus.signedOut);
      expect(store.session, isNull);
    },
  );

  test('an unreachable server leaves the person signed in', () async {
    store.session = const StoredSession(token: 'saved', user: ada);
    repository.meError = const ApiException('Could not reach the server.');
    await auth.restore();
    expect(auth.status, AuthStatus.signedIn);
    expect(store.session, isNotNull);
  });

  test('a stored session that cannot be read is the same as none', () async {
    final broken = _BrokenStore();
    final auth = AuthController(store: broken, repository: repository);
    addTearDown(auth.dispose);
    await auth.restore();
    expect(auth.status, AuthStatus.signedOut);
  });

  test('signing in keeps the session for the next launch', () async {
    await auth.restore();
    await auth.signIn(email: 'ada@example.com', password: 'correct horse');
    expect(auth.status, AuthStatus.signedIn);
    expect(store.session?.token, 'token-1');
    expect(store.session?.user, ada);
  });

  test('a failed sign-in changes nothing and passes the message on', () async {
    await auth.restore();
    repository.loginError = const ApiException(
      "That email and password don't match.",
      status: 401,
    );
    await expectLater(
      auth.signIn(email: 'ada@example.com', password: 'nope'),
      throwsA(isA<ApiException>()),
    );
    expect(auth.status, AuthStatus.signedOut);
    expect(store.session, isNull);
  });

  test('registering signs in with the new account', () async {
    await auth.restore();
    await auth.register(
      email: 'new@example.com',
      password: 'correct horse',
      name: 'New',
    );
    expect(auth.user?.email, 'new@example.com');
    expect(auth.user?.displayName, 'New');
    expect(store.session?.token, 'token-2');
  });

  test('logging out signs out at once and tells the server', () async {
    await auth.restore();
    await auth.signIn(email: 'ada@example.com', password: 'correct horse');
    await auth.signOut();
    expect(auth.status, AuthStatus.signedOut);
    expect(store.session, isNull);
    expect(repository.calls, contains('logout token-1'));
  });

  test('logging out works when the server cannot be told', () async {
    await auth.restore();
    await auth.signIn(email: 'ada@example.com', password: 'correct horse');
    repository.logoutError = const ApiException('Could not reach the server.');
    await auth.signOut();
    expect(auth.status, AuthStatus.signedOut);
    expect(store.session, isNull);
  });

  test('deleting the account removes it on the server, then here', () async {
    await auth.restore();
    await auth.signIn(email: 'ada@example.com', password: 'correct horse');
    await auth.deleteAccount();
    expect(repository.calls, contains('delete token-1'));
    expect(auth.status, AuthStatus.signedOut);
    expect(store.session, isNull);
    expect(deletedCallbacks, 1);
  });

  test('a deletion the server refuses leaves the person signed in', () async {
    await auth.restore();
    await auth.signIn(email: 'ada@example.com', password: 'correct horse');
    repository.deleteError = const ApiException('Could not reach the server.');
    await expectLater(auth.deleteAccount(), throwsA(isA<ApiException>()));
    expect(auth.status, AuthStatus.signedIn);
    expect(store.session, isNotNull);
    expect(deletedCallbacks, 0);
  });

  test('export returns the server data for the signed-in account', () async {
    await auth.restore();
    await auth.signIn(email: 'ada@example.com', password: 'correct horse');
    expect(await auth.exportData(), contains('ada@example.com'));
  });

  test('display name falls back to the start of the email', () {
    expect(ada.displayName, 'Ada');
    expect(
      const AuthUser(id: 3, email: 'grace@example.com').displayName,
      'grace',
    );
  });
}

class _BrokenStore extends MemorySessionStore {
  @override
  Future<StoredSession?> read() async => throw Exception('keychain locked');
}
