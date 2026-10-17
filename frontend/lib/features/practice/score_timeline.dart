import 'package:hu_accomponist/features/practice/Exercise.dart';

/// Which hands of a keyboard score to practise. On a score with one staff
/// (or for another instrument) only [both] applies.
enum Hands {
  both('Both hands'),
  right('Right hand'),
  left('Left hand');

  const Hands(this.label);
  final String label;

  /// Whether a note on [staff] (0 = top) is played with these hands.
  bool plays(int staff) => switch (this) {
    Hands.both => true,
    Hands.right => staff == 0,
    Hands.left => staff >= 1,
  };
}

/// One written note of a score, as `assets/osmd/score_timeline.js` reads it:
/// repeats played out, tied notes joined, and timed at the written tempo.
class TimelineNote {
  /// 1-based, in time order. The score view finds the note on the page by
  /// it, and it is the id Rust and the backend tag the note with.
  final int id;
  final int midi;
  final double startMs;
  final double durationMs;

  /// The bar number printed on the score (0 for a pickup bar).
  final int measureNumber;

  /// How many bars had been played before this one (repeats included), so a
  /// repeated bar is a different place in the performance.
  final int visit;

  /// 0 = the top staff of the instrument (a pianist's right hand).
  final int staff;
  final bool grace;

  const TimelineNote({
    required this.id,
    required this.midi,
    required this.startMs,
    required this.durationMs,
    required this.measureNumber,
    required this.visit,
    required this.staff,
    required this.grace,
  });

  factory TimelineNote.fromJson(Map<String, dynamic> j) => TimelineNote(
    id: (j['id'] as num).toInt(),
    midi: (j['midi'] as num).toInt(),
    startMs: (j['startMs'] as num).toDouble(),
    durationMs: (j['durationMs'] as num).toDouble(),
    measureNumber: (j['measureNumber'] as num?)?.toInt() ?? 1,
    visit: (j['visit'] as num?)?.toInt() ?? 0,
    staff: (j['staff'] as num?)?.toInt() ?? 0,
    grace: j['grace'] == true,
  );
}

/// Everything a score says about when to play what, and its practice layout:
/// the notes Rust listens for and the backend judges against.
class ScoreTimeline {
  final List<TimelineNote> notes;

  /// The written tempo, in crotchets a minute.
  final double bpm;
  final String timeSignature;

  /// Staves of the instrument being played (2 for a piano).
  final int staves;

  const ScoreTimeline({
    required this.notes,
    required this.bpm,
    required this.timeSignature,
    required this.staves,
  });

  factory ScoreTimeline.fromJson(Map<String, dynamic> j) => ScoreTimeline(
    notes: [
      for (final n in (j['notes'] as List? ?? const []))
        TimelineNote.fromJson(n as Map<String, dynamic>),
    ],
    bpm: (j['bpm'] as num?)?.toDouble() ?? 100,
    timeSignature: j['timeSignature'] as String? ?? '4/4',
    staves: (j['staves'] as num?)?.toInt() ?? 1,
  );

  bool get isEmpty => notes.isEmpty;

  /// Whether the player can choose a hand (a score on two or more staves).
  bool get hasHands => staves >= 2;

  /// Bars are judged together until they span at least this long, so the
  /// feedback card speaks every few seconds, not after every short bar.
  static const double phraseMs = 4000;

  /// The notes to play at [bpm] crotchets a minute with [hands], in time
  /// order. [ExpectedNote.bar] is the phrase the note is judged in (a few
  /// bars, see [phraseMs]); [ExpectedNote.printedBar] the bar on the page.
  List<ExpectedNote> layout({required double bpm, Hands hands = Hands.both}) {
    final scale = this.bpm / bpm;
    final played = [
      for (final n in notes)
        if (!hasHands || hands.plays(n.staff)) n,
    ];
    if (played.isEmpty) return const [];

    // Phrases start on bar boundaries once the current one is long enough.
    final phraseOfVisit = <int, int>{};
    var phrase = 0;
    var phraseStart = played.first.startMs;
    var lastVisit = played.first.visit;
    for (final n in played) {
      if (n.visit != lastVisit) {
        if (n.startMs - phraseStart >= phraseMs / scale) {
          phrase++;
          phraseStart = n.startMs;
        }
        lastVisit = n.visit;
      }
      phraseOfVisit.putIfAbsent(n.visit, () => phrase);
    }

    final lastOfPhrase = <int, int>{};
    for (final n in played) {
      lastOfPhrase[phraseOfVisit[n.visit]!] = n.id;
    }
    return [
      for (final n in played)
        ExpectedNote(
          noteId: n.id,
          midi: n.midi,
          pitchHz: Exercise.midiToHz(n.midi),
          startMs: n.startMs * scale,
          durationMs: n.durationMs * scale,
          bar: phraseOfVisit[n.visit]!,
          isEnd: lastOfPhrase[phraseOfVisit[n.visit]!] == n.id,
          printedBar: n.measureNumber < 1 ? 1 : n.measureNumber,
          grace: n.grace,
        ),
    ];
  }

  /// native_ffi's `PieceData` for [layout], following the player's tempo
  /// (a whole piece isn't played to a metronome).
  static Map<String, dynamic> pieceData(
    String title,
    double bpm,
    List<ExpectedNote> notes,
  ) => {
    'piece_name': title,
    'curr_phase': 0,
    'instrument': null,
    'curr_music_phrase': 0,
    'timing': {'bpm': bpm, 'beat_unit': 4},
    'notes': [for (final n in notes) n.toRustJson()],
    'follow_tempo': true,
  };
}
