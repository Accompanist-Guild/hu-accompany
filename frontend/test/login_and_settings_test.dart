import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hu_accomponist/config/app_constants.dart';
import 'package:hu_accomponist/features/auth/auth_gate.dart';
import 'package:hu_accomponist/features/auth/login_page.dart';
import 'package:hu_accomponist/features/settings/settings_page.dart';
import 'package:hu_accomponist/features/shell/app_shell.dart';
import 'package:hu_accomponist/features/shell/shell_controller.dart';
import 'package:hu_accomponist/integrations/auth/auth_controller.dart';
import 'package:hu_accomponist/integrations/auth/session_store.dart';
import 'package:hu_accomponist/integrations/server/api_client.dart';

import 'support/auth_fakes.dart';
import 'support/hum_fakes.dart' show FakeSharer, MemoryTalkConsent;

void main() {
  late MemorySessionStore store;
  late FakeAuthRepository repository;
  late AuthController auth;
  late FakeLinkOpener links;

  setUp(() {
    SharedPreferences.setMockInitialValues({'hasCompletedOnboarding': true});
    store = MemorySessionStore();
    repository = FakeAuthRepository();
    links = FakeLinkOpener();
    auth = AuthController(store: store, repository: repository);
  });

  tearDown(() => auth.dispose());

  void tallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('login page', () {
    Future<void> pumpLogin(WidgetTester tester) async {
      tallView(tester);
      await auth.restore();
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(auth: auth, links: links),
        ),
      );
    }

    Finder field(String label) => find.widgetWithText(TextField, label);

    testWidgets('signs in with the trimmed email and the password', (
      tester,
    ) async {
      await pumpLogin(tester);
      await tester.enterText(field('Email'), '  ada@example.com ');
      await tester.enterText(field('Password'), 'correct horse');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(repository.calls, ['login ada@example.com']);
      expect(auth.status, AuthStatus.signedIn);
      expect(store.session?.token, 'token-1');
    });

    testWidgets('does not send a form with a bad email or no password', (
      tester,
    ) async {
      await pumpLogin(tester);
      await tester.enterText(field('Email'), 'not an email');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address.'), findsOneWidget);

      await tester.enterText(field('Email'), 'ada@example.com');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(repository.calls, isEmpty);
    });

    testWidgets("shows the server's reason when sign-in is refused", (
      tester,
    ) async {
      repository.loginError = const ApiException(
        "That email and password don't match.",
        status: 401,
      );
      await pumpLogin(tester);
      await tester.enterText(field('Email'), 'ada@example.com');
      await tester.enterText(field('Password'), 'wrong password');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text("That email and password don't match."), findsOneWidget);
      expect(auth.status, AuthStatus.signedOut);
    });

    testWidgets('creates an account, with an optional name', (tester) async {
      await pumpLogin(tester);
      expect(field('Name (optional)'), findsNothing);
      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();

      await tester.enterText(field('Name (optional)'), 'Grace');
      await tester.enterText(field('Email'), 'grace@example.com');
      await tester.enterText(field('Password'), 'short');
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose a password of at least 8 characters.'),
        findsOneWidget,
      );
      expect(repository.calls, isEmpty);

      await tester.enterText(field('Password'), 'correct horse');
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(repository.calls, ['register grace@example.com Grace']);
      expect(auth.user?.displayName, 'Grace');
    });

    testWidgets('links to the terms and the privacy policy', (tester) async {
      await pumpLogin(tester);
      await tester.tap(find.text('Terms of Service'));
      await tester.tap(find.text('Privacy Policy'));
      expect(links.opened, [
        AppConstants.termsOfServiceUrl,
        AppConstants.privacyPolicyUrl,
      ]);
    });
  });

  group('auth gate', () {
    testWidgets('chooses the login page or the app from the auth state', (
      tester,
    ) async {
      final shell = ShellController();
      addTearDown(shell.dispose);
      await tester.pumpWidget(
        MaterialApp(
          // The disks spin for ever, which pumpAndSettle can't wait out.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: AuthGate(
            auth: auth,
            shell: shell,
            links: links,
            loginRequired: true,
            pageBuilder: (slot) => Text('page $slot'),
          ),
        ),
      );
      // Still reading the stored session: neither is shown.
      expect(find.byType(LoginPage), findsNothing);
      expect(find.byType(AppShell), findsNothing);

      await auth.restore();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);

      await auth.signIn(email: 'ada@example.com', password: 'correct horse');
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsNothing);
      expect(find.byType(AppShell), findsOneWidget);

      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    });

    testWidgets('opens straight into the app when a session was stored', (
      tester,
    ) async {
      store.session = const StoredSession(token: 'saved', user: ada);
      final shell = ShellController();
      addTearDown(shell.dispose);
      await auth.restore();
      await tester.pumpWidget(
        MaterialApp(
          // The disks spin for ever, which pumpAndSettle can't wait out.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: AuthGate(
            auth: auth,
            shell: shell,
            loginRequired: true,
            pageBuilder: (slot) => Text('page $slot'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
    });
  });

  group('auth gate with login switched off', () {
    Future<void> pumpGate(WidgetTester tester, {bool? loginRequired}) async {
      final shell = ShellController();
      addTearDown(shell.dispose);
      await tester.pumpWidget(
        MaterialApp(
          // The disks spin for ever, which pumpAndSettle can't wait out.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: AuthGate(
            auth: auth,
            shell: shell,
            links: links,
            loginRequired: loginRequired,
            pageBuilder: (slot) => Text('page $slot'),
          ),
        ),
      );
    }

    testWidgets('login is off in this build until it is switched on', (tester) async {
      expect(AppConstants.loginRequired, isFalse);
    });

    testWidgets('shows the app at once, even while the stored session is still being read', (tester) async {
      await pumpGate(tester, loginRequired: false);
      await tester.pump();
      expect(auth.status, AuthStatus.restoring);
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
    });

    testWidgets('shows the app when nobody is signed in', (tester) async {
      await auth.restore();
      await pumpGate(tester, loginRequired: false);
      await tester.pumpAndSettle();
      expect(auth.status, AuthStatus.signedOut);
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
    });

    testWidgets('uses the build setting when no value is passed', (tester) async {
      await auth.restore();
      await pumpGate(tester); // AppConstants.loginRequired is false
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsOneWidget);
    });

    testWidgets('switching login on gives the login page back', (tester) async {
      await auth.restore();
      await pumpGate(tester, loginRequired: true);
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    });
  });

  group('settings page', () {
    late FakeSharer sharer;
    late int replays;
    late MemoryTalkConsent talk;

    Future<void> pumpSettings(
      WidgetTester tester, {
      ThemeData? theme,
      bool talkAllowed = false,
      bool loginRequired = true,
    }) async {
      tallView(tester);
      sharer = FakeSharer();
      talk = MemoryTalkConsent(granted: talkAllowed);
      replays = 0;
      await auth.signIn(email: 'ada@example.com', password: 'correct horse');
      repository.calls.clear();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: SettingsPage(
            auth: auth,
            links: links,
            loginRequired: loginRequired,
            sharer: sharer,
            consent: talk,
            loadVersion: () async => const AppVersion('1.2.3', '45'),
            onReplayTutorial: () => replays++,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('with login off, hides the account rows and keeps the rest', (tester) async {
      await pumpSettings(tester, loginRequired: false);
      for (final gone in ['Export my data', 'Delete account', 'Log out', 'Your account']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      // Apple needs withdrawing the AI permission to stay reachable, and the legal pages too.
      expect(find.text('Talk mode and AI services'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Contact support or send feedback'), findsOneWidget);
    });

    testWidgets('with login on, the account rows are all there', (tester) async {
      await pumpSettings(tester, loginRequired: true);
      for (final shown in ['Export my data', 'Delete account', 'Log out', 'Your account']) {
        expect(find.text(shown), findsOneWidget, reason: shown);
      }
    });

    testWidgets('shows who is signed in and the version and build', (
      tester,
    ) async {
      await pumpSettings(tester);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('ada@example.com'), findsOneWidget);
      expect(find.textContaining('Version 1.2.3 (build 45)'), findsOneWidget);
    });

    testWidgets('opens the privacy policy and the terms', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Privacy Policy'));
      await tester.tap(find.text('Terms of Service'));
      expect(links.opened, [
        AppConstants.privacyPolicyUrl,
        AppConstants.termsOfServiceUrl,
      ]);
    });

    testWidgets('says so when a page cannot be opened', (tester) async {
      await pumpSettings(tester);
      links.canOpen = false;
      await tester.tap(find.text('Privacy Policy'));
      await tester.pump();
      expect(find.text("Couldn't open that page."), findsOneWidget);
    });

    testWidgets('lists the open-source licenses on their own screen', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Open-source licenses'));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
    });

    testWidgets('replays the tutorial', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Replay the tutorial'));
      expect(replays, 1);
    });

    testWidgets('logging out asks first, then returns to signed out', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(auth.status, AuthStatus.signedIn);

      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Log out'));
      await tester.pumpAndSettle();
      expect(auth.status, AuthStatus.signedOut);
      expect(store.session, isNull);
      expect(repository.calls, contains('logout token-1'));
    });

    testWidgets('deleting the account warns it is irreversible, then deletes', (
      tester,
    ) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(find.text('Delete your account?'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.calls, isEmpty);
      expect(auth.status, AuthStatus.signedIn);

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete account'));
      await tester.pumpAndSettle();
      expect(repository.calls, ['delete token-1']);
      expect(auth.status, AuthStatus.signedOut);
      expect(store.session, isNull);
    });

    testWidgets('a deletion that fails says why and keeps the account', (
      tester,
    ) async {
      await pumpSettings(tester);
      repository.deleteError = const ApiException(
        'Could not reach the accompaniment server.',
      );
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete account'));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not reach the accompaniment server.'),
        findsOneWidget,
      );
      expect(auth.status, AuthStatus.signedIn);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('uses the platform alert on iOS', (tester) async {
      await pumpSettings(
        tester,
        theme: ThemeData(platform: TargetPlatform.iOS),
      );
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      final destructive = tester.widget<CupertinoDialogAction>(
        find.widgetWithText(CupertinoDialogAction, 'Delete account'),
      );
      expect(destructive.isDestructiveAction, isTrue);
    });

    testWidgets('says whether Talk mode may share with the AI services', (tester) async {
      await pumpSettings(tester, talkAllowed: true);
      expect(find.text('Talk mode and AI services'), findsOneWidget);
      expect(find.textContaining('Allowed'), findsOneWidget);
    });

    testWidgets('stopping the sharing asks first, then withdraws it', (tester) async {
      await pumpSettings(tester, talkAllowed: true);
      await tester.tap(find.text('Talk mode and AI services'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(talk.granted, isTrue);

      await tester.tap(find.text('Talk mode and AI services'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Stop sharing'));
      await tester.pumpAndSettle();
      expect(talk.granted, isFalse);
      expect(find.textContaining('Not allowed'), findsOneWidget);
    });

    testWidgets('when it is off, tapping explains they will be asked next time', (tester) async {
      await pumpSettings(tester);
      expect(find.textContaining('Not allowed'), findsOneWidget);
      await tester.tap(find.text('Talk mode and AI services'));
      await tester.pumpAndSettle();
      expect(find.textContaining('asked the next time you use Talk mode'), findsOneWidget);
      expect(talk.granted, isFalse);
    });

    testWidgets('exports the data through the share sheet', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Export my data'));
      await tester.pumpAndSettle();
      expect(repository.calls, ['export token-1']);
      expect(sharer.shared.single.$1, 'hu-accompany-data.json');
      expect(sharer.shared.single.$2, 'application/json');
    });

    testWidgets('writes to support with the version filled in', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Contact support or send feedback'));
      await tester.pumpAndSettle();
      final email = links.emails.single;
      expect(email.to, AppConstants.supportEmail);
      expect(email.subject, contains(AppConstants.appName));
      expect(email.body, contains('1.2.3 (45)'));
    });

    testWidgets('shows the address when there is no mail app', (tester) async {
      await pumpSettings(tester);
      links.canEmail = false;
      await tester.tap(find.text('Contact support or send feedback'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Email us at ${AppConstants.supportEmail}'),
        findsOneWidget,
      );
      expect(find.text('Copy address'), findsOneWidget);
    });
  });

  test(
    'the configured links are https URLs and the support address is set',
    () {
      for (final url in [
        AppConstants.privacyPolicyUrl,
        AppConstants.termsOfServiceUrl,
      ]) {
        expect(Uri.parse(url).scheme, 'https');
        expect(Uri.parse(url).host, isNotEmpty);
      }
      expect(AppConstants.supportEmail, contains('@'));
    },
  );
}
