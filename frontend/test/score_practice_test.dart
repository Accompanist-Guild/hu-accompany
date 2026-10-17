import 'package:flutter_test/flutter_test.dart';

import 'package:hu_accomponist/features/practice/Exercise.dart';
import 'package:hu_accomponist/features/practice/Phrase_Assembler.dart';
import 'package:hu_accomponist/features/practice/live_judge.dart';
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

    test('before anything is played, the opening note is due', () {
      expect(judge.due(now: t0), [1]);
    });

    test('a note played in time turns right and hops', () {
      final update = judge.add([heard(1, 0)], now: t0);
      expect(update.marks, {1: NoteMark.right});
      expect(update.played, [1]);
      expect(update.mistakes, isEmpty);
    });

    test('the note ending later changes nothing', () {
      judge.add([heard(1, 0)], now: t0);
      expect(judge.add([heard(1, 0, endMs: 200)], now: t0).isEmpty, isTrue);
    });

    test('a note never played is missed once a later one is', () {
      judge.add([heard(1, 0)], now: t0);
      final update = judge.add([heard(3, 417)], now: t0); // note 2 skipped
      expect(update.marks, {3: NoteMark.right, 2: NoteMark.wrong});
      expect(update.mistakes, ['Missed D♯ · bar 1']);
    });

    test('a note heard a moment after a later one is not counted missed', () {
      // Left-hand A (9) and right-hand A (10) are written together; the
      // right hand is recognised first.
      for (var id = 1; id <= 8; id++) {
        judge.add([heard(id, notes[id - 1].startMs)], now: t0);
      }
      final first = judge.add([heard(10, 1666.7)], now: t0);
      expect(first.marks.containsKey(9), isFalse);
      expect(judge.add([heard(9, 1670)], now: t0).marks, {9: NoteMark.right});
    });

    test('a wrong key turns the note it replaced red and says which', () {
      judge.add([heard(1, 0), heard(2, 208)], now: t0);
      // D (74) where E (76) is written, then the player carries on.
      final update = judge.add([heard(0, 420, hz: 587.33)], now: t0);
      expect(update.marks, {3: NoteMark.wrong});
      expect(update.mistakes, ['Played D instead of E · bar 1']);
      final next = judge.add([heard(4, 625)], now: t0);
      expect(next.marks, {4: NoteMark.right}, reason: 'note 3 is already red');
    });

    test('a wrong key then the right one is still a mistake', () {
      judge.add([heard(1, 0), heard(2, 208)], now: t0);
      judge.add([heard(0, 380, hz: 587.33)], now: t0);
      final update = judge.add([heard(3, 560)], now: t0);
      expect(update.marks.containsKey(3), isFalse);
      expect(judge.marks[3], NoteMark.wrong);
    });

    test('the right key at the same moment as a "wrong" one is right', () {
      // The detector heard a neighbour as the note struck: not a mistake.
      judge.add([heard(1, 0), heard(2, 208)], now: t0);
      judge.add([heard(0, 410, hz: 587.33)], now: t0);
      expect(judge.add([heard(3, 420)], now: t0).marks, {3: NoteMark.right});
    });

    test('a badly late note is wrong, and says so', () {
      judge.add([heard(1, 0)], now: t0);
      final update = judge.add([heard(2, 208 + 300)], now: t0);
      expect(update.marks, {2: NoteMark.wrong});
      expect(update.mistakes.single, 'D♯ came late · bar 1');
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
            details: {'note_id': id, 'issue': issue},
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
      expect(judge.review(report).marks, {2: NoteMark.wrong});
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
}
