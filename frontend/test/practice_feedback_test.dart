import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hu_accomponist/features/practice/Exercise.dart';
import 'package:hu_accomponist/features/practice/Exercise_Display.dart';
import 'package:hu_accomponist/features/practice/Exercise_Session.dart';
import 'package:hu_accomponist/features/practice/practice_feedback.dart';
import 'package:hu_accomponist/integrations/feedback/Pull_back_phrase.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';

/// A report as /api/feedback/phrase returns it.
PhraseReport report({
  required int phrase,
  int overall = 70,
  List<Map<String, dynamic>> findings = const [],
}) => PhraseReport.fromJson({
  'phrase': phrase,
  'bpm': 60.0,
  'time_signature': '4/4',
  'bars': [phrase, phrase],
  'scores': {'overall': overall},
  'feedback': findings,
  'session_id': 's',
});

Map<String, dynamic> finding({
  required int bar,
  required String category,
  String severity = 'major',
  String message = 'You played D instead of E.',
  Map<String, dynamic> details = const {},
}) => {
  'bars': bar,
  'category': category,
  'severity': severity,
  'confidence': 1.0,
  'message': message,
  'details': {'suggestion': 'Practice this slowly.', ...details},
};

void main() {
  final exercise = Exercise.all.first; // C major scale: 16 notes, 4 bars
  final notes = exercise.layout(bpm: 60, octave: 5);

  group('notices from a judged bar', () {
    test('a note finding is tied to the written note it names', () {
      final notices = PracticeNotice.fromReport(
        report(
          phrase: 2,
          findings: [
            finding(bar: 2, category: 'pitch', details: {'note_id': 6}),
          ],
        ),
        notes,
      );
      expect(notices.single.noteId, 6);
      expect(notices.single.bar, 1); // zero-based, like the notes
      expect(notices.single.message, 'You played D instead of E.');
      expect(notices.single.suggestion, 'Practice this slowly.');
      expect(notices.single.positive, isFalse);
    });

    test('rhythm, articulation and missing notes are tied the same way', () {
      for (final (category, details) in [
        ('rhythm', {'note_id': 3}),
        ('articulation', {'note_id': 3}),
        ('notes', {'note_id': 3, 'issue': 'missing_note'}),
      ]) {
        final notice = PracticeNotice.fromReport(
          report(
            phrase: 1,
            findings: [finding(bar: 1, category: category, details: details)],
          ),
          notes,
        ).single;
        expect(notice.noteId, 3, reason: category);
      }
    });

    test('a finding about the whole bar is not tied to any note', () {
      final notice = PracticeNotice.fromReport(
        report(phrase: 3, findings: [finding(bar: 3, category: 'tempo')]),
        notes,
      ).single;
      expect(notice.noteId, isNull);
      expect(notice.bar, 2);
    });

    test('a note played but not written is not tied to a written note', () {
      // Its note_id is the id of the heard note, which could equal any
      // written note's id by coincidence.
      final notice = PracticeNotice.fromReport(
        report(
          phrase: 1,
          findings: [
            finding(
              bar: 1,
              category: 'notes',
              details: {'note_id': 2, 'issue': 'extra_note'},
            ),
          ],
        ),
        notes,
      ).single;
      expect(notice.noteId, isNull);
    });

    test('an id that is not in the exercise is not guessed at', () {
      final notice = PracticeNotice.fromReport(
        report(
          phrase: 1,
          findings: [
            finding(bar: 1, category: 'pitch', details: {'note_id': 999}),
          ],
        ),
        notes,
      ).single;
      expect(notice.noteId, isNull);
    });

    test('major findings come first', () {
      final notices = PracticeNotice.fromReport(
        report(
          phrase: 1,
          findings: [
            finding(
              bar: 1,
              category: 'rhythm',
              severity: 'minor',
              details: {'note_id': 1},
            ),
            finding(bar: 1, category: 'pitch', details: {'note_id': 2}),
          ],
        ),
        notes,
      );
      expect(notices.map((n) => n.category), ['pitch', 'rhythm']);
    });

    test('praise only when nothing was flagged and the score is high', () {
      final clean = PracticeNotice.fromReport(
        report(phrase: 2, overall: 96),
        notes,
      );
      expect(clean.single.positive, isTrue);
      expect(clean.single.bar, 1);

      expect(
        PracticeNotice.fromReport(report(phrase: 2, overall: 60), notes),
        isEmpty,
      );
      expect(
        PracticeNotice.fromReport(
          report(
            phrase: 2,
            overall: 96,
            findings: [finding(bar: 2, category: 'tempo')],
          ),
          notes,
        ).where((n) => n.positive),
        isEmpty,
      );
    });
  });

  group('exercise view', () {
    late ExerciseSession session;

    setUp(() {
      session = ExerciseSession(
        exercise: exercise,
        bpm: 60,
        octave: 5,
        onReport: (_) {},
      );
    });

    tearDown(() => session.dispose());

    Future<void> pumpDisplay(
      WidgetTester tester, {
      Duration linger = const Duration(seconds: 6),
    }) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExerciseDisplay(session: session, bubbleLinger: linger),
          ),
        ),
      );
    }

    /// The colour of the chip showing [name]'s box.
    Color? chipColor(WidgetTester tester, String name, {int at = 0}) {
      final box = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text(name).at(at),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      return (box.decoration as BoxDecoration).color;
    }

    testWidgets('the note to play now is red, and moves on with the music', (
      tester,
    ) async {
      await pumpDisplay(tester);
      expect(chipColor(tester, 'C5'), PracticePalette.ivory);

      // 0.3 s into the first note (one beat is a second at 60 bpm).
      session.startClock(
        DateTime.now().subtract(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 300));
      expect(chipColor(tester, 'C5'), PracticePalette.alert);
      expect(chipColor(tester, 'D5'), PracticePalette.ivory);

      // 1.4 s in: the second note's turn, and the first goes back to normal.
      session.startClock(
        DateTime.now().subtract(const Duration(milliseconds: 1400)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 300));
      expect(chipColor(tester, 'D5'), PracticePalette.alert);
      expect(chipColor(tester, 'C5'), PracticePalette.ivory);

      // The red chip's name stays readable.
      final text = tester.widget<AnimatedDefaultTextStyle>(
        find
            .ancestor(
              of: find.text('D5'),
              matching: find.byType(AnimatedDefaultTextStyle),
            )
            .first,
      );
      expect(text.style.color, PracticePalette.paper);

      // Once the exercise is over, nothing is highlighted.
      session.startClock(DateTime.now().subtract(const Duration(seconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 300));
      for (final name in ['C5', 'D5', 'E5']) {
        expect(chipColor(tester, name), PracticePalette.ivory);
      }
      session.downbeat = null;
    });

    testWidgets('a flagged note gets a bubble that dismisses itself', (
      tester,
    ) async {
      await pumpDisplay(tester, linger: const Duration(seconds: 2));
      expect(find.text('You played D instead of E.'), findsNothing);

      session.receive(
        report(
          phrase: 1,
          findings: [
            finding(bar: 1, category: 'pitch', details: {'note_id': 3}),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('You played D instead of E.'), findsOneWidget);
      expect(find.text('Practice this slowly.'), findsOneWidget);
      // And the note carries a badge.
      expect(find.byKey(const ValueKey('badge-3-pitch')), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      expect(find.text('You played D instead of E.'), findsNothing);
      // The badge stays for the rest of the run.
      expect(find.byKey(const ValueKey('badge-3-pitch')), findsOneWidget);
    });

    testWidgets('a bar with several findings shows one bubble, the worst', (
      tester,
    ) async {
      await pumpDisplay(tester);
      session.receive(
        report(
          phrase: 1,
          findings: [
            finding(
              bar: 1,
              category: 'rhythm',
              severity: 'minor',
              message: 'A little late.',
              details: {'note_id': 1},
            ),
            finding(
              bar: 1,
              category: 'pitch',
              message: 'Wrong note.',
              details: {'note_id': 2},
            ),
            finding(
              bar: 1,
              category: 'articulation',
              severity: 'minor',
              message: 'Too short.',
              details: {'note_id': 4},
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Wrong note.'), findsOneWidget);
      expect(find.text('A little late.'), findsNothing);
      expect(find.text('Too short.'), findsNothing);
      // All three are on their notes.
      expect(find.byKey(const ValueKey('badge-1-rhythm')), findsOneWidget);
      expect(find.byKey(const ValueKey('badge-2-pitch')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('badge-4-articulation')),
        findsOneWidget,
      );
    });

    testWidgets('a newer bar replaces the bubble instead of stacking', (
      tester,
    ) async {
      await pumpDisplay(tester);
      session.receive(
        report(
          phrase: 1,
          findings: [
            finding(
              bar: 1,
              category: 'pitch',
              message: 'First.',
              details: {'note_id': 1},
            ),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      session.receive(
        report(
          phrase: 2,
          findings: [
            finding(
              bar: 2,
              category: 'pitch',
              message: 'Second.',
              details: {'note_id': 6},
            ),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('First.'), findsNothing);
      expect(find.text('Second.'), findsOneWidget);
    });

    testWidgets('a clean bar is praised, and a bar-wide finding has a bubble', (
      tester,
    ) async {
      await pumpDisplay(tester);
      session.receive(report(phrase: 1, overall: 97));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Nice, that bar was clean.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      session.receive(
        report(
          phrase: 2,
          findings: [
            finding(
              bar: 2,
              category: 'tempo',
              severity: 'minor',
              message: 'You sped up.',
            ),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('You sped up.'), findsOneWidget);
    });

    testWidgets('nothing to say means no bubble and no history button', (
      tester,
    ) async {
      await pumpDisplay(tester);
      session.receive(report(phrase: 1, overall: 60));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);
      expect(find.text('Nice, that bar was clean.'), findsNothing);
    });

    testWidgets('earlier feedback can be looked back at', (tester) async {
      await pumpDisplay(tester, linger: const Duration(milliseconds: 500));
      session.receive(
        report(
          phrase: 1,
          findings: [
            finding(
              bar: 1,
              category: 'pitch',
              message: 'Wrong note.',
              details: {'note_id': 2},
            ),
          ],
        ),
      );
      session.receive(
        report(
          phrase: 2,
          findings: [
            finding(
              bar: 2,
              category: 'rhythm',
              message: 'Rushed.',
              details: {'note_id': 6},
            ),
          ],
        ),
      );
      await tester.pump(const Duration(seconds: 2)); // bubbles gone

      await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.text('FEEDBACK SO FAR'), findsOneWidget);
      expect(
        find.textContaining('Wrong note.', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Rushed.', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Bar 2', findRichText: true), findsOneWidget);
    });

    test('the phrase card is spared the findings the notes already show', () {
      final anchored = PhraseFeedbackItem.fromJson(
        finding(bar: 1, category: 'pitch', details: {'note_id': 3}),
      );
      final bar = PhraseFeedbackItem.fromJson(
        finding(bar: 1, category: 'tempo'),
      );
      expect(session.isAnchored(anchored), isTrue);
      expect(session.isAnchored(bar), isFalse);
    });

    testWidgets('the bubble stays on the page for notes at either edge', (
      tester,
    ) async {
      await pumpDisplay(tester);
      for (final (phrase, noteId, message) in [
        (2, 5, 'First note of the bar.'), // left edge
        (3, 12, 'Last note of the bar.'), // right edge
      ]) {
        session.receive(
          report(
            phrase: phrase,
            findings: [
              finding(
                bar: phrase,
                category: 'pitch',
                message: message,
                details: {'note_id': noteId},
              ),
            ],
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        final rect = tester.getRect(find.text(message));
        expect(rect.left, greaterThanOrEqualTo(0), reason: message);
        expect(rect.right, lessThanOrEqualTo(500), reason: message);
        expect(rect.top, greaterThanOrEqualTo(0), reason: message);
      }
    });
  });
}
