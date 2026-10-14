import 'dart:math';

import 'package:flutter/material.dart';

import 'package:hu_accomponist/shared/theme/Color_Theme.dart';

/// A record standing for a page, drawn to look like vinyl: fine grooves with
/// a few wider track gaps, a dead-wax band, a soft light (vinyl is matte, not chrome) that stays put while the
/// disk turns under it, a paper label with the page's icon, a spindle hole
/// and a shadow.
///
/// It turns at 33⅓ rpm, the speed of an LP. The grooves are concentric, so
/// turning them would show nothing; what turns is the label and a few faint
/// scratches in the grooves, while the sheen stays where the light is.
class MiniDisk extends StatefulWidget {
  final double size;
  final Color diskColor;
  final IconData icon;

  /// The disk for the page being shown wears a gold ring.
  final bool active;

  /// Off for disks that are only illustrations (the tutorial's list).
  final bool spin;

  const MiniDisk({
    super.key,
    required this.size,
    required this.diskColor,
    required this.icon,
    this.active = false,
    this.spin = true,
  });

  @override
  State<MiniDisk> createState() => _MiniDiskState();
}

class _MiniDiskState extends State<MiniDisk>
    with SingleTickerProviderStateMixin {
  /// One turn every 1.8 seconds: 33⅓ revolutions a minute.
  static const _turn = Duration(milliseconds: 1800);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Disks side by side shouldn't turn in lockstep: start each a little
    // way round, by which icon it carries.
    final phase = ((widget.icon.codePoint * 31) % 100) / 100;
    _controller = AnimationController(
      vsync: this,
      duration: _turn,
      value: phase,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSpin();
  }

  @override
  void didUpdateWidget(MiniDisk old) {
    super.didUpdateWidget(old);
    if (old.spin != widget.spin) _syncSpin();
  }

  void _syncSpin() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (widget.spin && !reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final labelRadius = size * 0.2;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Everything that stays still: the disk, its grooves and the
          // light on it. Cached, so the turning doesn't repaint it.
          RepaintBoundary(
            child: CustomPaint(
              size: Size.square(size),
              painter: _VinylPainter(
                diskColor: widget.diskColor,
                active: widget.active,
              ),
            ),
          ),
          // What turns: scratches, then the label with its icon and hole.
          RotationTransition(
            turns: _controller,
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.square(size),
                painter: _TurningPainter(active: widget.active),
                foregroundPainter: _SpindlePainter(),
                child: Center(
                  child: Transform.translate(
                    offset: Offset(0, -labelRadius * 0.28),
                    child: Icon(
                      widget.icon,
                      size: labelRadius * 0.95,
                      color: const Color(0xFF3B2F22),
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

/// A repeatable pseudo-random 0..1 for index [i]: the same disk looks the
/// same every frame and on every build, which a shared `Random` would not.
double _noise(int i) => ((sin(i * 12.9898) * 43758.5453) % 1).abs();

/// Fraction of the radius the label covers.
const double _labelFraction = 0.4;

class _VinylPainter extends CustomPainter {
  final Color diskColor;
  final bool active;
  const _VinylPainter({required this.diskColor, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final labelR = r * _labelFraction;
    final grooveOuter = r * 0.965;
    final grooveInner = labelR + r * 0.07; // dead wax between label and grooves

    // Shadow on whatever the disk is lying on.
    canvas.drawCircle(
      c + Offset(0, r * 0.1),
      r * 0.96,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.42)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.16),
    );

    // The body: vinyl is black but not flat, a little lighter where the
    // light falls.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.1,
          colors: [
            Color.lerp(diskColor, Colors.white, 0.04)!,
            diskColor,
            Color.lerp(diskColor, Colors.black, 0.5)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Grooves: many fine rings, each a touch different, and the odd wide
    // gap where one track ends and the next begins.
    final rings = max(14, ((grooveOuter - grooveInner) / 0.9).floor());
    final width = max(0.35, r / 90);
    for (var i = 0; i < rings; i++) {
      final t = i / rings;
      final radius = grooveInner + (grooveOuter - grooveInner) * t;
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = Colors.white.withValues(alpha: 0.02 + 0.035 * _noise(i)),
      );
    }
    for (final gap in const [0.27, 0.52, 0.79]) {
      canvas.drawCircle(
        c,
        grooveInner + (grooveOuter - grooveInner) * gap,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(0.8, r / 32)
          ..color = Colors.black.withValues(alpha: 0.35),
      );
    }

    // The light: two bright wedges on opposite sides of the grooves, as a
    // lamp makes on a real record. They stay put while the disk turns.
    final grooves = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: c, radius: grooveOuter))
      ..addOval(Rect.fromCircle(center: c, radius: grooveInner));
    const first = 0.12;
    const second = 0.62;
    const half = 0.16;
    final clear = Colors.white.withValues(alpha: 0);
    final bright = Colors.white.withValues(alpha: 0.09);
    canvas.drawPath(
      grooves,
      Paint()
        ..shader = SweepGradient(
          colors: [clear, clear, bright, clear, clear, bright, clear, clear],
          stops: const [
            0,
            first - half,
            first,
            first + half,
            second - half,
            second,
            second + half,
            1,
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // The edge: a faint bevel where the rim catches the light.
    canvas.drawCircle(
      c,
      r - max(0.5, r / 60),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.8, r / 40)
        ..shader = SweepGradient(
          colors: [
            Colors.white.withValues(alpha: 0.04),
            Colors.white.withValues(alpha: 0.12),
            Colors.white.withValues(alpha: 0.04),
            Colors.white.withValues(alpha: 0.09),
            Colors.white.withValues(alpha: 0.04),
          ],
          transform: const GradientRotation(-pi / 4),
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    if (active) {
      canvas.drawCircle(
        c,
        r + 1.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = PracticePalette.gold,
      );
    }
  }

  @override
  bool shouldRepaint(_VinylPainter old) =>
      old.diskColor != diskColor || old.active != active;
}

/// The label and a few scratches: the parts of the disk that show it turning.
class _TurningPainter extends CustomPainter {
  final bool active;
  const _TurningPainter({required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final labelR = r * _labelFraction;

    // Hairline scratches and dust: short arcs at fixed places in the grooves.
    for (var i = 0; i < 7; i++) {
      final radius = labelR + r * 0.12 + (r * 0.8 - labelR) * _noise(i + 40);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: radius),
        _noise(i + 70) * 2 * pi,
        0.25 + _noise(i + 90) * 0.5,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(0.4, r / 100)
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.04 + 0.04 * _noise(i)),
      );
    }

    // The paper label: warm cream, darker toward the edge, gold on the disk
    // being shown.
    final paper = active
        ? PracticePalette.lightGold
        : TurntablePalette.parchment;
    canvas.drawCircle(
      c,
      labelR,
      Paint()
        ..shader = RadialGradient(
          colors: [paper, Color.lerp(paper, const Color(0xFF8A7752), 0.35)!],
        ).createShader(Rect.fromCircle(center: c, radius: labelR)),
    );

    // Printing on it: a ring, and dashes standing in for the small text.
    final ink = const Color(0xFF3B2F22);
    canvas.drawCircle(
      c,
      labelR * 0.86,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.4, r / 110)
        ..color = ink.withValues(alpha: 0.4),
    );
    if (r >= 28) {
      for (var i = 0; i < 10; i++) {
        final start = i * 2 * pi / 10 + 0.15;
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: labelR * 0.72),
          start,
          0.2,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(0.6, r / 60)
            ..strokeCap = StrokeCap.round
            ..color = ink.withValues(alpha: 0.28),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TurningPainter old) => old.active != active;
}

/// The spindle hole, over the label and its icon.
class _SpindlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final hole = max(0.8, r * 0.045);
    canvas.drawCircle(c, hole, Paint()..color = TurntablePalette.background);
    canvas.drawCircle(
      c,
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.4, r / 120)
        ..color = Colors.black.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(_SpindlePainter old) => false;
}
