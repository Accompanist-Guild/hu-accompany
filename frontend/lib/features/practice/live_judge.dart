import 'dart:math' as math;

import 'package:hu_accomponist/features/practice/Exercise.dart';
import 'package:hu_accomponist/integrations/feedback/Pull_back_phrase.dart';
import 'package:hu_accomponist/src/rust/models.dart';

/// How a played note is shown on the score.
enum NoteMark { right, wrong }

/// What changed on the score after something was heard or judged.
class LiveUpdate {
  /// Notes whose mark changed.
  final Map<int, NoteMark> marks;

  /// Notes the player just started: they give a little jump.
  final List<int> played;

  /// The notes due to be played now (they shake), or null when unchanged.
  final List<int>? due;

  /// What went wrong, in words, newest last ("Played D instead of D♯ · bar 12").
  final List<String> mistakes;

  const LiveUpdate({
    this.marks = const {},
    this.played = const [],
    this.due,
    this.mistakes = const [],
  });

  bool get isEmpty =>
      marks.isEmpty && played.isEmpty && due == null && mistakes.isEmpty;
}

enum _Why { missed, wrongKey, timing, judged }

/// Judges a performance note by note as Rust reports it, so the score can
/// colour each note the moment it is played instead of after the bar has been
/// sent off and judged.
///
/// Rust sends three kinds of record (see native_ffi/README.md):
///  * a written note starting (`note_id` > 0, no end): it was played, at the
///    right pitch (Rust only recognises the written pitch). It is right unless
///    it came badly early or late;
///  * a written note ending (with an end): nothing new for the colours;
///  * a stray key (`note_id` 0): a key the score doesn't have there. The
///    written note it was played instead of is wrong.
/// A written note is also wrong once a later note has been played and it
/// never was (missed). The backend's verdicts ([review]) can add to that.
class LiveJudge {
  LiveJudge(List<ExpectedNote> notes, {required double bpm})
    : notes = List.of(notes)..sort((a, b) => a.startMs.compareTo(b.startMs)),
      _beatMs = 60000.0 / bpm {
    _byId = {for (final n in this.notes) n.noteId: n};
  }

  final List<ExpectedNote> notes;
  final double _beatMs;
  late final Map<int, ExpectedNote> _byId;

  final Map<int, NoteMark> marks = {};
  final Set<int> heard = {};
  final Map<int, _Why> _why = {};

  /// Written note -> start (score ms) of the stray key played in its place.
  final Map<int, double> _strayAt = {};

  /// The latest note heard starting: its written start, and when it arrived.
  double? _lastStartMs;
  DateTime? _lastHeardAt;
  List<int> _due = const [];

  /// Notes played together (a chord, both hands) start within this.
  static const double chordMs = 60;

  /// An earlier note is only counted missed once a note written at least
  /// this much later has been heard: notes reported a little out of order
  /// (a low note takes longer to recognise) must not flash red.
  static const double missedAfterMs = 150;

  /// A stray key counts as played instead of a written note due within this.
  static const double strayReachMs = 150;

  /// A stray this long before the written note itself is a wrong key played
  /// first (and then corrected); closer than this, it was the same attack.
  static const double correctedAfterMs = 120;

  /// Rust reports a note this long after it was played (the pitch network's
  /// look-ahead, plus the frames needed to be sure). Used to guess where the
  /// player is now, for [due].
  static const Duration reportLag = Duration(milliseconds: 350);

  /// How far ahead of the last heard note the player is assumed to have
  /// gone at most, when nothing more has been heard.
  static const double maxRunOnMs = 1500;

  /// How early or late a note may come and still be right: most of its own
  /// length (a semiquaver has less room than a minim), within limits.
  double toleranceMs(ExpectedNote n) =>
      (0.6 * math.min(n.durationMs, _beatMs)).clamp(120.0, 250.0);

  /// One batch from Rust's notesStream.
  LiveUpdate add(List<Notes> batch, {DateTime? now}) {
    final marks = <int, NoteMark>{};
    final played = <int>[];
    final mistakes = <String>[];
    for (final entry in batch) {
      final start = entry.startTimeMs;
      if (start == null) continue;
      final id = entry.noteId.toInt();
      if (id == 0) {
        if (entry.endTimeMs == null) {
          _stray(entry.pitchHz, start, marks, mistakes);
        }
        continue;
      }
      final note = _byId[id];
      if (note == null || heard.contains(id)) continue;
      // A note ending that was never heard starting (e.g. read back at stop)
      // started all the same.
      _onset(note, start, marks, mistakes);
      played.add(id);
      _lastStartMs = math.max(_lastStartMs ?? note.startMs, note.startMs);
      _lastHeardAt = now ?? DateTime.now();
    }
    return LiveUpdate(marks: marks, played: played, mistakes: mistakes);
  }

  void _onset(
    ExpectedNote note,
    double heardMs,
    Map<int, NoteMark> marks,
    List<String> mistakes,
  ) {
    final id = note.noteId;
    heard.add(id);
    final stray = _strayAt[id];
    final offBy = heardMs - note.startMs;
    if (stray != null && stray < heardMs - correctedAfterMs) {
      // A wrong key first, then the right one: still a mistake (already said).
    } else if (offBy.abs() > toleranceMs(note)) {
      _set(id, NoteMark.wrong, _Why.timing, marks);
      mistakes.add(
        '${_name(note)} came ${offBy < 0 ? 'early' : 'late'} · bar ${_bar(note)}',
      );
    } else {
      _set(id, NoteMark.right, null, marks);
    }

    // Every earlier note not heard by now was missed.
    for (final n in notes) {
      if (n.startMs >= note.startMs - missedAfterMs) break;
      if (n.grace ||
          heard.contains(n.noteId) ||
          this.marks.containsKey(n.noteId)) {
        continue;
      }
      _set(n.noteId, NoteMark.wrong, _Why.missed, marks);
      mistakes.add('Missed ${_name(n)} · bar ${_bar(n)}');
    }
  }

  void _stray(
    double pitchHz,
    double atMs,
    Map<int, NoteMark> marks,
    List<String> mistakes,
  ) {
    // The written note due nearest the stray, among those not yet played.
    ExpectedNote? target;
    var best = double.infinity;
    final strayMidi = _midiOf(pitchHz);
    for (final n in notes) {
      if (n.startMs > atMs + strayReachMs) break;
      if (n.grace ||
          heard.contains(n.noteId) ||
          marks.containsKey(n.noteId) ||
          this.marks.containsKey(n.noteId) ||
          n.startMs < atMs - strayReachMs) {
        continue;
      }
      // Nearest in time, then in pitch: a wrong note is usually next door.
      final distance =
          (n.startMs - atMs).abs() + 10.0 * (n.midi - strayMidi).abs();
      if (distance < best) {
        best = distance;
        target = n;
      }
    }
    if (target == null || _strayAt.containsKey(target.noteId)) return;
    _strayAt[target.noteId] = atMs;
    _set(target.noteId, NoteMark.wrong, _Why.wrongKey, marks);
    mistakes.add(
      'Played ${_pretty(Exercise.noteName(strayMidi))} instead of '
      '${_name(target)} · bar ${_bar(target)}',
    );
  }

  /// The backend's verdict on a phrase. Wrong notes, misses and badly timed
  /// notes it found turn red; what it says about notes the player was heard
  /// playing at the right pitch can't make them wrong notes.
  LiveUpdate review(PhraseReport report) {
    final marks = <int, NoteMark>{};
    for (final item in report.feedback) {
      final raw = item.details['note_id'];
      if (raw is! num) continue;
      final note = _byId[raw.toInt()];
      if (note == null || note.grace) continue;
      final issue = item.details['issue'];
      final wrong = switch (item.category) {
        'notes' => issue == 'missing_note' && !heard.contains(note.noteId),
        'pitch' =>
          !heard.contains(note.noteId) &&
              (item.severity == 'major' ||
                  item.details['user_note'] != item.details['expected_note']),
        'rhythm' => issue == 'onset' && item.severity == 'major',
        _ => false,
      };
      if (wrong && this.marks[note.noteId] != NoteMark.wrong) {
        _set(note.noteId, NoteMark.wrong, _Why.judged, marks);
      }
    }
    return LiveUpdate(marks: marks);
  }

  /// The notes to play now: the first not played yet (with its chord), and
  /// those after it that the player has probably reached since the last note
  /// was heard. Null when the answer hasn't changed since the last call.
  List<int>? due({DateTime? now}) {
    ExpectedNote? first;
    for (final n in notes) {
      if (!n.grace &&
          !heard.contains(n.noteId) &&
          !marks.containsKey(n.noteId)) {
        first = n;
        break;
      }
    }
    var result = <int>[];
    if (first != null) {
      var reach = first.startMs;
      final last = _lastStartMs, at = _lastHeardAt;
      if (last != null && at != null) {
        final since = (now ?? DateTime.now()).difference(at) + reportLag;
        reach = math.max(
          reach,
          last + math.min(since.inMilliseconds.toDouble(), maxRunOnMs),
        );
      }
      for (final n in notes) {
        if (n.startMs < first.startMs) continue;
        if (n.startMs > reach + chordMs) break;
        if (!n.grace &&
            !heard.contains(n.noteId) &&
            !marks.containsKey(n.noteId)) {
          result.add(n.noteId);
        }
      }
    }
    if (_sameIds(result, _due)) return null;
    _due = result;
    return result;
  }

  void _set(int id, NoteMark mark, _Why? why, Map<int, NoteMark> changed) {
    if (marks[id] == mark && _why[id] == why) return;
    marks[id] = mark;
    if (why == null) {
      _why.remove(id);
    } else {
      _why[id] = why;
    }
    changed[id] = mark;
  }

  static bool _sameIds(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static int _midiOf(double hz) =>
      (69 + 12 * math.log(hz / 440.0) / math.ln2).round();

  static String _name(ExpectedNote n) => _pretty(Exercise.noteName(n.midi));

  /// "D#5" -> "D♯": the octave says little on a page that shows where it is.
  static String _pretty(String name) =>
      name.replaceAll(RegExp(r'-?\d+$'), '').replaceAll('#', '♯');

  static int _bar(ExpectedNote n) => n.printedBar ?? n.bar + 1;
}
