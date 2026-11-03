import 'package:flutter/material.dart';

import 'package:hu_accomponist/features/shell/disk_pages.dart';
import 'package:hu_accomponist/features/shell/mini_disk.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// The steps of the first-run tour, in order. The shell moves between them:
/// the hold step advances when the person actually does the gesture.
abstract final class TutorialStep {
  static const int welcome = 0;
  static const int hold = 1;
  static const int drawer = 2;
  static const int tour = 3;
  static const int count = 4;
}

/// A dimmed layer over the whole app with a card explaining the current
/// step. The hold step cuts a hole over the disk bar and lets touches
/// through it, so the person tries the gesture on the real disks.
class TutorialOverlay extends StatefulWidget {
  final int step;

  /// Height of the disk bar including the inset below it: the hole.
  final double barHeight;

  /// Moves on without the gesture (the step's own button).
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback onDone;

  /// The disks the tour describes.
  final List<DiskPage> pages;

  const TutorialOverlay({
    super.key,
    required this.step,
    required this.barHeight,
    required this.onNext,
    required this.onSkip,
    required this.onDone,
    this.pages = diskPages,
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A pulsing outline is decoration; people who turned motion off get a
    // steady one.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse
        ..stop()
        ..value = 0.5;
    } else {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  bool get _holeOverBar => widget.step != TutorialStep.drawer;

  /// Touches reach the disks through the hole only on the step that asks
  /// for a gesture. Elsewhere the hole just shows them off.
  bool get _interactiveHole => widget.step == TutorialStep.hold;

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
                      pulse: _pulse.value,
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
                      pages: widget.pages,
                      key: ValueKey(step),
                      step: step,
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
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback onDone;
  final List<DiskPage> pages;

  const _Card({
    super.key,
    required this.pages,
    required this.step,
    required this.onNext,
    required this.onSkip,
    required this.onDone,
  });

  static const _titles = [
    'Meet your disks',
    'Press and hold for the disk drawer',
    'Tap a disk to jump there',
    'Where things are',
  ];

  static const _bodies = [
    'The disks at the bottom are your pages: tap one to go there. The one '
        'with the gold ring is where you are now. This quick tour takes under '
        'a minute, and you can replay it from your account: tap your icon at the top of Home.',
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
          Text(
            _titles[step],
            style: const TextStyle(
              color: PracticePalette.brown,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            _bodies[step],
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
          for (final page in pages)
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
            'Some disks hold more than one page: pick one from the tabs at '
            'the top. In the Practice Room, on Practice: the sliders at the '
            'top left open your library and exercises, the pencil at the top right marks up the score, and '
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
