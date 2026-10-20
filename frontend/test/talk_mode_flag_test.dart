import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hu_accomponist/config/app_constants.dart';
import 'package:hu_accomponist/features/hum/hum_chat.dart';
import 'package:hu_accomponist/features/hum/hum_controller.dart';
import 'package:hu_accomponist/features/hum/hum_page.dart';
import 'package:hu_accomponist/features/settings/settings_page.dart';
import 'package:hu_accomponist/integrations/auth/auth_controller.dart';

import 'support/auth_fakes.dart';
import 'support/hum_fakes.dart';

/// Talk mode (typing or speaking a change to the song) is answered by Google Gemini and ElevenLabs on the server.
/// A first public launch leaves it off, so the chat and its settings row are hidden unless the build says
/// `--dart-define=TALK_MODE=true`. Everything else on both screens must stay exactly as it is.
void main() {
  test('is off in a build that does not ask for it', () {
    expect(AppConstants.talkMode, isFalse);
  });

  group('hum page', () {
    late HumController controller;

    setUp(() {
      controller = HumController(
        repository: FakeHumRepository(),
        recorder: FakeRecorder(),
        player: FakePlayer(),
        rawPlayer: FakePlayer(),
        chatRecorder: FakeRecorder(),
        voicePlayer: FakePlayer(),
        sharer: FakeSharer(),
        store: MemorySavedHumStore(),
      );
    });

    tearDown(() => controller.dispose());

    Future<void> humWith(WidgetTester tester, {bool? talkMode}) async {
      tester.view.physicalSize = const Size(900, 4800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: talkMode == null
              ? HumPage(controller: controller)
              : HumPage(controller: controller, talkMode: talkMode),
        ),
      );
      await tester.runAsync(() async {
        await controller.startHum();
        await controller.stopHum();
      });
      await tester.pump();
    }

    testWidgets('by default shows the song and its controls but no chat', (tester) async {
      await humWith(tester);

      expect(find.text('G major  ·  97 bpm  ·  9 notes'), findsOneWidget);
      expect(find.text('YOUR SONG'), findsOneWidget);
      expect(find.byType(HumChat), findsNothing);
      expect(find.text('CHANGE IT WITH WORDS'), findsNothing);
      expect(find.byKey(const ValueKey('chat-mic')), findsNothing);
    });

    testWidgets('with Talk mode on, the chat is there', (tester) async {
      await humWith(tester, talkMode: true);

      expect(find.byType(HumChat), findsOneWidget);
      expect(find.text('CHANGE IT WITH WORDS'), findsOneWidget);
    });
  });

  group('settings page', () {
    late AuthController auth;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      auth = AuthController(store: MemorySessionStore(), repository: FakeAuthRepository());
    });

    tearDown(() => auth.dispose());

    Future<void> settingsWith(WidgetTester tester, {bool? talkMode}) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsPage(
            auth: auth,
            loginRequired: false,
            talkMode: talkMode,
            consent: MemoryTalkConsent(granted: false),
            loadVersion: () async => const AppVersion('1.2.3', '45'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('by default has no Talk mode row, and keeps the others', (tester) async {
      await settingsWith(tester);

      expect(find.text('Talk mode and AI services'), findsNothing);
      expect(find.text('Open-source licenses'), findsOneWidget);
    });

    testWidgets('with Talk mode on, the row is there', (tester) async {
      await settingsWith(tester, talkMode: true);

      expect(find.text('Talk mode and AI services'), findsOneWidget);
    });
  });
}
