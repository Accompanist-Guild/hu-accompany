import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:hu_accomponist/features/practice/Exercise.dart';
import 'package:hu_accomponist/features/practice/Phrase_Assembler.dart';
import 'package:hu_accomponist/features/practice/live_judge.dart';
import 'package:hu_accomponist/features/practice/practice_prefs.dart';
import 'package:hu_accomponist/features/practice/score_timeline.dart';
import 'package:hu_accomponist/integrations/audio/Rust_Session.dart';
import 'package:hu_accomponist/integrations/feedback/Phrase_send2_server.dart';
import 'package:hu_accomponist/integrations/feedback/Pull_back_phrase.dart';
import 'package:hu_accomponist/src/rust/models.dart';

/// How a score is to be practised: the tempo and which hands.
class ScorePracticeSettings {
  final double bpm;
  final Hands hands;
  const ScorePracticeSettings({required this.bpm, this.hands = Hands.both});
}

/// One run through a score: loads its notes into Rust (following the
/// player's tempo), counts the player in, judges each note as it is played
/// ([LiveJudge]), and sends the phrases to the backend for the detailed
/// feedback. A run can be paused and continued, started over, or started
/// again from any note; the verdicts before that note stay.
///
/// The score view is driven through [onLive]; [countIn] is exposed through
/// [ChangeNotifier] for the count-in overlay.
class ScorePracticeSession extends ChangeNotifier {
  ScorePracticeSession({
    required this.piece,
    required this.timeline,
    required this.settings,
    required this.onLive,
    required this.onReport,
    Strictness strictness = Strictness.normal,
  }) : notes = timeline.layout(bpm: settings.bpm, hands: settings.hands) {
    judge = LiveJudge(notes, bpm: settings.bpm, strictness: strictness);
  }

  final PieceInfo piece;
  final ScoreTimeline timeline;
  final ScorePracticeSettings settings;
  final List<ExpectedNote> notes;

  /// What to change on the score.
  final void Function(LiveUpdate update) onLive;

  /// Each judged phrase, in order.
  final void Function(PhraseReport report) onReport;

  late final LiveJudge judge;

  /// Every phrase the backend judged this run.
  final List<PhraseReport> reports = [];

  /// The count-in beat being shown (1..), or null.
  int? countIn;

  /// The note this stretch of playing starts from (null = the first).
  int? fromId;

  PhraseAssembler _assembler = PhraseAssembler(const []);
  String? _sessionId;
  Future<void> _sendQueue = Future.value();
  Timer? _ticker;
  Timer? _countInTimer;
  bool _disposed = false;

  /// How often the notes due to be played are worked out again.
  static const Duration _tick = Duration(milliseconds: 80);

  /// Beats counted in, and how long each is: one bar of the score's own
  /// metre (two of a short one), in its beat (a dotted crotchet in 6/8).
  ({int beats, Duration beat}) get _countIn {
    final parts = timeline.timeSignature.split('/');
    var top = int.tryParse(parts.first) ?? 4;
    final bottom = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 4;
    var beatQuarters = 4 / bottom;
    if (bottom == 8 && top % 3 == 0 && top > 3) {
      top ~/= 3; // compound time: count the dotted beats
      beatQuarters *= 3;
    }
    if (top < 3) top *= 2;
    final ms = beatQuarters * 60000 / settings.bpm;
    return (beats: top, beat: Duration(microseconds: (ms * 1000).round()));
  }

  /// The notes from [fromId] on: what Rust listens for this stretch.
  List<ExpectedNote> _remaining() {
    final from = fromId == null ? null : judge.note(fromId!);
    return [
      for (final n in notes)
        if (from == null || n.startMs >= from.startMs) n,
    ];
  }

  /// Runs before capture starts: takes back the verdicts from [from] on
  /// ([fromId] when not given; the first note for a fresh run), loads the
  /// notes from there into Rust and counts the player in. Returns an error
  /// message, or null to go ahead. Resolves one beat early, so the
  /// microphone is already open for the first note.
  Future<String?> prepare({int? from, bool keepFrom = false}) async {
    if (!keepFrom) fromId = from;
    final remaining = _remaining();
    if (remaining.isEmpty) return 'There are no notes left to play from here.';
    final error = await RustSession.load(
      ScoreTimeline.pieceData(piece.title, settings.bpm, remaining),
    );
    if (error != null) return error;

    onLive(judge.restartFrom(fromId));
    // Phrases from the restart on will be judged again.
    final fromPhrase = (fromId == null ? 0 : judge.note(fromId!)?.bar ?? 0) + 1;
    reports.removeWhere((r) => r.phrase >= fromPhrase);
    _assembler = PhraseAssembler(remaining);

    final (:beats, :beat) = _countIn;
    for (var i = 1; i < beats; i++) {
      if (_disposed) return 'cancelled';
      _setCountIn(i);
      // Haptics only before capture starts: once the microphone is live, a
      // vibration can register as sound.
      HapticFeedback.mediumImpact();
      await Future<void>.delayed(beat);
    }
    if (_disposed) return 'cancelled';
    _setCountIn(beats);
    _countInTimer = Timer(beat, () => _setCountIn(null));
    _ticker?.cancel();
    _ticker = Timer.periodic(_tick, (_) => _refreshDue());
    return null;
  }

  /// Continuing after a pause: from the first note not played yet.
  Future<String?> resume() => prepare(from: judge.next ?? fromId);

  /// A batch from Rust's notesStream.
  void onRustBatch(List<Notes> batch) {
    if (_disposed) return;
    final update = judge.add(batch);
    final due = judge.due();
    final repeat = judge.repeatStarting();
    if (!update.isEmpty || due != null || repeat != null) {
      onLive(
        LiveUpdate(
          marks: update.marks,
          played: update.played,
          due: due,
          repeat: repeat,
        ),
      );
    }
    _enqueue(_assembler.add(batch));
  }

  void _refreshDue() {
    if (_disposed) return;
    final due = judge.due();
    final repeat = judge.repeatStarting();
    if (due != null || repeat != null) {
      onLive(LiveUpdate(due: due, repeat: repeat));
    }
  }

  /// The microphone stopped (a pause or the end): nothing is due any more,
  /// and whatever is unsent is judged, including a note still sounding.
  Future<void> stopListening() async {
    _ticker?.cancel();
    _countInTimer?.cancel();
    _setCountIn(null);
    if (!_disposed) onLive(const LiveUpdate(due: []));
    final leftovers = await RustSession.leftovers();
    if (_disposed) return;
    onRustBatch(leftovers);
    if (!_disposed) onLive(const LiveUpdate(due: []));
    _enqueue(_assembler.flush());
  }

  /// The run is over: everything heard is judged and sent.
  Future<void> finish() async {
    await stopListening();
    await _sendQueue;
  }

  void _enqueue(List<AssembledPhrase> phrases) {
    for (final phrase in phrases) {
      _sendQueue = _sendQueue.then((_) => _send(phrase));
    }
  }

  Future<void> _send(AssembledPhrase phrase) async {
    debugPrint(
      '[Diagnostics] phrase ${phrase.number}: ${phrase.userNotes.length} heard / '
      '${phrase.expectedNotes.length} written',
    );
    final report = await PhraseUploadService.sendPhrase(
      sessionId: _sessionId,
      phraseNumber: phrase.number,
      bpm: settings.bpm,
      timeSignature: timeline.timeSignature,
      piece: piece,
      expectedNotes: phrase.expectedNotes,
      userNotes: phrase.userNotes,
    );
    if (report == null || _disposed) return;
    _sessionId ??= report.sessionId;
    reports
      ..removeWhere((r) => r.phrase == report.phrase)
      ..add(report);
    final update = judge.review(report);
    if (!update.isEmpty) onLive(update);
    onReport(report);
    notifyListeners(); // the summary, if open, takes in the new tips
  }

  void _setCountIn(int? value) {
    if (_disposed || countIn == value) return;
    countIn = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _countInTimer?.cancel();
    super.dispose();
  }
}
