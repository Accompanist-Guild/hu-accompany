import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hu_accomponist/features/shell/disk_pages.dart';
import 'package:hu_accomponist/features/shell/mini_disk.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// The bottom navigation: a spinning record for every page, side by side
/// along the bottom of the screen, over the page.
///
/// The disk for the page being shown is larger, with a gold ring. Tapping a
/// disk goes to its page, and holding the row asks the shell to open the
/// disk drawer ([onHold]).
class DiskBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelected;
  final VoidCallback onHold;

  /// The disks along the row, in slot order.
  final List<DiskPage> pages;

  const DiskBar({
    super.key,
    required this.index,
    required this.onSelected,
    required this.onHold,
    this.pages = diskPages,
  });

  /// The active disk's largest diameter; the others are a little smaller.
  /// On a narrow screen the disks shrink so they all fit.
  static double diskSizeFor(Orientation orientation) =>
      orientation == Orientation.landscape ? 46 : 64;

  /// What the row takes from the bottom of the screen, so pages leave it
  /// clear: the disk, some air above it and, below, the system inset (the
  /// home indicator) or a small margin if there is none.
  static double heightFor(BuildContext context) {
    final media = MediaQuery.of(context);
    final disk = diskSizeFor(media.orientation);
    return disk + Space.sm + max(media.padding.bottom, Space.md);
  }

  /// How much smaller the disks are that aren't being shown.
  static const double _inactiveScale = 0.84;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxDisk = DiskBar.diskSizeFor(media.orientation);
    final bottom = max(media.padding.bottom, Space.md);

    return Semantics(
      container: true,
      label:
          'Pages. Tap a disk to change page, or press and hold to see them '
          'all.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (_) {
          HapticFeedback.mediumImpact();
          onHold();
        },
        child: SizedBox(
          height: DiskBar.heightFor(context),
          child: LayoutBuilder(
            builder: (context, box) {
              // Each disk gets an equal share of the width, up to the
              // spacing the row has on a wide screen.
              final slot = min(maxDisk * 1.5, box.maxWidth / pages.length);
              final disk = min(maxDisk, slot * 0.86);
              return Padding(
                padding: EdgeInsets.only(bottom: bottom),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    height: disk,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < pages.length; i++)
                          SizedBox(
                            width: slot,
                            child: Center(
                              child: _disk(
                                i,
                                i == index ? disk : disk * _inactiveScale,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _disk(int i, double size) {
    final page = pages[i];
    final active = i == index;
    return Semantics(
      button: true,
      selected: active,
      label: page.title,
      onTap: () => onSelected(i),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: active
            ? null
            : () {
                HapticFeedback.selectionClick();
                onSelected(i);
              },
        // Hover only: on touch, a long press belongs to the disk drawer.
        child: Tooltip(
          message: page.tooltip,
          triggerMode: TooltipTriggerMode.manual,
          waitDuration: navTooltipWait,
          // The disk grows into place when its page is picked.
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: size),
            duration: Motion.slow,
            curve: Motion.enter,
            builder: (context, animated, _) => MiniDisk(
              size: animated,
              diskColor: page.diskColor,
              icon: page.icon,
              active: active,
            ),
          ),
        ),
      ),
    );
  }
}
