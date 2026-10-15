import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hu_accomponist/config/app_constants.dart';
import 'package:hu_accomponist/features/hum/talk_consent.dart';

import 'support/auth_fakes.dart' show FakeLinkOpener;
import 'support/hum_fakes.dart' show MemoryTalkConsent;

/// Talk mode sends what you type or say to outside AI services (Google Gemini, and ElevenLabs for voice).
/// Apple requires asking first, so nothing may be sent until the person has said yes.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the stored answer', () {
    test('is "not yet" until the person agrees', () async {
      expect(await const PrefsTalkConsent().isGranted(), isFalse);
    });

    test('is remembered after agreeing, even by a fresh instance', () async {
      await const PrefsTalkConsent().grant();
      expect(await const PrefsTalkConsent().isGranted(), isTrue);
    });

    test('can be withdrawn', () async {
      const consent = PrefsTalkConsent();
      await consent.grant();
      await consent.withdraw();
      expect(await consent.isGranted(), isFalse);
    });

    test(
      'is kept under a versioned key, so a changed disclosure can ask again',
      () async {
        await const PrefsTalkConsent().grant();
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('talk_ai_consent_v2'), isTrue);
        // The wording changed (adults only, ElevenLabs may reuse voice), so an older yes does not count.
        SharedPreferences.setMockInitialValues({'talk_ai_consent_v1': true});
        expect(await const PrefsTalkConsent().isGranted(), isFalse);
      },
    );
  });

  group('the question', () {
    late MemoryTalkConsent consent;
    late FakeLinkOpener links;
    bool? answer;

    setUp(() {
      consent = MemoryTalkConsent();
      links = FakeLinkOpener();
      answer = null;
    });

    Future<void> pumpHost(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                answer = await ensureTalkConsent(
                  context,
                  consent: consent,
                  links: links,
                );
              },
              child: const Text('use talk mode'),
            ),
          ),
        ),
      );
    }

    testWidgets('does not ask again once they have agreed', (tester) async {
      consent.granted = true;
      await pumpHost(tester);
      await tester.tap(find.text('use talk mode'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(answer, isTrue);
    });

    testWidgets(
      'names who receives what, and says hum recordings are not among it',
      (tester) async {
        await pumpHost(tester);
        await tester.tap(find.text('use talk mode'));
        await tester.pumpAndSettle();

        final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
        final text = find
            .descendant(of: find.byWidget(dialog), matching: find.byType(Text))
            .evaluate()
            .map(
              (e) =>
                  (e.widget as Text).data ??
                  (e.widget as Text).textSpan?.toPlainText() ??
                  '',
            )
            .join('\n');
        expect(text, contains('Google Gemini'));
        expect(text, contains('ElevenLabs'));
        expect(text, contains('voice recording'));
        expect(text.toLowerCase(), contains('hum recordings are not'));
        // ElevenLabs keeps speech-to-text audio by default, so the box must not leave that out.
        expect(text, contains('ElevenLabs may keep your voice recording'));
        expect(text, contains('improve its own services'));
        expect(text, contains('Settings'));
        expect(find.text('Agree and continue'), findsOneWidget);
        expect(find.text('Not now'), findsOneWidget);
        expect(find.text('Privacy Policy'), findsOneWidget);
      },
    );

    bool agreeEnabled(WidgetTester tester) =>
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Agree and continue'),
            )
            .onPressed !=
        null;

    testWidgets(
      'asks for an 18-or-older confirmation, and agreeing waits for it',
      (tester) async {
        await pumpHost(tester);
        await tester.tap(find.text('use talk mode'));
        await tester.pumpAndSettle();

        expect(find.text('I am 18 or older'), findsOneWidget);
        expect(agreeEnabled(tester), isFalse);
        // Pressing the disabled button does nothing: no answer, nothing remembered.
        await tester.tap(find.text('Agree and continue'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(consent.granted, isFalse);

        await tester.tap(find.text('I am 18 or older'));
        await tester.pumpAndSettle();
        expect(agreeEnabled(tester), isTrue);

        // Unticking takes it back.
        await tester.tap(find.text('I am 18 or older'));
        await tester.pumpAndSettle();
        expect(agreeEnabled(tester), isFalse);
      },
    );

    testWidgets(
      'the box to tick stays reachable on the smallest iPhone that runs iOS 15',
      (tester) async {
        // 320 x 568 points: iPhone SE (1st generation).
        tester.view.physicalSize = const Size(320 * 2, 568 * 2);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await pumpHost(tester);
        await tester.tap(find.text('use talk mode'));
        await tester.pumpAndSettle();

        // If the box were off screen or covered, this tap would miss and Agree would stay off.
        await tester.tap(find.text('I am 18 or older'));
        await tester.pumpAndSettle();
        expect(agreeEnabled(tester), isTrue);
        await tester.tap(find.text('Agree and continue'));
        await tester.pumpAndSettle();
        expect(answer, isTrue);
      },
    );

    testWidgets('says the AI services are for adults only', (tester) async {
      await pumpHost(tester);
      await tester.tap(find.text('use talk mode'));
      await tester.pumpAndSettle();
      expect(find.textContaining('for adults'), findsOneWidget);
    });

    testWidgets('"Not now" works without the confirmation', (tester) async {
      await pumpHost(tester);
      await tester.tap(find.text('use talk mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(answer, isFalse);
    });

    testWidgets('agreeing is remembered and lets the request through', (
      tester,
    ) async {
      await pumpHost(tester);
      await tester.tap(find.text('use talk mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I am 18 or older'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agree and continue'));
      await tester.pumpAndSettle();

      expect(answer, isTrue);
      expect(consent.granted, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('"Not now" sends nothing and remembers nothing', (
      tester,
    ) async {
      await pumpHost(tester);
      await tester.tap(find.text('use talk mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(answer, isFalse);
      expect(consent.granted, isFalse);
    });

    testWidgets('tapping outside the box does not count as a yes or a no', (
      tester,
    ) async {
      await pumpHost(tester);
      await tester.tap(find.text('use talk mode'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(answer, isNull);
    });

    testWidgets('the Privacy Policy can be read without answering', (
      tester,
    ) async {
      await pumpHost(tester);
      await tester.tap(find.text('use talk mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Privacy Policy'));
      await tester.pumpAndSettle();

      expect(links.opened, [AppConstants.privacyPolicyUrl]);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(answer, isNull);
    });
  });
}
