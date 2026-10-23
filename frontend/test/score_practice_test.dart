import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hu_accomponist/features/practice/Exercise.dart';
import 'package:hu_accomponist/features/practice/Phrase_Assembler.dart';
import 'package:hu_accomponist/features/practice/live_judge.dart';
import 'package:hu_accomponist/features/practice/practice_prefs.dart';
import 'package:hu_accomponist/features/practice/score_practice_session.dart';
import 'package:hu_accomponist/features/practice/score_practice_widgets.dart';
import 'package:hu_accomponist/features/practice/score_timeline.dart';
import 'package:hu_accomponist/integrations/feedback/Phrase_send2_server.dart';
import 'package:hu_accomponist/integrations/feedback/Pull_back_phrase.dart';
import 'package:hu_accomponist/src/rust/models.dart';

// Playing along with a score: its timeline as the score view reads it, the
// note-by-note judging that colours the score, and the phrases sent off.
void main() {
  /// The opening of Für Elise as score_timeline.js reads it (3/8, 72 bpm, a
  /// pickup bar 0): E D# | E D# E B D C | A (with the left hand's A E A).
  ScoreTimeline elise() {
    const rh = [76, 75, 76, 75, 76, 71, 74, 72];
    final notes = <Map<String, dynamic>>[
      for (var i = 0; i < rh.length; i++)
        {
          'id': i + 1,
          'midi': rh[i],
          'startMs': i * 208.3,
          'durationMs': 208.3,
          'measureNumber': i < 2 ? 0 : 1,
          'visit': i < 2 ? 0 : 1,
          'staff': 0,
        },
      {
        'id': 9,
        'midi': 45,
        'startMs': 1666.7,
        'durationMs': 208.3,
        'measureNumber': 2,
        'visit': 2,
        'staff': 1,
      },
      {
        'id': 10,
        'midi': 69,
        'startMs': 1666.7,
        'durationMs': 416.7,
        'measureNumber': 2,
        'visit': 2,
        'staff': 0,
      },
      {
        'id': 11,
        'midi': 52,
        'startMs': 1875.0,
        'durationMs': 208.3,
        'measureNumber': 2,
        'visit': 2,
        'staff': 1,
      },
      {
        'id': 12,
        'midi': 57,
        'startMs': 2083.3,
        'durationMs': 208.3,
        'measureNumber': 2,
        'visit': 2,
        'staff': 1,
      },
    ];
    return ScoreTimeline.fromJson({
      'notes': notes,
      'bpm': 72,
      'timeSignature': '3/8',
      'staves': 2,
    });
  }

  /// Two bars (written bars 0 and 1, two notes each) with a repeat sign,
  /// then a third bar: played 0 1 0 1 2, 300 ms a note, at 60 bpm.
  ScoreTimeline repeated() {
    const measures = [0, 0, 1, 1, 0, 0, 1, 1, 2, 2];
    return ScoreTimeline.fromJson({
      'notes': [
        for (var i = 0; i < measures.length; i++)
          {
            'id': i + 1,
            'midi': 60 + i,
            'startMs': i * 300.0,
            'durationMs': 300.0,
            'measure': measures[i],
            'measureNumber': measures[i] + 1,
            'visit': i ~/ 2,
            'staff': 0,
          },
      ],
      'bpm': 60,
      'timeSignature': '2/4',
      'staves': 1,
    });
  }

  Notes heard(int id, double startMs, {double? endMs, double hz = 440}) =>
      Notes(
        noteId: BigInt.from(id),
        pitchHz: hz,
        startTimeMs: startMs,
        endTimeMs: endMs,
        durationMs: endMs == null ? null : endMs - startMs,
        isEnd: false,
      );

  group('timeline', () {
    test('lays the notes out at the chosen tempo', () {
      final notes = elise().layout(bpm: 36); // half the written tempo
      expect(notes.length, 12);
      expect(notes[1].startMs, closeTo(416.6, 0.1));
      expect(notes[1].durationMs, closeTo(416.6, 0.1));
      expect(notes.first.pitchHz, closeTo(659.26, 0.01));
    });

    test(
      'keeps the bar printed on the score, the pickup counting as bar 1',
      () {
        final notes = elise().layout(bpm: 72);
        expect(notes.map((n) => n.printedBar).toSet(), {1, 2});
        expect(notes.first.toBackendJson()['bar'], 1);
        expect(notes.last.toBackendJson()['bar'], 2);
      },
    );

    test('plays one hand alone', () {
      final right = elise().layout(bpm: 72, hands: Hands.right);
      final left = elise().layout(bpm: 72, hands: Hands.left);
      expect(right.map((n) => n.noteId), [1, 2, 3, 4, 5, 6, 7, 8, 10]);
      expect(left.map((n) => n.noteId), [9, 11, 12]);
    });

    test(
      'groups bars into phrases of a few seconds, ending on the last note',
      () {
        // At 72 bpm the three bars last 2.3 s: one phrase. At 24 bpm, 6.9 s.
        final fast = elise().layout(bpm: 72);
        expect(fast.map((n) => n.bar).toSet(), {0});
        expect(fast.where((n) => n.isEnd).map((n) => n.noteId), [12]);
        final slow = elise().layout(bpm: 24);
        expect(slow.map((n) => n.bar).toSet().length, greaterThan(1));
        for (final phrase in slow.map((n) => n.bar).toSet()) {
          final inPhrase = slow.where((n) => n.bar == phrase).toList();
          expect(
            inPhrase.where((n) => n.isEnd).length,
            1,
            reason: 'phrase $phrase',
          );
        }
      },
    );

    test('asks Rust to follow the player\'s tempo', () {
      final notes = elise().layout(bpm: 72);
      final piece = ScoreTimeline.pieceData('Für Elise', 72, notes);
      expect(piece['follow_tempo'], isTrue);
      expect((piece['notes'] as List).length, 12);
      expect(piece['timing'], {'bpm': 72.0, 'beat_unit': 4});
    });
  });

  group('live judge', () {
    late List<ExpectedNote> notes;
    late LiveJudge judge;
    final t0 = DateTime(2026, 10, 16, 12);

    setUp(() {
      notes = elise().layout(bpm: 72);
      judge = LiveJudge(notes, bpm: 72);
    });

    NoteResult? result(int id) => judge.marks[id]?.result;

    test('before anything is played, the opening note is due', () {
      expect(judge.due(now: t0), [1]);
    });

    test('a note played on time is perfect, and hops', () {
      final update = judge.add([heard(1, 0)], now: t0);
      expect(update.marks[1]!.result, NoteResult.perfect);
      expect(update.played, [1]);
    });

    test('a little off is close; further off is early or late', () {
      // At 72 bpm a beat is 833 ms: perfect within 83 ms; a semiquaver
      // (208 ms) is close up to 125 ms.
      judge.add([heard(1, 50)], now: t0);
      judge.add([heard(2, 208 + 100)], now: t0);
      judge.add([heard(3, 417 - 200)], now: t0);
      judge.add([heard(4, 625 + 200)], now: t0);
      expect(result(1), NoteResult.perfect);
      expect(result(2), NoteResult.close);
      expect(result(3), NoteResult.early);
      expect(result(4), NoteResult.late);
      expect(judge.marks[4]!.offMs, closeTo(200, 0.1));
      expect(judge.marks[4]!.describe(notes[3]), 'D♯ came late by 200 ms');
    });

    test('how strict timing is can be chosen', () {
      final relaxed = LiveJudge(notes, bpm: 72, strictness: Strictness.relaxed);
      relaxed.add([heard(1, 150)], now: t0);
      expect(relaxed.marks[1]!.result, NoteResult.perfect);
      final any = LiveJudge(notes, bpm: 72, strictness: Strictness.anyTime);
      any.add([heard(1, 2000)], now: t0);
      expect(any.marks[1]!.result, NoteResult.perfect);
    });

    test('the note ending later changes nothing', () {
      judge.add([heard(1, 0)], now: t0);
      expect(judge.add([heard(1, 0, endMs: 200)], now: t0).isEmpty, isTrue);
    });

    test('a note never played is missed once a later one is', () {
      judge.add([heard(1, 0)], now: t0);
      final update = judge.add([heard(3, 417)], now: t0); // note 2 skipped
      expect(update.marks[2]!.result, NoteResult.missed);
      expect(update.marks[3]!.result, NoteResult.perfect);
      expect(update.marks[2]!.describe(notes[1]), 'D♯ was not played');
    });

    test('a note heard a moment after a later one is not counted missed', () {
      // Left-hand A (9) and right-hand A (10) are written together; the
      // right hand is recognised first.
      for (var id = 1; id <= 8; id++) {
        judge.add([heard(id, notes[id - 1].startMs)], now: t0);
      }
      final first = judge.add([heard(10, 1666.7)], now: t0);
      expect(first.marks.containsKey(9), isFalse);
      expect(
        judge.add([heard(9, 1670)], now: t0).marks[9]!.result,
        NoteResult.perfect,
      );
    });

    test('a wrong key marks the note it replaced, with the key played', () {
      judge.add([heard(1, 0), heard(2, 208)], now: t0);
      // D (74) where E (76) is written, then the player carries on.
      final update = judge.add([heard(0, 420, hz: 587.33)], now: t0);
      expect(update.marks[3]!.result, NoteResult.wrong);
      expect(update.marks[3]!.playedMidi, 74);
      expect(update.marks[3]!.describe(notes[2]), 'Played D instead of E');
      final next = judge.add([heard(4, 625)], now: t0);
      expect(next.marks.keys, [4], reason: 'note 3 stays a wrong note');
    });

    test('a wrong key then the right one is still a mistake', () {
      judge.add([heard(1, 0), heard(2, 208)], now: t0);
      judge.add([heard(0, 380, hz: 587.33)], now: t0);
      final update = judge.add([heard(3, 560)], now: t0);
      expect(update.marks.containsKey(3), isFalse);
      expect(result(3), NoteResult.wrong);
    });

    test('the right key at the same moment as a "wrong" one is right', () {
      // The detector heard a neighbour as the note struck: not a mistake.
      judge.add([heard(1, 0), heard(2, 208)], now: t0);
      judge.add([heard(0, 410, hz: 587.33)], now: t0);
      judge.add([heard(3, 420)], now: t0);
      expect(result(3), NoteResult.perfect);
    });

    test('notes due follow the player on between reports', () {
      judge.add([heard(1, 0)], now: t0);
      expect(judge.due(now: t0), [2], reason: '350 ms of lag: note 2 is due');
      final later = judge.due(now: t0.add(const Duration(milliseconds: 300)));
      expect(later, [2, 3, 4]);
      expect(
        judge.due(now: t0.add(const Duration(milliseconds: 300))),
        isNull,
        reason: 'unchanged',
      );
    });

    test('starting again from a note keeps what came before it', () {
      judge.add([
        heard(1, 0),
        heard(2, 208),
        heard(3, 417),
        heard(4, 625),
      ], now: t0);
      final update = judge.restartFrom(3);
      expect(update.cleared, [3, 4]);
      expect(judge.marks.keys, [1, 2]);
      expect(judge.next, 3);
      expect(update.due, [3]);
      // Notes before the restart point are not missed by playing on.
      judge.add([heard(3, 417), heard(5, 833)], now: t0);
      expect(result(4), NoteResult.missed);
      expect(judge.marks.keys.toSet(), {1, 2, 3, 4, 5});
    });

    test('a run started part-way through ignores the notes before it', () {
      judge.restartFrom(5);
      judge.add([heard(5, 833), heard(6, 1042)], now: t0);
      expect(judge.marks.keys.toSet(), {5, 6}, reason: 'notes 1-4 not missed');
      judge.add([heard(1, 0)], now: t0);
      expect(judge.marks.containsKey(1), isFalse);
    });

    test('the backend can mark a missed note, but not one heard', () {
      judge.add([heard(1, 0)], now: t0);
      PhraseFeedbackItem finding(int id, String category, String issue) =>
          PhraseFeedbackItem(
            bars: 1,
            box: null,
            category: category,
            severity: 'major',
            confidence: 1,
            message: '',
            details: {
              'note_id': id,
              'issue': issue,
              'suggestion': 'Go slowly.',
            },
          );
      final report = PhraseReport(
        piece: const PieceInfo(title: '', composer: '', composedDate: ''),
        recordedAt: t0,
        phrase: 1,
        bpm: 72,
        timeSignature: '3/8',
        bars: const [1],
        scores: const PhraseScores(overall: 50),
        feedback: [
          finding(1, 'notes', 'missing_note'),
          finding(2, 'notes', 'missing_note'),
        ],
        sessionId: 's',
        storedAt: '',
      );
      final update = judge.review(report);
      expect(update.marks.keys, [2]);
      expect(update.marks[2]!.result, NoteResult.missed);
      expect(judge.findings[2]!.single.details['suggestion'], 'Go slowly.');
    });

    test('counts how the run went', () {
      judge.add([heard(1, 0), heard(2, 208 + 100), heard(4, 625)], now: t0);
      expect(judge.counts[NoteResult.perfect], 2);
      expect(judge.counts[NoteResult.close], 1);
      expect(judge.counts[NoteResult.missed], 1);
    });
  });

  group('repeats', () {
    late List<ExpectedNote> notes;
    late LiveJudge judge;
    setUp(() {
      notes = repeated().layout(bpm: 60);
      judge = LiveJudge(notes, bpm: 60);
    });

    test('knows which time through each bar is', () {
      expect(notes.map((n) => n.pass), [0, 0, 0, 0, 1, 1, 1, 1, 0, 0]);
      expect(notes[4].measure, notes[0].measure);
    });

    test('groups the score into sections, a repeat with each time', () {
      expect(judge.sections.length, 2);
      final first = judge.sections.first;
      expect(first.repeated, isTrue);
      expect(first.bars, 'Bars 1–2');
      expect(first.times, [
        [1, 2, 3, 4],
        [5, 6, 7, 8],
      ]);
      expect(judge.sections.last.times, [
        [9, 10],
      ]);
      expect(judge.sectionOf(6), (first, 1));
      expect(ScoreSection.timeName(1), '2nd time');
    });

    test('says once when the repeat starts, with its notes', () {
      expect(judge.repeatStarting(), isNull);
      judge.add([for (var i = 1; i <= 3; i++) heard(i, (i - 1) * 300.0)]);
      expect(judge.repeatStarting(), isNull, reason: 'note 4 is still to come');
      judge.add([heard(4, 900)]);
      expect(judge.repeatStarting(), [5, 6, 7, 8]);
      expect(judge.repeatStarting(), isNull);
      // The first time through keeps its verdicts.
      expect(judge.marks.keys, containsAll([1, 2, 3, 4]));
    });

    test('going on part-way through a repeat shows that time through', () {
      for (var i = 1; i <= 6; i++) {
        judge.add([heard(i, (i - 1) * 300.0)]);
      }
      judge.repeatStarting();
      final update = judge.restartFrom(7);
      expect(update.showPass, [5, 6, 7, 8]);
      expect(judge.repeatStarting(), isNull, reason: 'already under way');
      // From the start of the repeat, it is announced again.
      judge.restartFrom(5);
      expect(judge.repeatStarting(), [5, 6, 7, 8]);
    });
  });

  group('phrases sent to the backend', () {
    final notes = elise().layout(bpm: 72);

    test('only finished notes are judged', () {
      final assembler = PhraseAssembler(notes);
      expect(assembler.add([heard(1, 0)]), isEmpty);
      final phrases = assembler.flush([heard(1, 0)]);
      expect(phrases, isEmpty, reason: 'a start alone is not a played note');
    });

    test('a wrong key goes to the bar it was played in, without an id', () {
      final assembler = PhraseAssembler(notes);
      assembler.add([
        heard(1, 0, endMs: 200),
        heard(0, 420, endMs: 600, hz: 587.33),
      ]);
      final phrase = assembler.flush().single;
      expect(phrase.userNotes.map((n) => n.noteId.toInt()), [1, 0]);
      final wire = PhraseUploadService.userNoteToJson(phrase.userNotes.last);
      expect(wire.containsKey('note_id'), isFalse);
      expect(wire['pitch_hz'], 587.33);
    });
  });

  group('summary', () {
    testWidgets('shows what was played at once, then takes in the tips', (
      tester,
    ) async {
      final session = ScorePracticeSession(
        piece: const PieceInfo(
          title: 'Für Elise',
          composer: '',
          composedDate: '',
        ),
        timeline: elise(),
        settings: const ScorePracticeSettings(bpm: 72),
        onLive: (_) {},
        onReport: (_) {},
      );
      addTearDown(session.dispose);
      // Notes 1 and 3 played; 2 skipped; the player stopped after note 3.
      session.onRustBatch([heard(1, 0), heard(3, 417)]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => ScoreSummarySheet.show(context, session),
                child: const Text('stop'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('stop'));
      await tester.pumpAndSettle();
      // Only what was played counts: 2 of 3, not of the whole piece.
      expect(find.text('2 of 3 notes right'), findsOneWidget);
      expect(find.text('67'), findsOneWidget);
      expect(find.text('D♯ was not played'), findsOneWidget);
      expect(find.text('Go slowly.'), findsNothing);

      // The server's verdict comes in after the sheet is open.
      session.judge.review(
        PhraseReport(
          piece: session.piece,
          recordedAt: DateTime(2026),
          phrase: 1,
          bpm: 72,
          timeSignature: '3/8',
          bars: const [1],
          scores: const PhraseScores(overall: 60),
          feedback: const [
            PhraseFeedbackItem(
              bars: 1,
              box: null,
              category: 'notes',
              severity: 'major',
              confidence: 1,
              message: '',
              details: {
                'note_id': 2,
                'issue': 'missing_note',
                'suggestion': 'Go slowly.',
              },
            ),
          ],
          sessionId: 's',
          storedAt: '',
        ),
      );
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      session.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Go slowly.'), findsOneWidget);
    });

    testWidgets('folds a repeated section, with each time through', (
      tester,
    ) async {
      final session = ScorePracticeSession(
        piece: const PieceInfo(
          title: 'Two bars',
          composer: '',
          composedDate: '',
        ),
        timeline: repeated(),
        settings: const ScorePracticeSettings(bpm: 60),
        onLive: (_) {},
        onReport: (_) {},
      );
      addTearDown(session.dispose);
      // The first time clean; the second time note 6 is skipped.
      session.onRustBatch([
        for (final i in [1, 2, 3, 4, 5, 7, 8]) heard(i, (i - 1) * 300.0),
      ]);

      SummaryChoice? choice;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    choice = await ScoreSummarySheet.show(context, session),
                child: const Text('stop'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('stop'));
      await tester.pumpAndSettle();
      expect(find.text('Bars 1–2 · played 2 times'), findsOneWidget);
      expect(
        find.text('1st time: clean · 2nd time: 1 mistake'),
        findsOneWidget,
      );
      expect(find.textContaining('was not played'), findsNothing);

      await tester.tap(find.text('Bars 1–2 · played 2 times'));
      await tester.pumpAndSettle();
      expect(find.text('No mistakes'), findsOneWidget);
      expect(find.text('2ND TIME'), findsOneWidget);
      expect(find.textContaining('was not played'), findsOneWidget);

      await tester.tap(find.text('See it on the score'));
      await tester.pumpAndSettle();
      expect(choice?.note, isNull);
      expect(choice, isNotNull);
    });
  });
}
