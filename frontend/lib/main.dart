import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hu_accomponist/features/practice/Draggable_Recorder_Button.dart';
import 'package:hu_accomponist/features/practice/Drawing_Overlay.dart';
import 'package:hu_accomponist/integrations/scores/score_ink_store.dart';
import 'package:hu_accomponist/features/search/Music_Library_Page.dart';
import 'package:hu_accomponist/features/practice/score_osmd_view.dart';
import 'package:hu_accomponist/integrations/scores/score_models.dart';
import 'package:hu_accomponist/features/home/Vinyl_Loading_Screen.dart';
import 'package:hu_accomponist/features/auth/auth_gate.dart';
import 'package:hu_accomponist/features/onboarding/onboarding_store.dart';
import 'package:hu_accomponist/features/shell/shell_controller.dart';
import 'package:hu_accomponist/integrations/auth/auth_controller.dart';
import 'package:hu_accomponist/integrations/auth/auth_repository.dart';
import 'package:hu_accomponist/integrations/auth/session_store.dart';
import 'package:hu_accomponist/src/rust/models.dart';
import 'package:hu_accomponist/integrations/feedback/Phrase_send2_server.dart';
import 'package:hu_accomponist/integrations/feedback/Pull_back_phrase.dart';
import 'package:hu_accomponist/features/practice/Phrase_Feedback.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';
import 'package:hu_accomponist/features/practice/Practice_Tool_Buttons.dart';
import 'package:hu_accomponist/features/practice/Practice_Pen_Panel.dart';
import 'package:hu_accomponist/features/practice/Practice_Settings_Drawer.dart';
import 'package:hu_accomponist/features/practice/Exercise_Display.dart';
import 'package:hu_accomponist/features/practice/exercise_picker.dart';
import 'package:hu_accomponist/features/practice/Exercise_Session.dart';
import 'package:hu_accomponist/features/practice/live_judge.dart';
import 'package:hu_accomponist/features/practice/play_along_guide.dart';
import 'package:hu_accomponist/features/practice/practice_prefs.dart';
import 'package:hu_accomponist/features/practice/practice_prefs_sheet.dart';
import 'package:hu_accomponist/features/practice/score_practice_widgets.dart';
import 'package:hu_accomponist/features/practice/score_practice_session.dart';
import 'package:hu_accomponist/features/practice/score_practice_sheet.dart';
import 'package:hu_accomponist/features/practice/score_timeline.dart';
import 'package:hu_accomponist/features/practice/how_to_play_card.dart';
import 'package:hu_accomponist/integrations/guidelines/guideline_models.dart';
import 'package:hu_accomponist/integrations/guidelines/guideline_repository.dart';
import 'package:hu_accomponist/integrations/audio/Rust_Bridge.dart';

// Re-exported so anything that already reached for PhraseFeedback through
// main.dart keeps compiling after the enum moved to its own file.
export 'package:hu_accomponist/features/practice/Phrase_Feedback.dart';

// Audio capture is driven through integrations/audio/Audio_Native.dart,
// which owns the dart:ffi lookup of start_recording/stop_recording. Those
// are C symbols rather than flutter_rust_bridge calls because native_ffi
// marks listen_audio/stop_audio as `#[frb(ignore)]`; src/rust/api.dart
// therefore exposes only initSession/getUserData/notesStream.

Future<void> main() async {
  // Attempt to load the native Rust library, but never let a failure here
  // block the UI from rendering.
  // Right now this is expected to potentially fail while the Xcode/cargokit
  // integration for native_ffi is still being fixed; once that's sorted,
  // this try/catch can stay as a permanent safety net regardless.
  // Loading strategy differs per platform (static on iOS, dynamic
  // elsewhere), and failure must never block the UI — see Rust_Bridge.dart.
  await RustBridge.ensureInitialized();

  runApp(const HuAccumponistApp());
}

class HuAccumponistApp extends StatefulWidget {
  /// The auth state, the shell and the onboarding flag are handed in by
  /// tests; the app builds the real ones.
  const HuAccumponistApp({super.key, this.auth, this.shell, this.onboarding});

  final AuthController? auth;
  final ShellController? shell;
  final OnboardingStore? onboarding;

  @override
  State<HuAccumponistApp> createState() => _HuAccumponistAppState();
}

class _HuAccumponistAppState extends State<HuAccumponistApp> {
  late final OnboardingStore _onboarding =
      widget.onboarding ?? const OnboardingStore();
  late final ShellController _shell = widget.shell ?? ShellController();
  late final AuthController _auth =
      widget.auth ??
      AuthController(
        store: const SecureSessionStore(),
        repository: const ApiAuthRepository(),
        // A deleted account takes the tutorial flag with it, so whoever
        // signs up next on this device is shown the tutorial.
        onAccountDeleted: _onboarding.clear,
      );

  @override
  void initState() {
    super.initState();
    _auth.addListener(_resetShellWhenSignedOut);
    // Reads the stored session; the splash covers the wait. Until it
    // answers, the auth gate shows nothing of its own.
    if (_auth.status == AuthStatus.restoring) _auth.restore();
  }

  @override
  void dispose() {
    _auth.removeListener(_resetShellWhenSignedOut);
    if (widget.auth == null) _auth.dispose();
    if (widget.shell == null) _shell.dispose();
    super.dispose();
  }

  /// The next person to sign in starts on Practice, not wherever the last
  /// person left off.
  void _resetShellWhenSignedOut() {
    if (_auth.status == AuthStatus.signedOut) _shell.reset();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: PracticePalette.ivory,
        colorScheme: const ColorScheme.light(primary: PracticePalette.gold),
        // Every platform's default route animation is replaced with one
        // fade-through, so moving between screens feels like the same app
        // regardless of which device it is running on.
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          },
        ),
      ),
      // Above the Navigator, so a page pushed over the shell (the shelf
      // opened from the library, say) can still send the person to Practice.
      builder: (context, child) =>
          ShellScope(controller: _shell, child: child!),
      // App opens onto the vinyl spin-up splash, then the auth gate: the
      // login page when nobody is signed in, otherwise the app itself, on
      // Practice, with the disk bar along the bottom (see AppShell).
      home: Vinyl_Loading_Screen(
        child: AuthGate(auth: _auth, shell: _shell, onboarding: _onboarding),
      ),
    );
  }
}

class ScoreViewerPage extends StatefulWidget {
  final LoadedScore? selected;
  const ScoreViewerPage({super.key, this.selected});

  @override
  State<ScoreViewerPage> createState() => _ScoreViewerPageState();
}

class _ScoreViewerPageState extends State<ScoreViewerPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _isDrawingMode = false;
  bool _isErasing = false;
  bool _isRecording = false;

  PhraseFeedback _feedback = PhraseFeedback.none;

  /// The most recent analyzed phrase, handed to the feedback overlay for display.
  /// Purely presentational -- [_feedback] still drives the recorder halo,
  /// exactly as before.
  PhraseReport? _latestReport;

  /// The exercise being practised, if any. While set it replaces the score,
  /// and it is what Rust listens for and the backend judges against.
  ExerciseSession? _exercise;

  /// The loaded score's notes, once the score view has read them off it.
  ScoreTimeline? _timeline;

  /// How the player chose to practise this score (tempo, hands); asked the
  /// first time they record it.
  ScorePracticeSettings? _scoreSettings;

  /// The latest run through the score. Kept after recording stops, so its
  /// last phrases can still come back and mark their notes.
  ScorePracticeSession? _scoreSession;

  final RecorderController _recorder = RecorderController();

  /// Listening is stopped part-way through a run (the recorder's Pause).
  bool _paused = false;

  /// A tapped note is taken as the place to start from.
  bool _picking = false;

  /// Where the next run starts (null: the beginning), chosen beforehand.
  int? _startFromId;

  /// Where to go on from after a pause, picked on the score.
  int? _resumeFromId;

  bool get _listening => _isRecording && !_paused;

  /// While playing along, the score has the whole screen: every button
  /// steps aside, a tap pauses and a double tap finishes.
  bool get _immersive =>
      _listening && !_picking && _exercise == null && _scoreSession != null;

  /// "Tap to pause · double-tap to finish", for a moment as playing starts.
  bool _showTapHint = false;
  Timer? _tapHintTimer;

  /// The app shell this page sits in, if any (see [_syncShell]).
  ShellController? _shell;

  /// Looking back over a finished run on the score.
  bool _reviewing = false;

  /// While [_reviewing]: section of the run -> the time through shown.
  final Map<int, int> _shownTimes = {};

  /// The play-along guide's step on screen, or null.
  int? _guideStep;
  bool _guideChecked = false;
  final _recorderKey = GlobalKey();
  final _scoreKey = GlobalKey();
  final _settingsKey = GlobalKey();
  final _helpKey = GlobalKey();

  late final Map<GuideTarget, GlobalKey> _guideTargets = {
    GuideTarget.recorder: _recorderKey,
    GuideTarget.score: _scoreKey,
    GuideTarget.settings: _settingsKey,
    GuideTarget.help: _helpKey,
  };

  /// The first time a score is ready to play along with, the guide starts.
  Future<void> _maybeStartGuide() async {
    if (_guideChecked || !_scoreReady) return;
    _guideChecked = true;
    if (await const PlayAlongGuideStore().hasSeen()) return;
    if (mounted && !_isRecording) setState(() => _guideStep = 0);
  }

  void _endGuide() {
    const PlayAlongGuideStore().setSeen();
    setState(() => _guideStep = null);
  }

  void _openHelp() => PlayAlongHelpSheet.show(
    context,
    onReplayGuide: () {
      if (mounted && !_isRecording) setState(() => _guideStep = 0);
    },
  );
  final DrawingController _drawing = DrawingController();

  /// Call this from the Flutter-Rust-Bridge performance-result callback.
  void setPhraseFeedback(PhraseFeedback feedback) {
    if (!mounted) return;
    setState(() => _feedback = feedback);
  }

  /// Convenience entry point for a Rust result that reports whether a note
  /// was correct. Replace the bool with the Rust result type when it is wired
  /// into Flutter-Rust-Bridge.
  void applyPerformanceResult({required bool playedCorrectly}) {
    setPhraseFeedback(
      playedCorrectly ? PhraseFeedback.good : PhraseFeedback.off,
    );
  }

  void _onRecordingChanged(bool isRecording) {
    debugPrint('[Diagnostics] recording: $isRecording');
    if (mounted) {
      setState(() {
        _isRecording = isRecording;
        _paused = false;
      });
    }
    if (isRecording) _flashTapHint();
    if (!isRecording) {
      _exercise?.finish();
      _stopPicking();
      final session = _scoreSession;
      if (session != null) _finishScore(session);
    }
    if (isRecording) {
      // A fresh recording gets a fresh session — the backend assigns the
      // real session id on phrase 1's response (see below).
      _feedbackSessionId = null;
      setState(() => _latestReport = null);
      setPhraseFeedback(PhraseFeedback.none);
    }
  }

  // Backend-assigned session id (format "<date>-<piece title>"), captured
  // from phrase 1's response and reused for every later phrase in the
  // same recording so they land in one session directory. Null until
  // phrase 1 comes back.
  String? _feedbackSessionId;

  /// Tempo and metre assumed for bar numbering when the loaded score's
  /// MusicXML does not state them; named here so the assumption is visible
  /// rather than sitting as two literals inside the request.
  static const double _assumedBpm = 96;
  static const String _assumedTimeSignature = '4/4';

  double get _bpm => _score?.summary.tempoBpm ?? _assumedBpm;
  String get _timeSignature {
    final fromScore = _score?.summary.timeSignature ?? '';
    return fromScore.isEmpty ? _assumedTimeSignature : fromScore;
  }

  /// Ground-truth notes for the loaded piece, in the backend's
  /// expected_notes shape. Empty until something populates it: the OMR
  /// endpoints that would produce it are never called from this app.
  List<Map<String, dynamic>> _expectedNotes = const [];

  /// Fired by Draggable_Recorder_Button once per phrase, as soon as Rust
  /// finishes analyzing it. Sends it to /api/feedback/phrase, which
  /// judges and returns the phrase's report in the same response, then
  /// shows the result in the feedback card.
  ///
  /// `piece` now carries the real title and composer captured when the
  /// score was picked from the library (see [_piece]).
  ///
  /// Two inputs still have no source anywhere in the app, and are sent as
  /// documented defaults rather than invented values:
  ///
  ///   - `bpm` / `timeSignature`: taken from the score's MusicXML when it
  ///     states them, otherwise [_assumedBpm] and [_assumedTimeSignature].
  ///     The backend uses them only to number bars, so a wrong tempo
  ///     mislabels bar numbers but does not invalidate pitch scoring.
  ///
  ///   - `expectedNotes`: nothing turns the loaded MusicXML into expected
  ///     notes yet, so it is sent empty. The backend requires a non-empty
  ///     `expected_notes` to judge against, so phrases come back rejected
  ///     rather than scored — see the diagnostics line below, which says
  ///     so explicitly in the terminal instead of failing silently.
  Future<void> _onPhraseReceived(int phraseNumber, List<Notes> notes) async {
    final exercise = _exercise;
    if (exercise != null) {
      exercise.onRustBatch(notes);
      return;
    }
    final scoreSession = _scoreSession;
    if (scoreSession != null) {
      scoreSession.onRustBatch(notes);
      return;
    }

    if (_expectedNotes.isEmpty) {
      debugPrint(
        '[Diagnostics] phrase $phraseNumber: no expected_notes for '
        '"${_piece.title}" — nothing derives expected notes from the '
        'MusicXML yet, so the backend has nothing to judge against and '
        'will reject this phrase.',
      );
    }

    final report = await PhraseUploadService.sendPhrase(
      sessionId: _feedbackSessionId,
      phraseNumber: phraseNumber,
      bpm: _bpm,
      timeSignature: _timeSignature,
      piece: _piece,
      expectedNotes: _expectedNotes,
      userNotes: notes,
    );

    if (report == null || !mounted) return;

    _feedbackSessionId = report.sessionId;
    // Surfaces the report the call already returns. The request itself is
    // untouched -- this only consumes the response.
    setState(() => _latestReport = report);

    setPhraseFeedback(PhraseFeedback.forScore(report.scores.overall));
  }

  /// Identity of the loaded score, captured when it is picked from the
  /// library and sent with every phrase.
  ///
  /// `composedDate` is whatever the catalogue knows, often nothing: an
  /// empty date is honest; a fabricated one would be written into every
  /// stored phrase file.
  PieceInfo _piece = const PieceInfo(title: '', composer: '', composedDate: '');

  // Null until a score has been picked from the library.
  LoadedScore? _score;
  bool get _hasScore => _score != null;

  /// A score is showing whose notes can be played along with.
  bool get _scoreReady =>
      _exercise == null && _hasScore && !(_timeline?.isEmpty ?? true);

  // Kept as a stable field so picking another score reloads the same
  // WebView instead of rebuilding it.
  final ScoreOsmdController _osmd = ScoreOsmdController();

  // Pen ink drawn on each score, kept between visits.
  final ScoreInkStore _inkStore = const ScoreInkStore();

  /// Ink goes on the score itself (scrolling and zooming with it) when a
  /// score is showing; an exercise keeps the drawing overlay.
  bool get _inkOnScore => _exercise == null && _hasScore;

  // Swaps in a new score, or clears it if [selected] is null.
  void _setScore(LoadedScore? selected) {
    // A run of the old score can't go on with the new one: stop listening.
    if (_recorder.isRecording || _recorder.isPaused) {
      Future.microtask(_recorder.finish);
    }
    if (selected != null) _endExercise();
    _endScoreSession();
    _timeline = null;
    _scoreSettings = null;
    _startFromId = null;
    _resumeFromId = null;
    _picking = false;
    _guideChecked = false;
    _score = selected;
    _osmd.setInk('[]'); // until this score's own ink is read
    if (selected != null) _loadInk(selected.summary.id);
    _piece = selected == null
        ? const PieceInfo(title: '', composer: '', composedDate: '')
        : PieceInfo(
            title: selected.summary.title,
            composer: selected.summary.composer,
            composedDate: selected.summary.composedDate,
            // The backend resolves the score's tags from its id and checks
            // the matching authored guidelines on every phrase.
            scoreId: selected.summary.id,
            tags: selected.summary.tags,
          );
    _guides = const [];
    _guidesDismissed = false;
    if (selected != null) _loadGuides(selected.summary.id);
  }

  /// "How to play" guidelines for the loaded score, shown in a card before
  /// the first run.
  List<Guideline> _guides = const [];
  bool _guidesDismissed = false;
  final GuidelineRepository _guideRepository = const ApiGuidelineRepository();

  Future<void> _loadGuides(String scoreId) async {
    try {
      final guides = await _guideRepository.forScore(scoreId);
      if (!mounted || _score?.summary.id != scoreId) return;
      setState(() => _guides = guides);
    } on Object catch (e) {
      // No card is better than an error over the score.
      debugPrint('[Diagnostics] guidelines for score $scoreId: $e');
    }
  }

  Future<void> _loadInk(String scoreId) async {
    final saved = await _inkStore.load(scoreId);
    if (mounted && _score?.summary.id == scoreId) _osmd.setInk(saved);
  }

  /// Changes the pen tools and tells the score page what a touch now does.
  void _setPen(VoidCallback change) {
    setState(change);
    _osmd.setInkMode(
      _isErasing
          ? InkMode.eraser
          : _isDrawingMode
          ? InkMode.pen
          : InkMode.off,
      color: _penColor,
      width: _penSize,
    );
  }

  void _clearAnnotations() {
    _drawing.clear();
    _osmd.clearInk();
  }

  // ── Exercises ──────────────────────────────────────────────────────

  Future<void> _openExercisePicker() async {
    final choice = await ExercisePicker.show(context);
    if (choice == null || !mounted) return;
    setState(() {
      _endExercise();
      _endScoreSession();
      _exercise = ExerciseSession(
        exercise: choice.exercise,
        bpm: choice.bpm,
        octave: choice.octave,
        onReport: _onExerciseReport,
      );
      _latestReport = null;
      _feedback = PhraseFeedback.none;
    });
  }

  void _endExercise() {
    _exercise?.dispose();
    _exercise = null;
  }

  void _endScoreSession() {
    _scoreSession?.dispose();
    _scoreSession = null;
  }

  // ── Playing along with a score ─────────────────────────────────────

  ScorePracticeSettings _defaultSettings(ScoreTimeline timeline) =>
      ScorePracticeSettings(bpm: timeline.bpm.roundToDouble());

  /// Tempo and hands for this score. Returns null if the player backed out.
  Future<ScorePracticeSettings?> _chooseSettings({
    required String action,
  }) async {
    final timeline = _timeline;
    if (timeline == null) return null;
    final chosen = await ScorePracticeSheet.show(
      context,
      title: _piece.title,
      timeline: timeline,
      current: _scoreSettings ?? _defaultSettings(timeline),
      action: action,
    );
    if (chosen != null && mounted) {
      setState(() {
        // Another hand may not have the note the run was to start from.
        if (chosen.hands != _scoreSettings?.hands) _startFromId = null;
        _scoreSettings = chosen;
      });
    }
    return chosen;
  }

  /// Loads the score into Rust and counts the player in. False to cancel.
  Future<bool> _prepareScore() async {
    final timeline = _timeline;
    if (timeline == null) {
      _say('The score is still loading.');
      return false;
    }
    if (timeline.isEmpty) {
      _say("This score has no notes the app can follow.");
      return false;
    }
    final settings =
        _scoreSettings ?? await _chooseSettings(action: 'Start playing');
    if (settings == null || !mounted) return false;

    _endScoreSession();
    final session = ScorePracticeSession(
      piece: _piece,
      timeline: timeline,
      settings: settings,
      strictness: PracticePrefs.instance.strictness,
      onLive: _onScoreLive,
      onReport: _onExerciseReport,
    );
    setState(() {
      _scoreSession = session;
      _paused = false;
      _resumeFromId = null;
      _reviewing = false;
      _shownTimes.clear();
    });
    _stopPicking();
    _osmd.resetLive();
    _osmd.setColors(PracticePrefs.instance.colors);
    final error = await session.prepare(from: _startFromId);
    if (error != null && error != 'cancelled') _say(error);
    return error == null;
  }

  /// Going on after a pause: from the note picked, or the next one due.
  Future<bool> _resumeScore() async {
    final session = _scoreSession;
    if (session == null) return false;
    _stopPicking();
    final from = _resumeFromId;
    _resumeFromId = null;
    final error = from == null
        ? await session.resume()
        : await session.prepare(from: from);
    if (error != null && error != 'cancelled') _say(error);
    if (error == null && mounted) {
      setState(() => _paused = false);
      _flashTapHint();
    }
    return error == null;
  }

  void _flashTapHint() {
    if (_exercise != null || _scoreSession == null) return;
    _tapHintTimer?.cancel();
    setState(() => _showTapHint = true);
    _tapHintTimer = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => _showTapHint = false);
    });
  }

  /// The disk bar steps aside while the score has the whole screen.
  bool _immersiveShown = false;

  void _syncShell() {
    if (_immersiveShown != _immersive) {
      _immersiveShown = _immersive;
      debugPrint('[Diagnostics] immersive: $_immersive');
      _osmd.setImmersive(_immersive);
    }
    final shell = _shell = ShellScope.maybeOf(context);
    if (shell == null || shell.immersive == _immersive) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) shell.setImmersive(_immersive);
    });
  }

  /// The recorder's swiped-out buttons (see [RecorderAction]).
  Future<bool> _onRecorderAction(RecorderAction action) async {
    final session = _scoreSession;
    if (session == null) return false;
    // The paused screen shows at once; the last notes come in behind it.
    if (action != RecorderAction.restart) setState(() => _paused = true);
    await session.stopListening();
    // Too late: the run was finished, or another started, meanwhile.
    if (!mounted || !identical(session, _scoreSession)) return false;
    switch (action) {
      case RecorderAction.pause:
        return false;
      case RecorderAction.fromNote:
        _startPicking();
        return false;
      case RecorderAction.restart:
        setState(() => _paused = false);
        final error = await session.prepare(from: _startFromId);
        if (error != null && error != 'cancelled') _say(error);
        return error == null;
    }
  }

  void _startPicking() {
    _osmd.setPicking(true);
    if (mounted) setState(() => _picking = true);
  }

  void _stopPicking() {
    if (!_picking) return;
    _osmd.setPicking(false);
    if (mounted) setState(() => _picking = false);
  }

  /// Before a run, from the drawer: tap where the next run starts.
  void _chooseStart() {
    if (_timeline == null || _timeline!.isEmpty) return;
    _startPicking();
  }

  /// A note tapped while picking where to start. A repeated note is played
  /// more than once: before a run, its first time; after a pause, the time
  /// at or just before where the player had got to.
  void _onNotePick(List<int> ids) {
    if (!_picking) return;
    final timeline = _timeline;
    if (timeline == null) return;
    final settings = _scoreSettings ?? _defaultSettings(timeline);
    final playable = {
      for (final n in timeline.layout(bpm: settings.bpm, hands: settings.hands))
        n.noteId: n.startMs,
    };
    final candidates = ids.where(playable.containsKey).toList()
      ..sort((a, b) => playable[a]!.compareTo(playable[b]!));
    if (candidates.isEmpty) {
      _say("That note isn't in the hands you're playing.");
      return;
    }
    final session = _scoreSession;
    if (session != null && _paused) {
      final next = session.judge.next;
      final reached = next == null
          ? double.infinity
          : session.judge.note(next)!.startMs;
      final before = candidates.where((id) => playable[id]! <= reached);
      _resumeFromId = before.isEmpty ? candidates.first : before.last;
      _stopPicking();
      _recorder.resume();
      return;
    }
    setState(() => _startFromId = candidates.first);
    _stopPicking();
  }

  /// A note tapped while not playing: what happened to it, beside it.
  void _onNoteTap(List<int> ids) {
    final session = _scoreSession;
    if (session == null || _listening || _picking) return;
    final marked = ids.where(session.judge.marks.containsKey).toList();
    if (marked.isEmpty) return;
    final id = marked.reduce((a, b) => a > b ? a : b);
    final note = session.judge.note(id)!;
    final verdict = session.judge.marks[id]!;
    _osmd.showTip(id, [
      '${verdict.describe(note)} · bar ${LiveJudge.bar(note)}',
      ?ScoreSummarySheet.tipFor(session, id),
    ]);
  }

  /// The run is over: once its last phrases are judged, the summary.
  /// The run is over: the summary of what was played, as soon as the last
  /// notes are in. The server's tips are still on their way; the summary
  /// takes them in as they come.
  Future<void> _finishScore(ScorePracticeSession session) async {
    await session.stopListening();
    if (!mounted || !identical(session, _scoreSession)) return;
    await _openSummary(session);
  }

  Future<void> _openSummary(ScorePracticeSession session) async {
    final choice = await ScoreSummarySheet.show(context, session);
    if (choice == null || !mounted || !identical(session, _scoreSession)) {
      return;
    }
    setState(() => _reviewing = true);
    final id = choice.note;
    if (id == null) return;
    // A note a repeat plays twice: show the time through it was in.
    final found = session.judge.sectionOf(id);
    if (found != null && found.$1.repeated) {
      _showTime(session.judge.sections.indexOf(found.$1), found.$2);
    }
    _osmd.spotlight(id);
  }

  /// While reviewing: shows how [time] through [section] went.
  void _showTime(int section, int time) {
    final session = _scoreSession;
    if (session == null) return;
    setState(() => _shownTimes[section] = time);
    _osmd.live(
      LiveUpdate(showPass: session.judge.sections[section].times[time]),
    );
  }

  void _onScoreLive(LiveUpdate update) {
    if (!mounted) return;
    _osmd.live(update, follow: _listening);
  }

  void _onPrefsChanged() => _osmd.setColors(PracticePrefs.instance.colors);

  /// The bar a note is printed in, for the banners.
  int? _barOf(int? id) {
    if (id == null) return null;
    for (final n in _timeline?.notes ?? const <TimelineNote>[]) {
      if (n.id == id) return n.measureNumber < 1 ? 1 : n.measureNumber;
    }
    return null;
  }

  void _onExerciseReport(PhraseReport report) {
    if (!mounted) return;
    setState(() => _latestReport = report);
    setPhraseFeedback(PhraseFeedback.forScore(report.scores.overall));
  }

  /// Runs between the mic tap and the microphone opening: loads what Rust
  /// is to listen for (the exercise, or the score's notes) and counts the
  /// player in.
  Future<bool> _beforeCapture() async {
    final exercise = _exercise;
    if (exercise == null) {
      if (_hasScore) return _prepareScore();
      _say('Pick a score or an exercise first.');
      return false;
    }
    final error = await exercise.prepare();
    if (error != null && error != 'cancelled') _say(error);
    return error == null;
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  @override
  void didUpdateWidget(ScoreViewerPage old) {
    super.didUpdateWidget(old);
    // The shell keeps this page alive and hands it a new score when one is
    // picked from Search or the Shelf. Each pick is a freshly loaded score,
    // so identity tells a new pick from a rebuild.
    final picked = widget.selected;
    if (picked != null && !identical(picked, old.selected)) {
      setState(() => _setScore(picked));
    }
  }

  @override
  void dispose() {
    _tapHintTimer?.cancel();
    final shell = _shell;
    if (shell != null && shell.immersive) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => shell.setImmersive(false),
      );
    }
    _exercise?.dispose();
    _scoreSession?.dispose();
    PracticePrefs.instance.removeListener(_onPrefsChanged);
    _drawing.dispose();
    _osmd.canUndoInk.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _osmd.onInkChanged = (strokes) {
      final id = _score?.summary.id;
      if (id != null) _inkStore.save(id, strokes);
    };
    _osmd.onTimeline = (timeline) {
      if (mounted) setState(() => _timeline = timeline);
      _osmd.setColors(PracticePrefs.instance.colors);
      _maybeStartGuide();
    };
    _osmd.onNoteTap = _onNoteTap;
    _osmd.onNotePick = _onNotePick;
    // macOS: clicks on the score reach the page, not the layer over it.
    _osmd.onScreenTap = (count) {
      debugPrint(
        '[Diagnostics] screen tap x$count (immersive=$_immersive, '
        'recording=$_isRecording, paused=$_paused, picking=$_picking)',
      );
      if (!_immersive) return;
      if (count >= 2) {
        _recorder.finish();
      } else {
        // Shown at once: the recorder takes a moment to stop listening.
        setState(() => _paused = true);
        _recorder.pause();
      }
    };
    PracticePrefs.instance.addListener(_onPrefsChanged);
    PracticePrefs.instance.load();
    _setScore(widget.selected);
  }

  // Pen settings
  bool _showPenSettings = false;
  Color _penColor = PracticePalette.gold;
  double _penSize = 3.0;

  void _goToNavPage() async {
    final selected = await Navigator.of(context).push<LoadedScore>(
      PageRouteBuilder<LoadedScore>(
        transitionDuration: Motion.page,
        reverseTransitionDuration: Motion.base,
        pageBuilder: (context, animation, secondaryAnimation) =>
            const Music_Library_Page(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final eased = CurveTween(curve: Motion.enter).animate(animation);
          return SlideTransition(
            position: Tween(
              begin: const Offset(0.0, 1.0),
              end: Offset.zero,
            ).animate(eased),
            child: FadeTransition(opacity: eased, child: child),
          );
        },
      ),
    );

    if (selected != null) {
      setState(() {
        _setScore(selected);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncShell();
    final immersive = _immersive;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: PracticePalette.ivory,
      drawerEnableOpenDragGesture: false,
      drawer: PracticeSettingsDrawer(
        isRecording: _isRecording,
        feedback: _feedback,
        hasScore: _hasScore,
        onOpenLibrary: () {
          Navigator.pop(context);
          _goToNavPage();
        },
        onClearAnnotations: _clearAnnotations,
        onOpenExercises: () {
          Navigator.pop(context);
          _openExercisePicker();
        },
        onPlayAlong: _scoreReady && !_isRecording
            ? () {
                Navigator.pop(context);
                _chooseSettings(action: 'Done');
              }
            : null,
        onStartFrom: _scoreReady && !_isRecording
            ? () {
                Navigator.pop(context);
                _chooseStart();
              }
            : null,
        onNoteSettings: () {
          Navigator.pop(context);
          PracticePrefsSheet.show(context);
        },
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // ─────────────────────────────────────────────
            // CLEAN IVORY BACKGROUND
            // ─────────────────────────────────────────────
            const Positioned.fill(
              child: ColoredBox(color: PracticePalette.ivory),
            ),

            // Very subtle top border, matching the reference page.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 1,
                color: PracticePalette.lightGold.withValues(alpha: 0.35),
              ),
            ),

            // ─────────────────────────────────────────────
            // SCORE
            // ─────────────────────────────────────────────
            Positioned.fill(
              child: AnimatedPadding(
                duration: Motion.base,
                curve: Motion.standard,
                // Upright, the tools sit above and below the score, which
                // uses nearly the whole width. Turned sideways (as many
                // players hold a phone on a stand), they move to the sides
                // and the score gets nearly the whole height. While playing
                // along, the tools are away and the score has it all.
                padding: immersive
                    ? const EdgeInsets.all(Space.xxs)
                    : _landscape(context)
                    ? const EdgeInsets.fromLTRB(76, Space.xxs, 76, Space.xxs)
                    : EdgeInsets.fromLTRB(
                        Space.sm,
                        70,
                        Space.sm,
                        InShellPage.of(context) ? Space.sm : 76,
                      ),
                child: Container(
                  key: _scoreKey,
                  decoration: BoxDecoration(
                    color: PracticePalette.paper,
                    borderRadius: Radii.cardRadius,
                    border: Border.all(
                      color: PracticePalette.lightGold.withValues(alpha: 0.65),
                      width: 1,
                    ),
                    boxShadow: Elevations.overlay(PracticePalette.brown),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      if (_exercise != null)
                        Positioned.fill(
                          child: ExerciseDisplay(session: _exercise!),
                        )
                      else if (_hasScore)
                        Positioned.fill(
                          child: ScoreOsmdView(
                            musicXml: _score!.musicXml,
                            controller: _osmd,
                          ),
                        )
                      else
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(Space.xxl),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Select a score from the library',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: PracticePalette.mutedBrown,
                                    fontSize: 15,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                const SizedBox(height: Space.md),
                                TextButton.icon(
                                  onPressed: _openExercisePicker,
                                  icon: const Icon(Icons.music_note_rounded),
                                  label: const Text('or practise an exercise'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: PracticePalette.gold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Small restrained ornament at the top of the score area.
                      if (!immersive)
                        Positioned(
                          top: 18,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _ornamentRule(),
                                  const SizedBox(width: Space.sm),
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: PracticePalette.gold.withValues(
                                          alpha: 0.75,
                                        ),
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: Space.sm),
                                  _ornamentRule(),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Count-in before playing along with a score.
                      if (_scoreSession != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ScoreCountIn(session: _scoreSession!),
                          ),
                        ),

                      // Playing along: a tap pauses, a double tap finishes. A
                      // drag still scrolls the score.
                      if (immersive)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _recorder.pause,
                            onDoubleTap: _recorder.finish,
                            onVerticalDragUpdate: (d) =>
                                _osmd.scrollBy(-d.delta.dy),
                          ),
                        ),
                      if (immersive)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: Space.md,
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: _showTapHint ? 1 : 0,
                              duration: Motion.base,
                              child: const Center(
                                child: ScoreBanner(
                                  icon: Icons.touch_app_rounded,
                                  text: 'Tap to pause · double-tap to finish',
                                ),
                              ),
                            ),
                          ),
                        ),

                      // The latest phrase's verdict, one thin line.
                      if (!immersive)
                        Positioned(
                          top: Space.xs,
                          left: Space.sm,
                          right: Space.sm,
                          child: IgnorePointer(
                            child: Center(
                              child: PhraseStrip(report: _latestReport),
                            ),
                          ),
                        ),
                      // How to play this piece, from the authored
                      // guidelines its tags match. Before playing only.
                      if (_guides.isNotEmpty &&
                          !_guidesDismissed &&
                          !_isRecording &&
                          !_reviewing &&
                          !_picking &&
                          _startFromId == null &&
                          _exercise == null)
                        Positioned(
                          top: 40,
                          left: Space.sm,
                          right: Space.sm,
                          child: Center(
                            child: HowToPlayCard(
                              guidelines: _guides,
                              onDismiss: () =>
                                  setState(() => _guidesDismissed = true),
                            ),
                          ),
                        ),

                      // Picking a note to start from, or where the next run starts.
                      if (_picking ||
                          (_startFromId != null &&
                              !_isRecording &&
                              !_reviewing))
                        Positioned(
                          top: 40,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: _picking
                                ? ScoreBanner(
                                    icon: Icons.ads_click_rounded,
                                    text: 'Tap the note to start from',
                                    onClose: _stopPicking,
                                  )
                                : ScoreBanner(
                                    icon: Icons.flag_rounded,
                                    text:
                                        'Starts at bar ${_barOf(_startFromId)}',
                                    onClose: () =>
                                        setState(() => _startFromId = null),
                                  ),
                          ),
                        ),

                      // Paused: go on, or call it a day. Notes can be
                      // drawn on the score meanwhile.
                      if (_paused && _isRecording && !_picking)
                        Positioned(
                          top: 40,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: ScoreActionBar(
                              icon: Icons.pause_rounded,
                              text: 'Paused',
                              actions: [
                                ('Go on', _recorder.resume),
                                ('Finish', _recorder.finish),
                              ],
                            ),
                          ),
                        ),

                      // Looking back over the run just played.
                      if (_reviewing && !_isRecording && _scoreSession != null)
                        Positioned(
                          top: 40,
                          left: Space.sm,
                          right: Space.sm,
                          child: Center(
                            child: RunReviewPanel(
                              session: _scoreSession!,
                              shown: _shownTimes,
                              onShow: _showTime,
                              onSummary: () => _openSummary(_scoreSession!),
                              onClose: () => setState(() {
                                _reviewing = false;
                                _shownTimes.clear();
                              }),
                            ),
                          ),
                        ),

                      if (_exercise == null && _hasScore && !immersive)
                        Positioned(
                          right: Space.sm,
                          bottom: Space.sm,
                          child: ZoomButtons(
                            onZoomIn: () => _osmd.zoomBy(1.2),
                            onZoomOut: () => _osmd.zoomBy(1 / 1.2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // ─────────────────────────────────────────────
            // DRAWING OVERLAY
            // ─────────────────────────────────────────────
            if (_exercise != null)
              Positioned.fill(
                child: Drawing_Overlay(
                  controller: _drawing,
                  isDrawingMode: _isDrawingMode,
                  isErasing: _isErasing,
                  penColor: _penColor,
                  penSize: _penSize,
                ),
              ),

            // ─────────────────────────────────────────────
            // SETTINGS
            // ─────────────────────────────────────────────
            if (!immersive)
              Positioned(
                top: 16,
                left: 22,
                child: Flex(
                  // Upright, along the top; sideways, down the left edge.
                  direction: _landscape(context)
                      ? Axis.vertical
                      : Axis.horizontal,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PracticeToolButton(
                      key: _settingsKey,
                      icon: Icons.tune_rounded,
                      active: false,
                      color: PracticePalette.gold,
                      onTap: () => _scaffoldKey.currentState?.openDrawer(),
                    ),
                    const SizedBox(width: Space.xs, height: Space.xs),
                    PracticeToolButton(
                      icon: Icons.search_rounded,
                      active: false,
                      color: PracticePalette.gold,
                      onTap: _goToNavPage,
                    ),
                    // The colour key and the guide, once there is a score.
                    if (_exercise == null && _hasScore) ...[
                      const SizedBox(width: Space.xs, height: Space.xs),
                      PracticeToolButton(
                        key: _helpKey,
                        icon: Icons.question_mark_rounded,
                        active: false,
                        color: PracticePalette.gold,
                        onTap: _openHelp,
                      ),
                    ],
                  ],
                ),
              ),

            // ─────────────────────────────────────────────
            // TOP RIGHT DRAWING TOOLS
            // ─────────────────────────────────────────────
            if (!immersive)
              Positioned(
                top: 16,
                right: 22,
                child: Flex(
                  direction: _landscape(context)
                      ? Axis.vertical
                      : Axis.horizontal,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PracticeToolButton(
                      icon: Icons.edit_outlined,
                      active: _isDrawingMode,
                      color: PracticePalette.gold,
                      onTap: () {
                        _setPen(() {
                          _isDrawingMode = !_isDrawingMode;
                          if (_isDrawingMode) {
                            _isErasing = false;
                          }
                        });
                      },
                    ),
                    const SizedBox(width: Space.xs, height: Space.xs),
                    AnimatedBuilder(
                      animation: Listenable.merge([_drawing, _osmd.canUndoInk]),
                      builder: (_, _) => PracticeToolButton(
                        icon: Icons.undo_rounded,
                        active: false,
                        color: PracticePalette.gold,
                        enabled: _inkOnScore
                            ? _osmd.canUndoInk.value
                            : _drawing.canUndo,
                        onTap: _inkOnScore ? _osmd.undoInk : _drawing.undo,
                      ),
                    ),
                    const SizedBox(width: Space.xs, height: Space.xs),
                    PracticeToolButton(
                      icon: Icons.palette_outlined,
                      active: _showPenSettings,
                      color: PracticePalette.gold,
                      onTap: () {
                        setState(() {
                          _showPenSettings = !_showPenSettings;
                        });
                      },
                    ),
                  ],
                ),
              ),

            // ─────────────────────────────────────────────
            // PEN SETTINGS
            // ─────────────────────────────────────────────
            if (!immersive)
              Positioned(
                top: _landscape(context) ? 16 : 68,
                right: _landscape(context) ? 76 : 22,
                // Scales and fades out of the palette button rather than
                // appearing outright, so it reads as belonging to the
                // control that opened it.
                child: AnimatedScale(
                  scale: _showPenSettings ? 1 : 0.92,
                  duration: Motion.fast,
                  curve: Motion.enter,
                  alignment: Alignment.topRight,
                  child: AnimatedOpacity(
                    opacity: _showPenSettings ? 1 : 0,
                    duration: Motion.fast,
                    child: IgnorePointer(
                      ignoring: !_showPenSettings,
                      child: PracticePenPanel(
                        colors: PracticePalette.penColors,
                        selectedColor: _penColor,
                        penSize: _penSize,
                        isErasing: _isErasing,
                        onColorSelected: (color) {
                          _setPen(() {
                            _penColor = color;
                            _isErasing = false;
                            _isDrawingMode = true;
                          });
                        },
                        onSizeChanged: (size) {
                          _setPen(() {
                            _penSize = size;
                          });
                        },
                        onEraserToggled: () {
                          _setPen(() {
                            _isErasing = !_isErasing;
                            if (_isErasing) _isDrawingMode = false;
                          });
                        },
                      ),
                    ),
                  ),
                ),
              ),

            // The draggable control owns its own Rust-bridge notesStream()
            // recording pipeline; it reports UI toggle state here and, per
            // phrase, hands the notes off for upload + feedback polling.
            Draggable_Recorder_Button(
              key: _recorderKey,
              onToggle: _onRecordingChanged,
              onPhrase: _onPhraseReceived,
              onBeforeCapture: _beforeCapture,
              onError: _say,
              accent: PracticeSettingsDrawer.feedbackColor(_feedback),
              controller: _recorder,
              actionsEnabled: _exercise == null && _scoreSession != null,
              onAction: _onRecorderAction,
              onBeforeResume: _resumeScore,
              hidden: immersive,
            ),

            // ─────────────────────────────────────────────
            // EXIT (only when pushed; inside the shell there is no "back")
            // ─────────────────────────────────────────────
            if (!InShellPage.of(context) && !immersive)
              Positioned(
                right: 22,
                bottom: 20,
                child: PracticeBottomButton(
                  icon: Icons.arrow_back_rounded,
                  color: PracticePalette.mutedBrown,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),

            // The play-along guide, over everything.
            if (_guideStep != null)
              Positioned.fill(
                child: PlayAlongGuideOverlay(
                  step: _guideStep!,
                  targets: _guideTargets,
                  onNext: () => setState(() => _guideStep = _guideStep! + 1),
                  onBack: () => setState(() => _guideStep = _guideStep! - 1),
                  onDone: _endGuide,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static bool _landscape(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  static Widget _ornamentRule() => Container(
    width: 38,
    height: 1,
    color: PracticePalette.lightGold.withValues(alpha: 0.65),
  );
}
