import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:hu_accomponist/features/practice/Exercise.dart';
import 'package:hu_accomponist/features/practice/Phrase_Assembler.dart';
import 'package:hu_accomponist/features/practice/live_judge.dart';
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
/// player's tempo), counts the player in, colours each note as it is
/// played ([LiveJudge]), and sends the phrases to the backend for the
/// detailed feedback, which can mark more notes.
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
  }) : notes = timeline.layout(bpm: settings.bpm, hands: settings.hands);

  final PieceInfo piece;
  final ScoreTimeline timeline;
  final ScorePracticeSettings settings;
  final List<ExpectedNote> notes;

  /// What to change on the score.
  final void Function(LiveUpdate update) onLive;

  /// Each judged phrase, in order.
  final void Function(PhraseReport report) onReport;

  /// The count-in beat being shown (1..), or null.
  int? countIn;

  late LiveJudge _judge = LiveJudge(notes, bpm: settings.bpm);
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

  /// Runs before capture starts: loads the score into Rust and counts the
  /// player in. Returns an error message, or null to go ahead. Resolves one
  /// beat early, so the microphone is already open for the first note.
  Future<String?> prepare() async {
    if (notes.isEmpty) return 'There are no notes to play for these hands.';
    final error = await RustSession.load(
      ScoreTimeline.pieceData(piece.title, settings.bpm, notes),
    );
    if (error != null) return error;

    _judge = LiveJudge(notes, bpm: settings.bpm);
    _assembler = PhraseAssembler(notes);
    _sessionId = null;
    onLive(LiveUpdate(due: _judge.due() ?? const []));

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
    _ticker = Timer.periodic(_tick, (_) => _refreshDue());
    return null;
  }

  /// A batch from Rust's notesStream.
  void onRustBatch(List<Notes> batch) {
    if (_disposed) return;
    final update = _judge.add(batch);
    final due = _judge.due();
    if (!update.isEmpty || due != null) {
      onLive(
        LiveUpdate(
          marks: update.marks,
          played: update.played,
          mistakes: update.mistakes,
          due: due,
        ),
      );
    }
    _enqueue(_assembler.add(batch));
  }

  void _refreshDue() {
    final due = _judge.due();
    if (due != null && !_disposed) onLive(LiveUpdate(due: due));
  }

  /// Recording stopped: nothing is due any more, and whatever is unsent is
  /// judged, including the note that may still have been sounding.
  Future<void> finish() async {
    _ticker?.cancel();
    _countInTimer?.cancel();
    _setCountIn(null);
    if (!_disposed) onLive(const LiveUpdate(due: []));
    final leftovers = await RustSession.leftovers();
    if (_disposed) return;
    onRustBatch(leftovers);
    _enqueue(_assembler.flush());
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
    final update = _judge.review(report);
    if (!update.isEmpty) onLive(update);
    onReport(report);
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
