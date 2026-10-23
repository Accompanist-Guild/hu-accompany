import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hu_accomponist/features/practice/play_along_guide.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    // The key's swatches animate for ever, which pumpAndSettle can't wait out.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child!,
    ),
    home: Scaffold(body: child),
  );

  testWidgets('the colour key names every mark', (tester) async {
    await tester.pumpWidget(
      host(const SingleChildScrollView(child: NoteLegend())),
    );
    for (final title in [
      'Perfect',
      'A little off',
      'Wrong key',
      'Missed',
      'Early',
      'Late',
      'Repeats',
      'Up next',
      'Heard',
    ]) {
      expect(find.textContaining(title), findsOneWidget, reason: title);
    }
  });

  testWidgets('the guide steps through, back and forth, and ends', (
    tester,
  ) async {
    var step = 0;
    var done = false;
    late StateSetter set;
    final recorder = GlobalKey();
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return Stack(
              children: [
                Positioned(
                  left: 20,
                  top: 400,
                  child: SizedBox(key: recorder, width: 80, height: 80),
                ),
                if (!done)
                  Positioned.fill(
                    child: PlayAlongGuideOverlay(
                      step: step,
                      targets: {GuideTarget.recorder: recorder},
                      onNext: () => set(() => step++),
                      onBack: () => set(() => step--),
                      onDone: () => set(() => done = true),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Play along with the score'), findsOneWidget);
    expect(find.text('STEP 1 OF ${playAlongGuide.length}'), findsOneWidget);

    await tester.tap(find.text('Show me'));
    await tester.pumpAndSettle();
    expect(find.text('Start and stop here'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Play along with the score'), findsOneWidget);

    for (var i = 0; i < playAlongGuide.length - 1; i++) {
      await tester.tap(find.text(i == 0 ? 'Show me' : 'Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Help is here'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
  });

  testWidgets('the colour steps show the key in the card', (tester) async {
    final step = playAlongGuide.indexWhere((s) => s.legend && !s.fullLegend);
    await tester.pumpWidget(
      host(
        PlayAlongGuideOverlay(
          step: step,
          targets: const {},
          onNext: () {},
          onBack: () {},
          onDone: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Wrong key'), findsOneWidget);
    expect(find.textContaining('Up next'), findsNothing, reason: 'next step');
  });

  testWidgets('help has the key and replays the guide', (tester) async {
    var replayed = false;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => PlayAlongHelpSheet.show(
              context,
              onReplayGuide: () => replayed = true,
            ),
            child: const Text('help'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('help'));
    await tester.pumpAndSettle();
    expect(find.text('What the colours mean'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Replay the guide'), 200);
    await tester.tap(find.text('Replay the guide'));
    await tester.pumpAndSettle();
    expect(replayed, isTrue);
    expect(find.text('What the colours mean'), findsNothing);
  });

  test('the guide is remembered once seen', () async {
    SharedPreferences.setMockInitialValues({});
    const store = PlayAlongGuideStore();
    expect(await store.hasSeen(), isFalse);
    await store.setSeen();
    expect(await store.hasSeen(), isTrue);
  });
}
