import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hu_accomponist/features/shell/disk_pages.dart';
import 'package:hu_accomponist/features/shell/mini_disk.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// Every page at once, opened by holding the disk bar. The screen behind
/// dims and blurs and the disks pop up from the bar in a grid; tapping one
/// goes there, tapping anywhere else closes the drawer.
///
/// Always mounted by the shell and driven by [open], so it can animate out
/// as well as in; while fully closed it builds nothing and takes no touches.
class DiskDrawer extends StatefulWidget {
  final bool open;
  final int index;
  final ValueChanged<int> onSelected;
  final VoidCallback onClose;

  /// The disks to lay out, in slot order.
  final List<DiskPage> pages;

  const DiskDrawer({
    super.key,
    required this.open,
    required this.index,
    required this.onSelected,
    required this.onClose,
    this.pages = diskPages,
  });

  @override
  State<DiskDrawer> createState() => _DiskDrawerState();
}

class _DiskDrawerState extends State<DiskDrawer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
    reverseDuration: Motion.base,
    value: widget.open ? 1 : 0,
  );

  @override
  void didUpdateWidget(DiskDrawer old) {
    super.didUpdateWidget(old);
    if (widget.open == old.open) return;
    if (widget.open) {
      _anim.forward();
    } else {
      _anim.reverse();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final t = _anim.value;
        if (t == 0) return const SizedBox.shrink();
        final scrim = Curves.easeOut.transform(t.clamp(0.0, 1.0));
        // Material gives the labels a text style; without one they render
        // with Flutter's fallback: bold, yellow double underline.
        return Positioned.fill(
          child: Material(
            type: MaterialType.transparency,
            child: Semantics(
              scopesRoute: true,
              explicitChildNodes: true,
              label: 'All pages',
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onClose,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: 14 * scrim,
                        sigmaY: 14 * scrim,
                      ),
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.5 * scrim),
                      ),
                    ),
                  ),
                  Positioned.fill(child: _scatter(context)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Disks per column. Pages fill the left column top to bottom, then the
  /// right; an odd one out (the seventh of seven) sits in the middle of the
  /// bottom row.
  int get _perColumn => widget.pages.length ~/ 2;

  Widget _scatter(BuildContext context) {
    final media = MediaQuery.of(context);
    final landscape = media.orientation == Orientation.landscape;
    final screen = media.size;

    // The lower part of the screen, which is where the bar is and where a
    // thumb already is. Turned sideways there's less room, so use more of it.
    final top = screen.height * (landscape ? 0.14 : 0.36);
    final bottom = screen.height - (landscape ? 24.0 : 110.0);
    const sideMargin = Space.xl;
    // Wider than any disk: labels are centred under their disk in a box of
    // this width, so a long name never pushes off to one side.
    const itemWidth = 108.0;
    const labelHeight = 24.0;
    final areaHeight = bottom - top;
    // Three rows, each a disk, its label and a gap.
    final disk = (areaHeight / _perColumn - labelHeight - Space.xs).clamp(
      44.0,
      72.0,
    );
    final rowStep = (areaHeight - disk - labelHeight) / (_perColumn - 1);
    final leftX = sideMargin + itemWidth / 2;
    final rightX = screen.width - sideMargin - itemWidth / 2;

    return Stack(
      children: [
        for (var i = 0; i < widget.pages.length; i++)
          () {
            final column = i ~/ _perColumn;
            final row = i % _perColumn;
            final centerX = switch (column) {
              0 => leftX,
              1 => rightX,
              _ => screen.width / 2,
            };
            // The extra disk shares the bottom row.
            final y = top + (column > 1 ? _perColumn - 1 : row) * rowStep;
            return Positioned(
              left: centerX - itemWidth / 2,
              top: y,
              width: itemWidth,
              child: _item(
                i,
                disk,
                // Disks fly out from the middle of the bottom edge.
                from: Offset(
                  screen.width / 2 - centerX,
                  screen.height - (y + disk / 2),
                ),
              ),
            );
          }(),
      ],
    );
  }

  Widget _item(int i, double disk, {required Offset from}) {
    final page = widget.pages[i];
    final active = i == widget.index;
    // Each disk leaves a beat after the one before, with a little overshoot.
    final start = (i * 0.07).clamp(0.0, 0.5);
    final pop = CurvedAnimation(
      parent: _anim,
      curve: Interval(
        start,
        (start + 0.55).clamp(0.0, 1.0),
        curve: Curves.easeOutBack,
      ),
      reverseCurve: Curves.easeIn,
    );

    return AnimatedBuilder(
      animation: pop,
      builder: (context, child) => Opacity(
        opacity: pop.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: from * (1 - pop.value),
          child: Transform.scale(scale: 0.3 + 0.7 * pop.value, child: child),
        ),
      ),
      child: Semantics(
        button: true,
        selected: active,
        label: page.title,
        excludeSemantics: true,
        onTap: () => widget.onSelected(i),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onSelected(i);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MiniDisk(
                size: disk,
                diskColor: page.diskColor,
                icon: page.icon,
                active: active,
              ),
              const SizedBox(height: Space.xxs),
              Text(
                page.title.toUpperCase(),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  color: TurntablePalette.parchment.withValues(
                    alpha: active ? 1 : 0.8,
                  ),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
