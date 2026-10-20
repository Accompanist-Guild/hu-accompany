import 'package:flutter/material.dart';

import 'package:hu_accomponist/features/shell/disk_pages.dart';
import 'package:hu_accomponist/features/shell/mini_disk.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// The steps of the first-run tour, in order. The shell moves between them:
/// the two gesture steps advance when the person actually does the gesture.
abstract final class TutorialStep {
  static const int welcome = 0;
  static const int swipe = 1;
  static const int hold = 2;
  static const int drawer = 3;
  static const int tour = 4;
  static const int count = 5;
}

/// A dimmed layer over the whole app with a card explaining the current
/// step. The gesture steps cut a hole over the disk bar and let touches
/// through it, so the person tries the gesture on the real disks. The swipe
/// step shows a finger swiping as an example, and waits for the person to do
/// it themselves.
class TutorialOverlay extends StatefulWidget {
  final int step;

  /// Height of the disk bar including the inset below it: the hole.
  final double barHeight;

  /// The person did what this step asked (only the swipe step waits on
  /// that): the card congratulates them before the shell moves on.
  final bool succeeded;

  /// Moves on without the gesture (the step's own button).
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback onDone;

  const TutorialOverlay({
    super.key,
    required this.step,
    required this.barHeight,
    this.succeeded = false,
    required this.onNext,
    required this.onSkip,
    required this.onDone,
  });

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// Loops the example swipe.
  late final AnimationController _demo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A pulsing outline is decoration; people who turned motion off get a
    // steady one.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse
        ..stop()
        ..value = 0.5;
      _demo
        ..stop()
        ..value = 0.5;
    } else {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
      if (!_demo.isAnimating) _demo.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _demo.dispose();
    super.dispose();
  }

  bool get _holeOverBar => widget.step != TutorialStep.drawer;

  /// Touches reach the disks through the hole only on the steps that ask
  /// for a gesture. Elsewhere the hole just shows them off.
  bool get _interactiveHole =>
      widget.step == TutorialStep.swipe || widget.step == TutorialStep.hold;

  /// The drawer step has the drawer's own dim, so this layer adds none and
  /// lets touches through to the drawer.
  bool get _blocksTouches => widget.step != TutorialStep.drawer;

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final onTop = step == TutorialStep.drawer;
    final centered = step == TutorialStep.welcome;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_blocksTouches) ...[
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => CustomPaint(
                    painter: _SpotlightPainter(
                      barHeight: _holeOverBar ? widget.barHeight : null,
                      pulse: widget.succeeded ? 1 : _pulse.value,
                    ),
                  ),
                ),
              ),
            ),
            // Swallows touches everywhere but over the hole.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: _interactiveHole ? widget.barHeight : 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                onVerticalDragStart: (_) {},
                onHorizontalDragStart: (_) {},
              ),
            ),
          ],
          if (widget.step == TutorialStep.swipe && !widget.succeeded)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _demo,
                  builder: (context, _) => _SwipeDemo(
                    progress: _demo.value,
                    barHeight: widget.barHeight,
                  ),
                ),
              ),
            ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                Space.md,
                Space.md,
                Space.md,
                _holeOverBar ? widget.barHeight + Space.md : Space.md,
              ),
              child: Align(
                alignment: centered
                    ? Alignment.center
                    : onTop
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AnimatedSwitcher(
                    duration: Motion.base,
                    switchInCurve: Motion.enter,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.96,
                          end: 1,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _Card(
                      key: ValueKey('$step-${widget.succeeded}'),
                      step: step,
                      succeeded: widget.succeeded,
                      onNext: widget.onNext,
                      onSkip: widget.onSkip,
                      onDone: widget.onDone,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  /// Height of the bar-shaped hole at the bottom, or null for no hole.
  final double? barHeight;
  final double pulse;

  const _SpotlightPainter({required this.barHeight, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.68);
    final hole = barHeight;
    if (hole == null) {
      canvas.drawRect(Offset.zero & size, dim);
      return;
    }
    final bar = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, size.height - hole, size.width, hole),
      topLeft: const Radius.circular(Radii.modal),
      topRight: const Radius.circular(Radii.modal),
    );
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(bar),
      dim,
    );
    canvas.drawRRect(
      bar.deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = PracticePalette.lightGold.withValues(
          alpha: 0.35 + 0.6 * pulse,
        ),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.barHeight != barHeight || old.pulse != pulse;
}

class _Card extends StatelessWidget {
  final int step;
  final bool succeeded;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback onDone;

  const _Card({
    super.key,
    required this.step,
    required this.succeeded,
    required this.onNext,
    required this.onSkip,
    required this.onDone,
  });

  static const _titles = [
    'Meet your disks',
    'Swipe to explore your disks',
    'Press and hold for the disk drawer',
    'Tap a disk to jump there',
    'Where things are',
  ];

  static const _bodies = [
    'The three disks at the bottom are your pages: the one with the gold ring '
        'is where you are now. This quick tour takes under a minute, and you '
        'can replay it from Settings.',
    'Slide a finger (or the mouse) left or right along the disks. Give it a '
        'try: the next one comes to the middle.',
    'Keep a finger on the disks for a moment. Every page pops out, and the '
        'rest of the screen fades back.',
    'Pick any page to go straight there, or tap outside the disks to close '
        'the drawer.',
    'Each disk is a page.',
  ];

  bool get _last => step == TutorialStep.tour;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            'STEP ${step + 1} OF ${TutorialStep.count}',
            style: const TextStyle(
              color: PracticePalette.gold,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              if (succeeded) ...[
                // Pops in, so the success is felt as well as read.
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.3, end: 1),
                  duration: Motion.slow,
                  curve: Curves.easeOutBack,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: PracticePalette.gold,
                    size: 24,
                  ),
                ),
                const SizedBox(width: Space.xs),
              ],
              Expanded(
                child: Text(
                  succeeded ? 'Nice swipe!' : _titles[step],
                  style: const TextStyle(
                    color: PracticePalette.brown,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            succeeded ? "That's how you browse your pages." : _bodies[step],
            style: const TextStyle(
              color: PracticePalette.mutedBrown,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          if (_last) Flexible(child: _tour()),
          const SizedBox(height: Space.md),
          Row(
            children: [
              TextButton(
                onPressed: onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: PracticePalette.mutedBrown,
                ),
                child: const Text('Skip'),
              ),
              const Spacer(),
              // The swipe step has no way past it but the swipe itself.
              if (step != TutorialStep.swipe)
                FilledButton(
                  onPressed: _last ? onDone : onNext,
                  style: FilledButton.styleFrom(
                    backgroundColor: PracticePalette.gold,
                    foregroundColor: PracticePalette.paper,
                  ),
                  child: Text(switch (step) {
                    TutorialStep.welcome => 'Show me',
                    TutorialStep.tour => 'Got it',
                    _ => 'Next',
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// What each disk is, and where the main Practice controls are.
  Widget _tour() {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final page in diskPages)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xxs),
              child: Row(
                children: [
                  MiniDisk(
                    size: 30,
                    diskColor: page.diskColor,
                    icon: page.icon,
                    spin: false,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${page.title}  ',
                            style: const TextStyle(
                              color: PracticePalette.brown,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: page.caption,
                            style: const TextStyle(
                              color: PracticePalette.mutedBrown,
                            ),
                          ),
                        ],
                      ),
                      style: const TextStyle(fontSize: 13, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Space.xs),
          const Text(
            'On Practice: the sliders at the top left open your library and '
            'exercises, the pencil at the top right marks up the score, and '
            'the microphone records. Drag it wherever suits.',
            style: TextStyle(
              color: PracticePalette.mutedBrown,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// An example of the swipe: a finger slides left along the disks, with
/// chevrons showing the direction, over and over until the person tries it.
class _SwipeDemo extends StatelessWidget {
  final double progress;
  final double barHeight;
  const _SwipeDemo({required this.progress, required this.barHeight});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // Rests, slides left, fades out, then starts again from the right.
    final slide = Curves.easeInOut.transform(
      ((progress - 0.15) / 0.55).clamp(0.0, 1.0),
    );
    final opacity = progress < 0.1
        ? progress / 0.1
        : progress > 0.75
        ? (1 - (progress - 0.75) / 0.25).clamp(0.0, 1.0)
        : 1.0;
    final x = width * (0.64 - 0.28 * slide);

    return Stack(
      children: [
        Positioned(
          left: x - 22,
          bottom: barHeight / 2 - 4,
          child: Opacity(
            opacity: opacity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Chevrons trail the finger, brightest nearest it.
                for (var i = 3; i >= 1; i--)
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    color: PracticePalette.lightGold.withValues(
                      alpha: 0.9 - 0.25 * i,
                    ),
                  ),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: PracticePalette.paper.withValues(alpha: 0.9),
                    border: Border.all(color: PracticePalette.gold, width: 2),
                    boxShadow: Elevations.raised(Colors.black),
                  ),
                  child: const Icon(
                    Icons.touch_app_rounded,
                    color: PracticePalette.gold,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
