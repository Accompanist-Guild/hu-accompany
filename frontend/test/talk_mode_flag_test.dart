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
/// It is on by default (nothing is sent until the person agrees in the consent box, see talk_consent_test.dart),
/// and a build for a server without those keys can leave it out with `--dart-define=TALK_MODE=false`, which hides
/// the chat and its settings row. Everything else on both screens must stay exactly as it is.
void main() {
  test('is on in a build that does not say otherwise', () {
    expect(AppConstants.talkMode, isTrue);
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

    testWidgets('by default the chat is there, next to the song and its controls', (tester) async {
      await humWith(tester);

      expect(find.text('G major  ·  97 bpm  ·  9 notes'), findsOneWidget);
      expect(find.text('YOUR SONG'), findsOneWidget);
      expect(find.byType(HumChat), findsOneWidget);
      expect(find.text('CHANGE IT WITH WORDS'), findsOneWidget);
    });

    testWidgets('with Talk mode left out of the build, there is no chat but the song and controls stay', (tester) async {
      await humWith(tester, talkMode: false);

      expect(find.text('G major  ·  97 bpm  ·  9 notes'), findsOneWidget);
      expect(find.text('YOUR SONG'), findsOneWidget);
      expect(find.byType(HumChat), findsNothing);
      expect(find.text('CHANGE IT WITH WORDS'), findsNothing);
      expect(find.byKey(const ValueKey('chat-mic')), findsNothing);
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

    testWidgets('by default has the Talk mode row, and the others', (tester) async {
      await settingsWith(tester);

      expect(find.text('Talk mode and AI services'), findsOneWidget);
      expect(find.text('Open-source licenses'), findsOneWidget);
    });

    testWidgets('with Talk mode left out of the build, the row is gone and the others stay', (tester) async {
      await settingsWith(tester, talkMode: false);

      expect(find.text('Talk mode and AI services'), findsNothing);
      expect(find.text('Open-source licenses'), findsOneWidget);
    });
  });
}
