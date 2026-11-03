import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hu_accomponist/features/shell/disk_pages.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// A section of the shell that holds several pages: a row of tabs along the
/// top and the selected page under it.
///
/// Like the shell itself, the pages are built when shown and dropped when
/// left, except [keepAliveTab] (Practice), which is kept once built so a
/// score or a recording survives a look at another tab.
class SectionTabs extends StatefulWidget {
  final List<DiskPage> tabs;
  final int selected;
  final ValueChanged<int> onSelected;
  final Widget Function(int tab) pageBuilder;
  final int? keepAliveTab;

  /// The page wants the whole screen: the tab row steps aside.
  final bool hideTabs;

  const SectionTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onSelected,
    required this.pageBuilder,
    this.keepAliveTab,
    this.hideTabs = false,
  });

  @override
  State<SectionTabs> createState() => _SectionTabsState();
}

class _SectionTabsState extends State<SectionTabs> {
  bool _keptBuilt = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected.clamp(0, widget.tabs.length - 1);
    if (selected == widget.keepAliveTab) _keptBuilt = true;
    final showTabs = !widget.hideTabs;

    // The widget tree keeps the same shape whether or not the tab row shows,
    // so hiding it never rebuilds the page from scratch.
    return ColoredBox(
      color: PracticePalette.ivory,
      child: Column(
        children: [
          if (showTabs)
            _TabRow(
              tabs: widget.tabs,
              selected: selected,
              onSelected: widget.onSelected,
            )
          else
            const SizedBox.shrink(),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: showTabs,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  for (var tab = 0; tab < widget.tabs.length; tab++)
                    if (tab == selected ||
                        (tab == widget.keepAliveTab && _keptBuilt))
                      Offstage(
                        key: ValueKey(tab),
                        offstage: tab != selected,
                        child: TickerMode(
                          enabled: tab == selected,
                          child: widget.pageBuilder(tab),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabRow extends StatelessWidget {
  final List<DiskPage> tabs;
  final int selected;
  final ValueChanged<int> onSelected;

  const _TabRow({
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PracticePalette.paper,
      child: SafeArea(
        bottom: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: PracticePalette.lightGold.withValues(alpha: 0.65),
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.xs,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++) ...[
                  if (i > 0) const SizedBox(width: Space.xs),
                  _TabPill(
                    page: tabs[i],
                    active: i == selected,
                    onTap: () {
                      if (i == selected) return;
                      HapticFeedback.selectionClick();
                      onSelected(i);
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final DiskPage page;
  final bool active;
  final VoidCallback onTap;

  const _TabPill({
    required this.page,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? PracticePalette.paper : PracticePalette.mutedBrown;
    return Semantics(
      button: true,
      selected: active,
      label: page.title,
      excludeSemantics: true,
      child: Tooltip(
        message: page.caption,
        triggerMode: TooltipTriggerMode.manual,
        waitDuration: navTooltipWait,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.pillRadius,
          child: AnimatedContainer(
            duration: Motion.fast,
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.xs,
            ),
            decoration: BoxDecoration(
              color: active ? PracticePalette.gold : Colors.transparent,
              borderRadius: Radii.pillRadius,
              border: Border.all(
                color: active
                    ? PracticePalette.gold
                    : PracticePalette.lightGold,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(page.icon, size: 16, color: color),
                const SizedBox(width: Space.xxs),
                Text(
                  page.title,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
