import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hu_accomponist/features/shell/disk_pages.dart';
import 'package:hu_accomponist/features/shell/mini_disk.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// The bottom navigation: three spinning records in a row along the bottom
/// of the screen, over the page.
///
/// The disk for the page being shown is in the middle, larger, with a gold
/// ring; the page before and after it are either side. Drag along the row to
/// browse: the disks follow the finger and settle with another page in the
/// middle. It wraps round, so swiping on from the last page comes back to
/// the first. Tapping a side disk jumps to it, and holding the row asks the
/// shell to open the disk drawer ([onHold]).
class DiskBar extends StatefulWidget {
  final int index;
  final ValueChanged<int> onSelected;

  /// Called as well as [onSelected] when the page changed because the person
  /// dragged along the row (not for taps or the drawer). The tutorial uses
  /// it to tell a real swipe from any other way of changing page.
  final ValueChanged<int>? onSwiped;
  final VoidCallback onHold;

  /// The disks along the row, in slot order.
  final List<DiskPage> pages;

  const DiskBar({
    super.key,
    required this.index,
    required this.onSelected,
    required this.onHold,
    this.onSwiped,
    this.pages = diskPages,
  });

  /// The middle disk's diameter; the side disks are a little smaller.
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

  @override
  State<DiskBar> createState() => _DiskBarState();
}

class _DiskBarState extends State<DiskBar> with SingleTickerProviderStateMixin {
  /// Where the row is turned to, in disk slots. Not wrapped: swiping on past
  /// the last page carries on to 7, 8... so the row keeps its direction, and
  /// each disk's place is worked out modulo the page count.
  late final ValueNotifier<double> _position;
  late final AnimationController _settle;

  double _settleFrom = 0;
  double _settleTo = 0;
  double _dragStartPosition = 0;

  int get _count => widget.pages.length;

  /// Pixels between neighbouring disks; set in build. The drag uses it so
  /// the row follows the finger 1:1.
  double _slotWidth = 92;

  @override
  void initState() {
    super.initState();
    _position = ValueNotifier(widget.index.toDouble());
    _settle = AnimationController(vsync: this, duration: Motion.slow)
      ..addListener(_settleTick);
  }

  @override
  void didUpdateWidget(DiskBar old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _turnTo(widget.index);
  }

  @override
  void dispose() {
    _settle.dispose();
    _position.dispose();
    super.dispose();
  }

  void _settleTick() {
    final t = Motion.enter.transform(_settle.value);
    _position.value = _settleFrom + (_settleTo - _settleFrom) * t;
  }

  /// Slots from [from] to the page [index], going the short way round.
  double _shortest(double from, int index) {
    final delta = (index - from) % _count;
    return delta > _count / 2 ? delta - _count : delta;
  }

  void _turnTo(int index) {
    _settle.stop();
    _settleFrom = _position.value;
    _settleTo = _settleFrom + _shortest(_settleFrom, index);
    _settle.forward(from: 0);
  }

  void _onDragStart(DragStartDetails d) {
    _settle.stop();
    _dragStartPosition = _position.value;
  }

  // Dragging left brings the next disk in, so the row moves with the finger.
  void _onDragUpdate(DragUpdateDetails d) {
    _position.value -= d.delta.dx / _slotWidth;
  }

  void _onDragEnd(DragEndDetails d) {
    // A flick carries the row a little further than where the finger left it.
    final thrown = _position.value - (d.primaryVelocity ?? 0) / 1000 * 0.5;
    final target = thrown.round().clamp(
      _dragStartPosition.round() - 3,
      _dragStartPosition.round() + 3,
    );
    final page = target % _count;
    if (page == widget.index) {
      _turnTo(widget.index);
    } else {
      HapticFeedback.selectionClick();
      widget.onSelected(page);
      widget.onSwiped?.call(page);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final diskSize = DiskBar.diskSizeFor(media.orientation);
    _slotWidth = diskSize * 1.5;

    return Semantics(
      container: true,
      label:
          'Pages. Swipe along the disks to change page, or press and hold '
          'to see them all.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onLongPressStart: (_) {
          HapticFeedback.mediumImpact();
          widget.onHold();
        },
        child: SizedBox(
          height: DiskBar.heightFor(context),
          child: ValueListenableBuilder<double>(
            valueListenable: _position,
            builder: (context, position, _) => _row(position, diskSize),
          ),
        ),
      ),
    );
  }

  Widget _row(double position, double diskSize) {
    // Each disk's distance from the middle, wrapped so the row is a loop.
    final slots = <(int, double)>[
      for (var i = 0; i < _count; i++)
        (i, ((i - position + _count / 2) % _count) - _count / 2),
    ];

    return LayoutBuilder(
      builder: (context, box) {
        final middle = box.maxWidth / 2;
        final bottom = max(MediaQuery.paddingOf(context).bottom, Space.md);
        return Stack(
          children: [
            for (final (i, d) in slots)
              // Three show; a fourth is already sliding in at the edge.
              if (d.abs() < 1.7) _placed(i, d, diskSize, middle, bottom),
          ],
        );
      },
    );
  }

  Widget _placed(
    int i,
    double d,
    double diskSize,
    double middle,
    double bottom,
  ) {
    final near = d.abs();
    // Full size in the middle, a little smaller either side; sizes follow
    // the drag, so a disk grows as it nears the middle.
    final size = diskSize * (1 - 0.16 * near.clamp(0, 1));
    // Fully there at one slot out; fades over the next half slot.
    final opacity = (1.7 - near).clamp(0.0, 0.7) / 0.7;
    return Positioned(
      left: middle + d * _slotWidth - size / 2,
      // Every disk sits on the same line (their centres line up), whatever
      // their size.
      bottom: bottom + (diskSize - size) / 2,
      child: Opacity(opacity: opacity, child: _disk(i, size)),
    );
  }

  Widget _disk(int i, double size) {
    final page = widget.pages[i];
    return Semantics(
      button: true,
      selected: i == widget.index,
      label: page.title,
      onTap: () => widget.onSelected(i),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: i == widget.index
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onSelected(i);
              },
        child: MiniDisk(
          size: size,
          diskColor: page.diskColor,
          icon: page.icon,
          active: i == widget.index,
        ),
      ),
    );
  }
}
