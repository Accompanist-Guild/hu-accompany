import 'dart:math' as math;

import 'package:hu_accomponist/features/practice/Exercise.dart';
import 'package:hu_accomponist/features/practice/practice_prefs.dart';
import 'package:hu_accomponist/integrations/feedback/Pull_back_phrase.dart';
import 'package:hu_accomponist/src/rust/models.dart';

/// How a written note went.
enum NoteResult {
  /// The right key, on time (see [Strictness]).
  perfect,

  /// The right key, a little early or late.
  close,

  /// The right key, too early or too late.
  early,
  late,

  /// Another key instead of this one.
  wrong,

  /// Not played (a later note was).
  missed;

  bool get isMistake => index >= NoteResult.early.index;
}

/// The verdict on one written note, with what the score needs to show it.
class NoteVerdict {
  final NoteResult result;

  /// The key played instead ([NoteResult.wrong]), as a MIDI number.
  final int? playedMidi;

  /// How far off the note came, in ms (negative = early).
  final double? offMs;

  /// [offMs] as a share of the time to the next written note, which is how
  /// far the score shifts the marker of where it was played.
  final double? offShare;

  const NoteVerdict(this.result, {this.playedMidi, this.offMs, this.offShare});

  /// One line about it, for the note's tip and the summary.
  String describe(ExpectedNote note) {
    final name = LiveJudge.name(note.midi);
    final ms = offMs?.abs().round();
    return switch (result) {
      NoteResult.perfect => '$name · on time',
      NoteResult.close =>
        '$name · a little ${offMs! < 0 ? 'early' : 'late'} ($ms ms)',
      NoteResult.early => '$name came early by $ms ms',
      NoteResult.late => '$name came late by $ms ms',
      NoteResult.wrong =>
        'Played ${LiveJudge.name(playedMidi ?? note.midi)} instead of $name',
      NoteResult.missed => '$name was not played',
    };
  }
}

/// What changed on the score after something was heard or judged.
class LiveUpdate {
  /// Notes whose verdict changed.
  final Map<int, NoteVerdict> marks;

  /// Notes whose verdict was taken back (a restart from an earlier note).
  final List<int> cleared;

  /// Notes the player just started: they give a little jump.
  final List<int> played;

  /// The notes due to be played now (they sway), or null when unchanged.
  final List<int>? due;

  const LiveUpdate({
    this.marks = const {},
    this.cleared = const [],
    this.played = const [],
    this.due,
  });

  bool get isEmpty =>
      marks.isEmpty && cleared.isEmpty && played.isEmpty && due == null;
}

/// Judges a performance note by note as Rust reports it, so the score can
/// show each note the moment it is played instead of after the bar has been
/// sent off and judged.
///
/// Rust sends three kinds of record (see native_ffi/README.md):
///  * a written note starting (`note_id` > 0, no end): it was played, at the
///    right pitch (Rust only recognises the written pitch). Its timing makes
///    it perfect, close, early or late ([Strictness]);
///  * a written note ending (with an end): nothing new;
///  * a stray key (`note_id` 0): a key the score doesn't have there. The
///    written note it was played instead of is [NoteResult.wrong].
/// A written note is [NoteResult.missed] once a later note has been played
/// and it never was. The backend's verdicts ([review]) can add to that.
class LiveJudge {
  LiveJudge(
    List<ExpectedNote> notes, {
    required double bpm,
    this.strictness = Strictness.normal,
  }) : notes = List.of(notes)..sort((a, b) => a.startMs.compareTo(b.startMs)),
       _beatMs = 60000.0 / bpm {
    _byId = {for (final n in this.notes) n.noteId: n};
  }

  final List<ExpectedNote> notes;
  final Strictness strictness;
  final double _beatMs;
  late final Map<int, ExpectedNote> _byId;

  final Map<int, NoteVerdict> marks = {};
  final Set<int> heard = {};

  /// What the backend said about each note, for its tip and the summary.
  final Map<int, List<PhraseFeedbackItem>> findings = {};

  /// Written note -> (start in score ms, key) of the stray played in its place.
  final Map<int, (double, int)> _strays = {};

  /// Notes before this score time are not part of the current run (it was
  /// started, or restarted, from a later note).
  double _fromMs = double.negativeInfinity;

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

  /// The detector's own timing jitter: nothing tighter than this can be
  /// asked of the player.
  static const double jitterMs = 40;

  ExpectedNote? note(int id) => _byId[id];

  /// How far off a note may be and still be perfect.
  double perfectMs(ExpectedNote n) =>
      math.max(jitterMs, strictness.perfectShare * _beatMs);

  /// How far off a note may be and still be close rather than early or
  /// late: most of its own length (a semiquaver has less room than a minim).
  double closeMs(ExpectedNote n) => math.max(
    perfectMs(n),
    (0.6 * math.min(n.durationMs, _beatMs)).clamp(120.0, 250.0) *
        strictness.closeScale,
  );

  /// One batch from Rust's notesStream.
  LiveUpdate add(List<Notes> batch, {DateTime? now}) {
    final marks = <int, NoteVerdict>{};
    final played = <int>[];
    for (final entry in batch) {
      final start = entry.startTimeMs;
      if (start == null) continue;
      final id = entry.noteId.toInt();
      if (id == 0) {
        if (entry.endTimeMs == null)
          _stray(_midiOf(entry.pitchHz), start, marks);
        continue;
      }
      final note = _byId[id];
      if (note == null || heard.contains(id) || note.startMs < _fromMs) {
        continue;
      }
      // A note ending that was never heard starting (e.g. read back at stop)
      // started all the same.
      _onset(note, start, marks);
      played.add(id);
      _lastStartMs = math.max(_lastStartMs ?? note.startMs, note.startMs);
      _lastHeardAt = now ?? DateTime.now();
    }
    return LiveUpdate(marks: marks, played: played);
  }

  void _onset(ExpectedNote note, double heardMs, Map<int, NoteVerdict> out) {
    final id = note.noteId;
    heard.add(id);
    final stray = _strays[id];
    if (stray != null && stray.$1 < heardMs - correctedAfterMs) {
      // A wrong key first, then the right one: it stays a wrong note.
    } else {
      _set(id, _timing(note, heardMs - note.startMs), out);
    }

    // Every earlier note not heard by now was missed.
    for (final n in notes) {
      if (n.startMs >= note.startMs - missedAfterMs) break;
      if (n.startMs < _fromMs ||
          n.grace ||
          heard.contains(n.noteId) ||
          marks.containsKey(n.noteId)) {
        continue;
      }
      _set(n.noteId, const NoteVerdict(NoteResult.missed), out);
    }
  }

  NoteVerdict _timing(ExpectedNote note, double offMs) {
    final share = offMs / _gapAfter(note);
    if (offMs.abs() <= perfectMs(note)) {
      return NoteVerdict(NoteResult.perfect, offMs: offMs, offShare: share);
    }
    if (offMs.abs() <= closeMs(note)) {
      return NoteVerdict(NoteResult.close, offMs: offMs, offShare: share);
    }
    return NoteVerdict(
      offMs < 0 ? NoteResult.early : NoteResult.late,
      offMs: offMs,
      offShare: share,
    );
  }

  /// Time from [note] to the next note that starts after it (or its length).
  double _gapAfter(ExpectedNote note) {
    for (final n in notes) {
      if (n.startMs > note.startMs + chordMs) return n.startMs - note.startMs;
    }
    return math.max(note.durationMs, 1);
  }

  void _stray(int playedMidi, double atMs, Map<int, NoteVerdict> out) {
    // The written note due nearest the stray, among those not yet played.
    ExpectedNote? target;
    var best = double.infinity;
    for (final n in notes) {
      if (n.startMs > atMs + strayReachMs) break;
      if (n.startMs < math.max(_fromMs, atMs - strayReachMs) ||
          n.grace ||
          heard.contains(n.noteId) ||
          marks.containsKey(n.noteId)) {
        continue;
      }
      // Nearest in time, then in pitch: a wrong note is usually next door.
      final distance =
          (n.startMs - atMs).abs() + 10.0 * (n.midi - playedMidi).abs();
      if (distance < best) {
        best = distance;
        target = n;
      }
    }
    if (target == null || _strays.containsKey(target.noteId)) return;
    _strays[target.noteId] = (atMs, playedMidi);
    _set(
      target.noteId,
      NoteVerdict(NoteResult.wrong, playedMidi: playedMidi),
      out,
    );
  }

  /// The backend's verdict on a phrase. It is kept for each note's tip, and
  /// notes it found missed or wrong that weren't heard are marked so; what
  /// it says about notes heard at the right pitch can't make them wrong.
  LiveUpdate review(PhraseReport report) {
    final out = <int, NoteVerdict>{};
    for (final item in report.feedback) {
      final raw = item.details['note_id'];
      if (raw is! num) continue;
      final note = _byId[raw.toInt()];
      if (note == null || note.startMs < _fromMs) continue;
      if (item.details['issue'] != 'extra_note') {
        findings.putIfAbsent(note.noteId, () => []).add(item);
      }
      if (note.grace || heard.contains(note.noteId)) continue;
      if (marks[note.noteId]?.result.isMistake ?? false) continue;
      final issue = item.details['issue'];
      if (item.category == 'notes' && issue == 'missing_note') {
        _set(note.noteId, const NoteVerdict(NoteResult.missed), out);
      } else if (item.category == 'pitch' &&
          item.details['user_note'] != item.details['expected_note']) {
        final userHz = item.details['user_hz'];
        _set(
          note.noteId,
          NoteVerdict(
            NoteResult.wrong,
            playedMidi: userHz is num ? _midiOf(userHz.toDouble()) : null,
          ),
          out,
        );
      }
    }
    return LiveUpdate(marks: out);
  }

  /// Starts the run over from [noteId] (the first note when null): every
  /// verdict from that note on is taken back; earlier ones stay.
  LiveUpdate restartFrom(int? noteId) {
    final from = noteId == null ? null : _byId[noteId];
    _fromMs = from?.startMs ?? double.negativeInfinity;
    final cleared = <int>[];
    for (final n in notes) {
      if (n.startMs < _fromMs) continue;
      if (marks.remove(n.noteId) != null) cleared.add(n.noteId);
      heard.remove(n.noteId);
      _strays.remove(n.noteId);
      findings.remove(n.noteId);
    }
    _lastStartMs = null;
    _lastHeardAt = null;
    _due = const [];
    return LiveUpdate(cleared: cleared, due: due());
  }

  /// The notes to play now: the first not played yet (with its chord), and
  /// those after it that the player has probably reached since the last note
  /// was heard. Null when the answer hasn't changed since the last call.
  List<int>? due({DateTime? now}) {
    ExpectedNote? first;
    for (final n in notes) {
      if (_open(n)) {
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
        if (_open(n)) result.add(n.noteId);
      }
    }
    if (_sameIds(result, _due)) return null;
    _due = result;
    return result;
  }

  /// The first note of the run not played yet, if any.
  int? get next {
    for (final n in notes) {
      if (_open(n)) return n.noteId;
    }
    return null;
  }

  bool _open(ExpectedNote n) =>
      n.startMs >= _fromMs &&
      !n.grace &&
      !heard.contains(n.noteId) &&
      !marks.containsKey(n.noteId);

  /// How many notes of the run ended each way.
  Map<NoteResult, int> get counts {
    final counts = {for (final r in NoteResult.values) r: 0};
    for (final v in marks.values) {
      counts[v.result] = counts[v.result]! + 1;
    }
    return counts;
  }

  void _set(int id, NoteVerdict verdict, Map<int, NoteVerdict> changed) {
    final old = marks[id];
    if (old != null &&
        old.result == verdict.result &&
        old.playedMidi == verdict.playedMidi &&
        old.offMs == verdict.offMs) {
      return;
    }
    marks[id] = verdict;
    changed[id] = verdict;
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

  /// "D♯" for MIDI 75: the octave says little on a page that shows where it is.
  static String name(int midi) => Exercise.noteName(
    midi,
  ).replaceAll(RegExp(r'-?\d+$'), '').replaceAll('#', '♯');

  static int bar(ExpectedNote n) => n.printedBar ?? n.bar + 1;
}
