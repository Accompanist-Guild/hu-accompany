import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hu_accomponist/features/practice/practice_prefs.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// Whether the play-along guide has been seen. It starts by itself once, the
/// first time a score is opened to play along with; the help button replays
/// it.
class PlayAlongGuideStore {
  const PlayAlongGuideStore();

  static const key = 'hasSeenPlayAlongGuide';

  Future<bool> hasSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? false;
    } catch (_) {
      return true; // no storage (tests): don't get in the way
    }
  }

  Future<void> setSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, true);
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────────────────────────────────
// The colour key: each kind of mark drawn small, as the score shows it.
// ─────────────────────────────────────────────────────────────────────────

/// The ways a note can be marked on the score.
enum MarkKind {
  perfect,
  close,
  wrong,
  missed,
  early,
  late,
  repeat,
  due,
  played,
}

class _Entry {
  final MarkKind kind;
  final String title;
  final String body;
  const _Entry(this.kind, this.title, this.body);
}

/// The marks, with what they mean, as one list: entries [from] to [to] of
/// the full key (all of it by default).
class NoteLegend extends StatefulWidget {
  final int from;
  final int? to;
  const NoteLegend({super.key, this.from = 0, this.to});

  /// The colours of a note played: perfect to late.
  static const int colourCount = 6;

  static const List<_Entry> _entries = [
    _Entry(MarkKind.perfect, 'Perfect', 'The right key, on the beat.'),
    _Entry(
      MarkKind.close,
      'A little off',
      'The right key, just a little early or late.',
    ),
    _Entry(
      MarkKind.wrong,
      'Wrong key',
      'The note stays black; a small word under it says the key you '
          'pressed.',
    ),
    _Entry(MarkKind.missed, 'Missed', 'Not played.'),
    _Entry(MarkKind.early, 'Early', 'The right key, too soon.'),
    _Entry(MarkKind.late, 'Late', 'The right key, too late.'),
    _Entry(
      MarkKind.repeat,
      'Repeats',
      '"Repeat!" pops up; the bars go back to black and fill in again. The '
          'summary keeps every time through.',
    ),
    _Entry(MarkKind.due, 'Up next', 'The notes to play now sway a little.'),
    _Entry(MarkKind.played, 'Heard', 'A note hops as the app hears it.'),
  ];

  @override
  State<NoteLegend> createState() => _NoteLegendState();
}

class _NoteLegendState extends State<NoteLegend>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _clock
        ..stop()
        ..value = 0;
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = NoteLegend._entries.sublist(
      widget.from,
      widget.to ?? NoteLegend._entries.length,
    );
    return ListenableBuilder(
      listenable: PracticePrefs.instance,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xxs + 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _clock,
                    builder: (context, _) => CustomPaint(
                      size: const Size(64, 48),
                      painter: MarkSwatchPainter(
                        kind: e.kind,
                        colors: PracticePrefs.instance.colors,
                        t: _clock.value,
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${e.title}  ',
                            style: const TextStyle(
                              color: PracticePalette.brown,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(text: e.body),
                        ],
                      ),
                      style: const TextStyle(
                        color: PracticePalette.mutedBrown,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One mark drawn on a scrap of staff: a crotchet the way the score shows it.
class MarkSwatchPainter extends CustomPainter {
  final MarkKind kind;
  final NoteColors colors;

  /// 0..1, looping: drives flashing, swaying and hopping.
  final double t;

  const MarkSwatchPainter({
    required this.kind,
    required this.colors,
    required this.t,
  });

  static const Color _ink = Color(0xFF1E1A16);

  @override
  void paint(Canvas canvas, Size size) {
    // A staff in the upper part, room under it for a word.
    final gap = size.height / 8.7; // staff space
    final top = gap * 2.2;
    final lines = Paint()
      ..color = _ink.withValues(alpha: 0.35)
      ..strokeWidth = 0.8;
    for (var i = 0; i < 5; i++) {
      canvas.drawLine(
        Offset(2, top + i * gap),
        Offset(size.width - 2, top + i * gap),
        lines,
      );
    }
    final center = Offset(size.width / 2 - 3, top + 2 * gap);
    final flash = 0.45 + 0.55 * (0.5 + 0.5 * math.cos(t * 2 * math.pi * 2));

    switch (kind) {
      case MarkKind.perfect:
        _note(canvas, center, gap, fill: colors.perfect);
      case MarkKind.close:
        _note(canvas, center, gap, fill: colors.close);
      case MarkKind.wrong:
        _note(canvas, center, gap, fill: _ink);
        _word(canvas, center, gap, 'D, not E', colors.wrong, flash);
      case MarkKind.missed:
        _note(canvas, center, gap, fill: _ink);
        _word(canvas, center, gap, 'missed', colors.wrong, flash);
      case MarkKind.early:
        _note(canvas, center, gap, fill: _ink);
        _word(canvas, center, gap, 'early', colors.wrong, flash);
      case MarkKind.late:
        _note(canvas, center, gap, fill: _ink);
        _word(canvas, center, gap, 'late', colors.wrong, flash);
      case MarkKind.repeat:
        _note(canvas, center.translate(-gap * 2, 0), gap, fill: colors.perfect);
        _note(canvas, center.translate(gap * 2, -gap / 2), gap, fill: _ink);
        _word(
          canvas,
          Offset(size.width / 2, top - gap * 2.6),
          0,
          'Repeat!',
          Color.lerp(colors.perfect, Colors.black, 0.32)!,
          flash,
          size: gap * 2.1,
          arrow: false,
        );
      case MarkKind.due:
        canvas.save();
        final sway = math.sin(t * 2 * math.pi) * (t < 0.5 ? 0.09 : 0.0);
        canvas.translate(center.dx, center.dy);
        canvas.rotate(sway);
        canvas.translate(-center.dx, -center.dy);
        _note(canvas, center, gap, fill: _ink);
        canvas.restore();
      case MarkKind.played:
        final hop = t < 0.35 ? math.sin(t / 0.35 * math.pi) * gap * 1.1 : 0.0;
        _note(canvas, center.translate(0, -hop), gap, fill: colors.perfect);
    }
  }

  /// A small word under the note at [c], with an arrow up to it, as the
  /// score writes a mistake. It flashes for a moment there; here, always.
  void _word(
    Canvas canvas,
    Offset c,
    double gap,
    String text,
    Color color,
    double flash, {
    double? size,
    bool arrow = true,
  }) {
    final paint = Paint()
      ..color = color.withValues(alpha: flash)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    var y = c.dy;
    if (arrow) {
      final from = c.dy + gap * 0.75, to = from + gap * 1.1;
      canvas.drawLine(Offset(c.dx, from), Offset(c.dx, to), paint);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - gap * 0.4, from + gap * 0.4)
          ..lineTo(c.dx, from)
          ..lineTo(c.dx + gap * 0.4, from + gap * 0.4),
        paint,
      );
      y = to;
    }
    final style = TextStyle(
      fontSize: size ?? gap * 1.75,
      fontWeight: FontWeight.w700,
      fontStyle: FontStyle.italic,
      height: 1,
    );
    TextPainter painter(TextStyle style) => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    // A paper edge, as on the score, so staff lines don't run through it.
    final edge = painter(
      style.copyWith(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..color = PracticePalette.paper,
      ),
    );
    final fill = painter(style.copyWith(color: color.withValues(alpha: flash)));
    final at = Offset(c.dx - fill.width / 2, y);
    edge.paint(canvas, at);
    fill.paint(canvas, at);
  }

  void _note(
    Canvas canvas,
    Offset c,
    double gap, {
    Color? fill,
    bool hollow = false,
  }) {
    if (hollow) {
      _head(canvas, c, gap, stroke: _ink);
    } else {
      _head(canvas, c, gap, fill: fill ?? _ink);
    }
    _stem(canvas, c, gap, hollow ? _ink : fill ?? _ink);
  }

  void _head(
    Canvas canvas,
    Offset c,
    double gap, {
    Color? fill,
    Color? stroke,
    double fillShare = 1,
  }) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.35);
    final oval = Rect.fromCenter(
      center: Offset.zero,
      width: gap * 1.45,
      height: gap * 1.0,
    );
    if (fill != null) {
      canvas.drawOval(
        oval,
        Paint()..color = fill.withValues(alpha: fill.a * fillShare),
      );
    }
    if (stroke != null) {
      canvas.drawOval(
        oval,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7
          ..color = stroke,
      );
    }
    canvas.restore();
  }

  void _stem(Canvas canvas, Offset c, double gap, Color color) {
    final x = c.dx + gap * 0.66;
    canvas.drawLine(
      Offset(x, c.dy - gap * 0.15),
      Offset(x, c.dy - gap * 3.3),
      Paint()
        ..color = color
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(MarkSwatchPainter old) =>
      old.t != t || old.kind != kind || old.colors != colors;
}

// ─────────────────────────────────────────────────────────────────────────
// The help sheet: the colour key, how to use it, and the guide again.
// ─────────────────────────────────────────────────────────────────────────

class PlayAlongHelpSheet extends StatelessWidget {
  final VoidCallback onReplayGuide;
  const PlayAlongHelpSheet({super.key, required this.onReplayGuide});

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onReplayGuide,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PracticePalette.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.modal)),
      ),
      builder: (_) => PlayAlongHelpSheet(onReplayGuide: onReplayGuide),
    );
  }

  static const List<(IconData, String)> howTo = [
    (Icons.mic_rounded, 'Tap the mic, count in with the beats, then play.'),
    (
      Icons.touch_app_rounded,
      'While playing, tap the score to pause and double-tap to finish. '
          'Paused, swipe right on the mic to restart or go on from a note.',
    ),
    (
      Icons.library_music_outlined,
      'When you stop, "See it on the score" shows how each note went, and '
          'each time through a repeat; tap any marked note for what happened.',
    ),
    (
      Icons.tune_rounded,
      'Settings (top left): tempo, hands, where to start, and how strict '
          'timing is.',
    ),
    (Icons.zoom_in_rounded, 'Zoom with + and −, or pinch.'),
  ];

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(
          Space.lg,
          Space.md,
          Space.lg,
          Space.xl,
        ),
        children: [
          const Text(
            'PLAY ALONG',
            style: TextStyle(
              color: PracticePalette.gold,
              fontSize: 11,
              letterSpacing: 2.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.xs),
          const Text(
            'What the colours mean',
            style: TextStyle(
              color: PracticePalette.brown,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.sm),
          const NoteLegend(),
          const SizedBox(height: Space.lg),
          const Text(
            'How to play along',
            style: TextStyle(
              color: PracticePalette.brown,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.xs),
          for (final (icon, text) in howTo)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xxs + 1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: PracticePalette.gold),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: PracticePalette.brown,
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Space.lg),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onReplayGuide();
            },
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Replay the guide'),
            style: OutlinedButton.styleFrom(
              foregroundColor: PracticePalette.gold,
              side: const BorderSide(color: PracticePalette.lightGold),
              minimumSize: const Size.fromHeight(46),
              shape: const RoundedRectangleBorder(
                borderRadius: Radii.pillRadius,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// The guide: a few steps over the real practice screen.
// ─────────────────────────────────────────────────────────────────────────

/// What a step of the guide points at.
enum GuideTarget { none, recorder, score, help, settings }

class GuideStep {
  final String title;
  final String body;
  final GuideTarget target;

  /// Shows the colour key in the card: the colours, or ([fullLegend]) the
  /// rest of it.
  final bool legend;
  final bool fullLegend;

  const GuideStep(
    this.title,
    this.body, {
    this.target = GuideTarget.none,
    this.legend = false,
    this.fullLegend = false,
  });
}

/// The guide's steps, in order.
const List<GuideStep> playAlongGuide = [
  GuideStep(
    'Play along with the score',
    'Play your instrument and the app listens: every note you play is '
        'marked on the score as you go, and it follows your tempo, so you '
        'needn\'t keep a metronome\'s. Here\'s how it works.',
  ),
  GuideStep(
    'Start and stop here',
    'Tap the mic. The first time, pick a tempo and which hands. After a '
        'count-in, start on the first note. You can drag the mic anywhere.',
    target: GuideTarget.recorder,
  ),
  GuideStep(
    'Tap to pause, double-tap to finish',
    'While you play, the score has the whole screen. Tap it once to pause '
        '(to look around or write on it), twice to finish. When paused, '
        'swipe right on the mic to Restart, or pick a note to go on from.',
    target: GuideTarget.recorder,
  ),
  GuideStep(
    'Reading the colours',
    'Each note shows how you played it:',
    target: GuideTarget.score,
    legend: true,
  ),
  GuideStep(
    'Repeats, and what to play next',
    'When a repeat starts, "Repeat!" pops up and those bars go back to '
        'black to fill in again. The notes to play now sway; a note hops '
        'when it\'s heard.',
    target: GuideTarget.score,
    legend: true,
    fullLegend: true,
  ),
  GuideStep(
    'After you play',
    'You\'ll get your score and every mistake, a repeat with each time '
        'through. "See it on the score" shows the run there; tap any marked '
        'note to see what happened to it.',
    target: GuideTarget.score,
  ),
  GuideStep(
    'Tempo, hands and more',
    'Settings has the tempo and hands, where to start, and how strict timing '
        'is (and the colours).',
    target: GuideTarget.settings,
  ),
  GuideStep(
    'Help is here',
    'Tap ? any time for the colour key, or to see this guide again.',
    target: GuideTarget.help,
  ),
];

/// The guide over the practice screen: a dimmed layer with a hole over what
/// the current step is about, and a card explaining it. [targets] gives the
/// widgets to point at, by their keys.
class PlayAlongGuideOverlay extends StatefulWidget {
  final int step;
  final Map<GuideTarget, GlobalKey> targets;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onDone;

  const PlayAlongGuideOverlay({
    super.key,
    required this.step,
    required this.targets,
    required this.onNext,
    required this.onBack,
    required this.onDone,
  });

  @override
  State<PlayAlongGuideOverlay> createState() => _PlayAlongGuideOverlayState();
}

class _PlayAlongGuideOverlayState extends State<PlayAlongGuideOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  Rect? _hole;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(PlayAlongGuideOverlay old) {
    super.didUpdateWidget(old);
    if (old.step != widget.step) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse
        ..stop()
        ..value = 0.5;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// Where the step's target is, in this overlay's coordinates.
  void _measure() {
    if (!mounted) return;
    final target = playAlongGuide[widget.step].target;
    final box = widget.targets[target]?.currentContext?.findRenderObject();
    final me = context.findRenderObject();
    Rect? hole;
    if (box is RenderBox && me is RenderBox && box.hasSize && me.hasSize) {
      final topLeft = me.globalToLocal(box.localToGlobal(Offset.zero));
      hole = (topLeft & box.size).inflate(target == GuideTarget.score ? 0 : 6);
    }
    if (hole != _hole) setState(() => _hole = hole);
  }

  @override
  Widget build(BuildContext context) {
    final step = playAlongGuide[widget.step];
    final hole = step.target == GuideTarget.none ? null : _hole;
    return LayoutBuilder(
      builder: (context, box) {
        // The card goes where the hole isn't: below a target near the top,
        // above one near the bottom, centred over the score.
        final Alignment align;
        if (hole == null) {
          align = Alignment.center;
        } else if (step.target == GuideTarget.score) {
          align = Alignment.bottomCenter;
        } else if (hole.center.dy < box.maxHeight / 2) {
          align = Alignment.bottomCenter;
        } else {
          align = Alignment.topCenter;
        }
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => CustomPaint(
                    painter: _GuideDimPainter(hole: hole, pulse: _pulse.value),
                  ),
                ),
              ),
              // Nothing underneath is touched while the guide is up.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Align(
                  alignment: align,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 440,
                      maxHeight: box.maxHeight * 0.62,
                    ),
                    child: AnimatedSwitcher(
                      duration: Motion.base,
                      child: _card(step, key: ValueKey(widget.step)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _card(GuideStep step, {Key? key}) {
    final last = widget.step == playAlongGuide.length - 1;
    return Container(
      key: key,
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: PracticePalette.paper,
        borderRadius: Radii.modalRadius,
        border: Border.all(
          color: PracticePalette.lightGold.withValues(alpha: 0.65),
        ),
        boxShadow: Elevations.overlay(PracticePalette.brown),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STEP ${widget.step + 1} OF ${playAlongGuide.length}',
            style: const TextStyle(
              color: PracticePalette.gold,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            step.title,
            style: const TextStyle(
              color: PracticePalette.brown,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            step.body,
            style: const TextStyle(
              color: PracticePalette.mutedBrown,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          if (step.legend)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: Space.sm),
                child: step.fullLegend
                    ? const NoteLegend(from: NoteLegend.colourCount)
                    : const NoteLegend(to: NoteLegend.colourCount),
              ),
            ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              TextButton(
                onPressed: widget.onDone,
                style: TextButton.styleFrom(
                  foregroundColor: PracticePalette.mutedBrown,
                ),
                child: const Text('Skip'),
              ),
              const Spacer(),
              if (widget.step > 0)
                TextButton(
                  onPressed: widget.onBack,
                  style: TextButton.styleFrom(
                    foregroundColor: PracticePalette.gold,
                  ),
                  child: const Text('Back'),
                ),
              const SizedBox(width: Space.xs),
              FilledButton(
                onPressed: last ? widget.onDone : widget.onNext,
                style: FilledButton.styleFrom(
                  backgroundColor: PracticePalette.gold,
                  foregroundColor: PracticePalette.paper,
                ),
                child: Text(
                  widget.step == 0
                      ? 'Show me'
                      : last
                      ? 'Got it'
                      : 'Next',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GuideDimPainter extends CustomPainter {
  final Rect? hole;
  final double pulse;
  const _GuideDimPainter({required this.hole, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.62);
    final hole = this.hole;
    if (hole == null) {
      canvas.drawRect(Offset.zero & size, dim);
      return;
    }
    final r = RRect.fromRectAndRadius(hole, const Radius.circular(Radii.card));
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(r),
      dim,
    );
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = PracticePalette.lightGold.withValues(
          alpha: 0.4 + 0.55 * pulse,
        ),
    );
  }

  @override
  bool shouldRepaint(_GuideDimPainter old) =>
      old.hole != hole || old.pulse != pulse;
}
