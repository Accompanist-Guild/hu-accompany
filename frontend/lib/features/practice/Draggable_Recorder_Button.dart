import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';
import 'package:hu_accomponist/features/practice/Recorder_Painters.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:hu_accomponist/src/rust/models.dart';
import 'package:hu_accomponist/src/rust/api.dart';
import 'package:hu_accomponist/integrations/audio/Audio_Native.dart';
import 'package:hu_accomponist/integrations/audio/Rust_Bridge.dart';

/// What the buttons that swipe out of the recorder do (see
/// [Draggable_Recorder_Button.actionsEnabled]).
enum RecorderAction {
  /// Stop listening for now, to look around the score; tap to go on.
  pause,

  /// Start over from the first note.
  restart,

  /// Pick a note on the score to start again from.
  fromNote,
}

/// Lets the practice screen go on with a paused recording, e.g. once the
/// player has picked the note to start again from.
class RecorderController {
  _Draggable_Recorder_ButtonState? _state;

  bool get isPaused => _state?._paused ?? false;
  bool get isRecording => _state?._isRecording ?? false;

  /// Continues a paused recording (through [Draggable_Recorder_Button.onBeforeResume]).
  Future<void> resume() async => _state?._resume();

  /// Pauses the recording, as the Pause button does.
  Future<void> pause() async {
    if (isRecording) await _state?._act(RecorderAction.pause);
  }

  /// Ends the recording (running or paused), as tapping the button does.
  Future<void> finish() async {
    final state = _state;
    if (state == null) return;
    if (state._isRecording) {
      await state._toggle();
    } else if (state._paused) {
      await state._act(null);
    }
  }
}

class Draggable_Recorder_Button extends StatefulWidget {
  final void Function(bool isRecording) onToggle;

  /// Whether swiping right on the button while recording (or paused) offers
  /// [RecorderAction]s. A paused recording offers Finish instead of Pause.
  final bool actionsEnabled;

  /// Carries out an action. For [RecorderAction.restart] it also gets the
  /// piece ready again (count-in) and returns whether to start listening;
  /// for the others the return value is ignored.
  final Future<bool> Function(RecorderAction action)? onAction;

  /// Runs before listening again after a pause; false keeps it paused.
  final Future<bool> Function()? onBeforeResume;

  final RecorderController? controller;

  /// Out of sight (and out of reach) while the score has the whole screen;
  /// the recording goes on.
  final bool hidden;

  /// Tints the pulse halo — lets the score screen reflect the last phrase's
  /// verdict without any extra chrome on top of the button.
  final Color accent;

  /// Fired once per phrase, the moment Rust finishes analyzing it.
  /// [phraseNumber] is 1-indexed within this recording. The backend owns
  /// session grouping (see Phrase_Send2_Server.dart) — this widget no
  /// longer invents a client-side session id.
  final void Function(int phraseNumber, List<Notes> notes)? onPhrase;

  /// Runs after the tap and before the microphone starts; return false to
  /// cancel the recording. The practice screen uses it to load the piece
  /// into Rust and count the player in.
  final Future<bool> Function()? onBeforeCapture;

  /// Called with a message for the player when recording cannot start
  /// (microphone permission, no microphone) or goes wrong while it runs.
  final void Function(String message)? onError;

  const Draggable_Recorder_Button({
    super.key,
    required this.onToggle,
    this.onPhrase,
    this.onBeforeCapture,
    this.onError,
    this.accent = const Color(0xFF9A7A2C),
    this.actionsEnabled = false,
    this.onAction,
    this.onBeforeResume,
    this.controller,
    this.hidden = false,
  });

  @override
  State<Draggable_Recorder_Button> createState() =>
      _Draggable_Recorder_ButtonState();
}

class _Draggable_Recorder_ButtonState extends State<Draggable_Recorder_Button>
    with SingleTickerProviderStateMixin {
  bool _isRecording = false;

  /// Stopped listening part-way through, to go on later.
  bool _paused = false;

  /// The swiped-out action buttons are showing.
  bool _fanOpen = false;
  Timer? _fanTimer;

  /// Sideways travel of the current swipe on the button.
  double _swipe = 0;

  static const double _fanWidth = 132.0;

  /// True while [Draggable_Recorder_Button.onBeforeCapture] runs, so a
  /// second tap during the count-in is ignored.
  bool _starting = false;
  Timer? _timer;

  /// Both tick far more often than the rest of the button changes — the
  /// timer once a second, the drag once a frame — and both used to go
  /// through setState, rebuilding the glass lens and the two painters
  /// along with them. Kept as notifiers so each drives only the one
  /// subtree that reads it.
  final ValueNotifier<Duration> _elapsed = ValueNotifier(Duration.zero);
  final ValueNotifier<Offset> _position = ValueNotifier(const Offset(20, 400));

  // Owns the live notesStream() subscription for the current recording.
  // Null whenever we're not recording.
  StreamSubscription<List<Notes>>? _phraseSubscription;
  int _phraseNumber = 0;

  /// The last audio problem shown, so a persistent one is said once.
  String? _lastProblem;

  // Approximate footprint of the whole draggable widget (label row +
  // spacing + the 100x100 icon stack) — used to keep it fully on-screen
  // when dragged, since Positioned won't clamp this for us.
  static const double _buttonWidth = 100.0;
  static const double _buttonHeight = 156.0;

  // Drives both the idle "tap to record" breathing halo and the faster
  // recording pulse — same controller, different period.
  late final AnimationController _pulseCtrl;

  static const Duration _idlePeriod = Duration(milliseconds: 2400);
  static const Duration _recordingPeriod = Duration(milliseconds: 1100);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: _idlePeriod)
      ..repeat();
    widget.controller?._state = this;
  }

  @override
  void didUpdateWidget(Draggable_Recorder_Button old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._state = null;
      widget.controller?._state = this;
    }
    if (widget.hidden && !old.hidden) {
      _fanTimer?.cancel();
      _fanOpen = false;
    }
  }

  @override
  void dispose() {
    widget.controller?._state = null;
    _fanTimer?.cancel();
    _timer?.cancel();
    // Leaving the screen mid-recording must not leave the microphone open.
    if (_isRecording) AudioNative().end();
    _phraseSubscription?.cancel();
    _pulseCtrl.dispose();
    _elapsed.dispose();
    _position.dispose();
    super.dispose();
  }

  /// Subscribes to Rust's notes and opens the microphone. Returns null when
  /// recording, or a message for the player when it could not start.
  Future<String?> _startRecording() async {
    _phraseNumber = 0;
    _lastProblem = null;

    try {
      await RustBridge.ensureInitialized();

      // Subscribe before starting capture, so no phrase emitted in the
      // first few milliseconds is missed.
      _phraseSubscription = notesStream().listen(
        (List<Notes> phrase) {
          _phraseNumber += 1;
          debugPrint(
            '[Diagnostics] phrase $_phraseNumber detected by Rust '
            '(${phrase.length} note(s))',
          );
          widget.onPhrase?.call(_phraseNumber, phrase);
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('[Diagnostics] notesStream error: $error');
        },
      );
      // Actually turn the microphone on. This is a dart:ffi call, not a
      // flutter_rust_bridge one: src/rust/api.dart exposes only
      // initSession/getUserData/notesStream, because listen_audio and
      // stop_audio are `#[frb(ignore)]` in native_ffi/src/lib.rs and reach
      // Dart as C symbols instead (see Audio_Native.dart).
      final failure = AudioNative().begin();
      if (failure != null) {
        await _phraseSubscription?.cancel();
        _phraseSubscription = null;
      }
      return failure;
    } catch (error, stackTrace) {
      debugPrint('[Diagnostics] failed to start recording: $error');
      debugPrintStack(stackTrace: stackTrace);
      await _phraseSubscription?.cancel();
      _phraseSubscription = null;
      return 'Could not start recording: $error';
    }
  }

  /// Shows a problem Rust noticed while recording (a silent microphone, a
  /// stream that stopped), once.
  void _reportAudioProblem() {
    final problem = AudioNative().problem();
    if (problem == null || problem.message == _lastProblem) return;
    _lastProblem = problem.message;
    debugPrint('[Diagnostics] audio problem: $problem');
    widget.onError?.call(problem.message);
  }

  Future<void> _stopRecording() async {
    // Stop the microphone first. Rust then finishes the audio it already
    // captured and sends the note that was still sounding, so keep listening
    // until it has: asking for the unsent notes waits for exactly that, and
    // whatever Rust could not send ends up there instead.
    AudioNative().end();
    try {
      await getUserData();
    } catch (error) {
      debugPrint('[Diagnostics] waiting for the last notes failed: $error');
    }
    // Let the notes just sent reach the listener before it goes.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _phraseSubscription?.cancel();
    _phraseSubscription = null;
  }

  Future<void> _toggle() async {
    if (_starting) return;
    _closeFan();

    if (_isRecording) {
      // Lighter than the start tick: stopping is a release, and the two
      // being distinguishable by feel means the button can be operated
      // without looking at it.
      HapticFeedback.lightImpact();
      _timer?.cancel();
      setState(() => _isRecording = false);
      _pulseCtrl.duration = _idlePeriod;
      _pulseCtrl.repeat();
      await _stopRecording();
      widget.onToggle(false);
      return;
    }

    if (_paused) {
      await _resume();
      return;
    }

    if (await _listen(widget.onBeforeCapture)) {
      _elapsed.value = Duration.zero;
      widget.onToggle(true);
    }
  }

  /// Gets permission, runs [before] (the count-in), then opens the
  /// microphone. True once listening.
  Future<bool> _listen(Future<bool> Function()? before) async {
    // Permission and audio session first: the system prompt must not land
    // in the middle of the count-in.
    setState(() => _starting = true);
    final blocked = await AudioNative().prepare();
    if (!mounted) return false;
    if (blocked != null) {
      setState(() => _starting = false);
      widget.onError?.call(blocked);
      return false;
    }

    if (before != null) {
      final proceed = await before();
      if (!mounted) return false;
      if (!proceed) {
        setState(() => _starting = false);
        return false;
      }
    } else {
      // With a count-in the haptics already happened; a vibration now
      // could reach the microphone as it opens.
      HapticFeedback.mediumImpact();
    }

    // Open the microphone before showing "recording": if it cannot open the
    // player must be told, not left talking to a dead button.
    final failure = await _startRecording();
    if (!mounted) return false;
    setState(() => _starting = false);
    if (failure != null) {
      widget.onError?.call(failure);
      return false;
    }

    setState(() {
      _isRecording = true;
      _paused = false;
    });
    _pulseCtrl.duration = _recordingPeriod;
    _pulseCtrl.repeat();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed.value += const Duration(seconds: 1);
      _reportAudioProblem();
    });
    return true;
  }

  /// Stops listening but keeps the recording, to go on later.
  Future<void> _pause() async {
    if (!_isRecording) return;
    HapticFeedback.lightImpact();
    _timer?.cancel();
    setState(() {
      _isRecording = false;
      _paused = true;
    });
    _pulseCtrl.duration = _idlePeriod;
    _pulseCtrl.repeat();
    await _stopRecording();
  }

  Future<void> _resume() async {
    if (!_paused || _starting) return;
    await _listen(widget.onBeforeResume);
  }

  Future<void> _act(RecorderAction? action) async {
    _closeFan();
    if (_starting) return;
    final onAction = widget.onAction;
    if (action == null) {
      // Finish, from a pause: the recording is over.
      setState(() => _paused = false);
      widget.onToggle(false);
      return;
    }
    await _pause();
    if (!mounted || onAction == null) return;
    switch (action) {
      case RecorderAction.pause:
      case RecorderAction.fromNote:
        await onAction(action);
      case RecorderAction.restart:
        if (await _listen(() => onAction(RecorderAction.restart))) {
          _elapsed.value = Duration.zero;
        }
    }
  }

  void _openFan() {
    if (_fanOpen) return;
    HapticFeedback.selectionClick();
    setState(() => _fanOpen = true);
    _fanTimer?.cancel();
    // Put away again if nothing is chosen.
    _fanTimer = Timer(const Duration(seconds: 5), _closeFan);
  }

  void _closeFan() {
    _fanTimer?.cancel();
    if (_fanOpen && mounted) setState(() => _fanOpen = false);
  }

  bool get _swipeable => widget.actionsEnabled && (_isRecording || _paused);

  static String _format(Duration elapsed) {
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // Built once per real state change and threaded through the position
    // builder as `child`, so dragging only re-runs the Positioned above it.
    final content = GestureDetector(
      onPanStart: (_) => _swipe = 0,
      onPanUpdate: _onPanUpdate,
      onTap: _toggle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: Motion.base,
            switchInCurve: Motion.enter,
            switchOutCurve: Motion.exit,
            child: _isRecording
                ? ValueListenableBuilder<Duration>(
                    key: const ValueKey(true),
                    valueListenable: _elapsed,
                    builder: (context, elapsed, _) =>
                        Text(_format(elapsed), style: _labelStyle(true)),
                  )
                : Text(
                    _paused ? 'Paused' : 'Tap to record',
                    key: ValueKey(_paused),
                    style: _labelStyle(false),
                  ),
          ),
          const SizedBox(height: Space.sm),
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Breathing halo — the idle hint that this circle is
                // tappable, and the live indicator once recording.
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, _) => CustomPaint(
                        painter: RecorderPulseHaloPainter(
                          progress: _pulseCtrl.value,
                          color: _isRecording
                              ? widget.accent
                              : RecorderPalette.haloIdle,
                          strength: _isRecording ? 0.38 : 0.24,
                        ),
                      ),
                    ),
                  ),
                ),
                _lens(),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          SizedBox(
            height: 14,
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, _) => CustomPaint(
                size: const Size(56, 14),
                painter: RecorderWaveHintPainter(
                  progress: _pulseCtrl.value,
                  active: _isRecording,
                  color: _isRecording
                      ? widget.accent
                      : RecorderPalette.haloIdle,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final shown = AnimatedOpacity(
      opacity: widget.hidden ? 0 : 1,
      duration: Motion.base,
      child: IgnorePointer(ignoring: widget.hidden, child: content),
    );
    return ValueListenableBuilder<Offset>(
      valueListenable: _position,
      child: shown,
      builder: (context, pos, child) {
        if (!_fanOpen)
          return Positioned(left: pos.dx, top: pos.dy, child: child!);
        // The buttons come out on whichever side has room.
        final onLeft =
            pos.dx + _buttonWidth + _fanWidth >
            MediaQuery.sizeOf(context).width;
        final fan = _fan(onLeft);
        return Positioned(
          left: onLeft ? pos.dx - _fanWidth : pos.dx,
          top: pos.dy,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: onLeft ? [fan, child!] : [child!, fan],
          ),
        );
      },
    );
  }

  /// The three action buttons, fanned out in an arc beside the button.
  Widget _fan(bool onLeft) {
    final items = [
      _paused
          ? (Icons.stop_rounded, 'Finish', null)
          : (Icons.pause_rounded, 'Pause', RecorderAction.pause),
      (Icons.replay_rounded, 'Restart', RecorderAction.restart),
      (Icons.ads_click_rounded, 'From a note', RecorderAction.fromNote),
    ];
    return SizedBox(
      width: _fanWidth,
      height: _buttonHeight,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Motion.base,
        curve: Motion.enter,
        builder: (context, t, _) => Stack(
          children: [
            for (var i = 0; i < items.length; i++)
              Positioned(
                // An arc: the middle one furthest out.
                left: onLeft ? null : (i == 1 ? 34.0 : 10.0) * t,
                right: onLeft ? (i == 1 ? 34.0 : 10.0) * t : null,
                top: 8.0 + i * 48.0,
                child: Opacity(
                  opacity: t,
                  child: _fanButton(items[i].$1, items[i].$2, items[i].$3),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fanButton(IconData icon, String label, RecorderAction? action) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => _act(action),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
          decoration: BoxDecoration(
            color: PracticePalette.paper,
            borderRadius: Radii.pillRadius,
            border: Border.all(color: PracticePalette.lightGold),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: PracticePalette.gold),
              const SizedBox(width: Space.xxs + 2),
              Text(
                label,
                style: const TextStyle(
                  color: PracticePalette.brown,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // While recording, a sideways swipe on the button brings the actions
    // out (right) or puts them away (left) instead of moving it.
    if (_swipeable) {
      _swipe += details.delta.dx;
      if (_swipe > 24) _openFan();
      if (_swipe < -24) _closeFan();
      return;
    }
    final screenSize = MediaQuery.of(context).size;
    final maxX = screenSize.width - _buttonWidth;
    final maxY = screenSize.height - _buttonHeight;
    final next = _position.value + details.delta;
    _position.value = Offset(
      next.dx.clamp(0.0, maxX < 0 ? 0.0 : maxX),
      next.dy.clamp(0.0, maxY < 0 ? 0.0 : maxY),
    );
  }

  TextStyle _labelStyle(bool recording) => TextStyle(
    color: recording ? RecorderPalette.labelActive : RecorderPalette.labelIdle,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  Widget _lens() {
    return AnimatedContainer(
      duration: Motion.slow,
      curve: Motion.standard,
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.55),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: LiquidGlassLens(
        style: LiquidGlassStyle(
          shape: const LiquidGlassShape.continuousRoundedRectangle(
            cornerRadius: 32,
          ),
          appearance: LiquidGlassAppearance(
            // A neutral transparent lens: no purple idle tint or red
            // recording tint.
            color: Colors.white.withValues(alpha: 0.10),
          ),
          refraction: const LiquidGlassRefraction(
            distortion: 0.12,
            distortionWidth: 20,
            magnification: 1.05,
          ),
        ),
        child: Center(child: _micIcon()),
      ),
    );
  }

  /// The idle mic breathes in time with the halo so the control reads as
  /// alive and waiting rather than as a static graphic. While recording the
  /// stop square stays still — a moving stop target is harder to hit, and
  /// the halo already carries the liveness at that point.
  Widget _micIcon() {
    final icon = AnimatedSwitcher(
      duration: Motion.fast,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: Icon(
        _isRecording
            ? Icons.stop_rounded
            : _paused
            ? Icons.play_arrow_rounded
            : Icons.mic_rounded,
        key: ValueKey((_isRecording, _paused)),
        color: RecorderPalette.icon,
        size: 30,
      ),
    );

    if (_isRecording) return icon;

    return AnimatedBuilder(
      animation: _pulseCtrl,
      child: icon,
      builder: (context, child) {
        // A full sine cycle over the controller's period: out and back,
        // with no discontinuity at the wrap point.
        final breath = sin(_pulseCtrl.value * 2 * pi);
        return Transform.scale(scale: 1 + 0.045 * breath, child: child);
      },
    );
  }
}
