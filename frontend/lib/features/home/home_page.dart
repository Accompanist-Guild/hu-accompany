import 'package:flutter/material.dart';

import 'package:hu_accomponist/features/practice/Open_Practice.dart';
import 'package:hu_accomponist/features/shell/disk_pages.dart';
import 'package:hu_accomponist/features/shell/mini_disk.dart';
import 'package:hu_accomponist/features/shell/shell_controller.dart';
import 'package:hu_accomponist/features/shelf/Shelf_Manager.dart';
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';
import 'package:hu_accomponist/shared/ui/Press_Scale.dart';
import 'package:hu_accomponist/shared/ui/Shimmer.dart';

/// "Today, 3:15 PM", "Yesterday", "Tuesday" or "Oct 12": how long ago a
/// score was last played, in the fewest words that are still exact.
String lastPlayedLabel(DateTime playedAt, DateTime now) {
  final day = DateTime(playedAt.year, playedAt.month, playedAt.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  if (days <= 0) {
    final hour = playedAt.hour % 12 == 0 ? 12 : playedAt.hour % 12;
    final minute = playedAt.minute.toString().padLeft(2, '0');
    return 'Today, $hour:$minute ${playedAt.hour < 12 ? 'AM' : 'PM'}';
  }
  if (days == 1) return 'Yesterday';
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  if (days < 7) return weekdays[playedAt.weekday - 1];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[playedAt.month - 1]} ${playedAt.day}';
}

/// The first page of the app: where you left off, and a way into every other
/// page. Everything on it goes through what already exists: the shelf's own
/// record of what was played, [OpenPractice] to open a score, and the
/// shell's [ShellController] to change page.
class HomePage extends StatefulWidget {
  final String? userName;

  /// Recently played scores, newest first. Defaults to the shelf's store.
  final Future<List<ShelfEntry>> Function() loadRecent;

  /// Opens a score in Practice. Defaults to [OpenPractice.withShelfEntry],
  /// which fetches the score and hands it to the shell.
  final Future<void> Function(BuildContext context, ShelfEntry entry) openEntry;

  final DateTime Function() now;

  const HomePage({
    super.key,
    this.userName,
    this.loadRecent = ShelfManager.loadAll,
    this.openEntry = OpenPractice.withShelfEntry,
    this.now = DateTime.now,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Future<List<ShelfEntry>> _recent = widget.loadRecent();

  static const int _moreShown = 2;

  String _greeting() {
    final hour = widget.now().hour;
    final part = hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    final name = widget.userName;
    return name == null || name.isEmpty ? part : '$part, $name';
  }

  void _go(int slot) => ShellScope.maybeOf(context)?.goTo(slot);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PracticePalette.ivory,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              physics: AppScroll.physics,
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.xl,
                Space.lg,
                Space.xxl,
              ),
              children: [
                _header(),
                const SizedBox(height: Space.xl),
                FutureBuilder<List<ShelfEntry>>(
                  future: _recent,
                  builder: (context, snapshot) => _recentSection(snapshot),
                ),
                const SizedBox(height: Space.xl),
                const _SectionLabel('Jump to'),
                const SizedBox(height: Space.sm),
                _navigation(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'HU ACCOMPONIST',
                style: TextStyle(
                  color: PracticePalette.gold,
                  fontSize: 11,
                  letterSpacing: 2.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                _greeting(),
                style: const TextStyle(
                  color: PracticePalette.brown,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: Space.md),
        MiniDisk(
          size: 52,
          diskColor: TurntablePalette.diskPractice,
          icon: Icons.music_note_rounded,
        ),
      ],
    );
  }

  Widget _recentSection(AsyncSnapshot<List<ShelfEntry>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const _RecentSkeleton();
    }
    // A store that can't be read is the same as one with nothing in it.
    final recent = snapshot.data ?? const <ShelfEntry>[];
    if (recent.isEmpty) return _emptyRecent();

    final latest = recent.first;
    final earlier = recent.skip(1).take(_moreShown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Continue practicing'),
        const SizedBox(height: Space.sm),
        _LatestCard(
          entry: latest,
          when: lastPlayedLabel(latest.playedAt, widget.now()),
          onContinue: () => widget.openEntry(context, latest),
        ),
        if (earlier.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          const _SectionLabel('Earlier'),
          const SizedBox(height: Space.xs),
          for (final entry in earlier)
            _EarlierRow(
              entry: entry,
              when: lastPlayedLabel(entry.playedAt, widget.now()),
              onTap: () => widget.openEntry(context, entry),
            ),
        ],
      ],
    );
  }

  Widget _emptyRecent() {
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nothing played yet',
            style: TextStyle(
              color: PracticePalette.brown,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Space.xxs),
          const Text(
            'Find a score in the library, or start with a short exercise. '
            'Whatever you play shows up here, ready to pick up again.',
            style: TextStyle(
              color: PracticePalette.mutedBrown,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.xs,
            children: [
              FilledButton.icon(
                onPressed: () => _go(PageSlot.search),
                icon: const Icon(Icons.search_rounded, size: 18),
                label: const Text('Find a score'),
                style: _goldButton,
              ),
              OutlinedButton.icon(
                onPressed: () => _go(PageSlot.practice),
                icon: const Icon(Icons.piano_rounded, size: 18),
                label: const Text('Try an exercise'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PracticePalette.gold,
                  side: const BorderSide(color: PracticePalette.lightGold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _navigation() {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = Space.sm;
        final columns = box.maxWidth >= 560 ? 3 : 2;
        final width = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            // Every page but this one.
            for (var slot = PageSlot.practice; slot < diskPages.length; slot++)
              SizedBox(
                width: width,
                child: _NavCard(page: diskPages[slot], onTap: () => _go(slot)),
              ),
          ],
        );
      },
    );
  }
}

final BoxDecoration _cardDecoration = BoxDecoration(
  color: PracticePalette.paper,
  borderRadius: Radii.cardRadius,
  border: Border.all(color: PracticePalette.lightGold.withValues(alpha: 0.65)),
  boxShadow: Elevations.card(PracticePalette.brown),
);

final ButtonStyle _goldButton = FilledButton.styleFrom(
  backgroundColor: PracticePalette.gold,
  foregroundColor: PracticePalette.paper,
  minimumSize: const Size(0, 44),
  shape: const RoundedRectangleBorder(borderRadius: Radii.cardRadius),
);

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: PracticePalette.mutedBrown,
      fontSize: 11,
      letterSpacing: 1.8,
      fontWeight: FontWeight.w700,
    ),
  );
}

/// The score to carry on with: cover, who and when, and the one big button.
class _LatestCard extends StatelessWidget {
  final ShelfEntry entry;
  final String when;
  final VoidCallback onContinue;

  const _LatestCard({
    required this.entry,
    required this.when,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onContinue,
      borderRadius: Radii.cardRadius,
      pressedScale: 0.985,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: _cardDecoration,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Cover(entry: entry, width: 88),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PracticePalette.brown,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  if (entry.composer.isNotEmpty) ...[
                    const SizedBox(height: Space.xxs),
                    Text(
                      entry.composer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PracticePalette.mutedBrown,
                        fontSize: 14,
                      ),
                    ),
                  ],
                  const SizedBox(height: Space.xxs),
                  Text(
                    'Last played · $when',
                    style: TextStyle(
                      color: PracticePalette.mutedBrown.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  FilledButton.icon(
                    onPressed: onContinue,
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('Continue Practicing'),
                    style: _goldButton,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stands in for a thumbnail until scores have real ones: the same stable
/// colours the shelf gives the piece, with a staff drawn on it.
class _Cover extends StatelessWidget {
  final ShelfEntry entry;
  final double width;
  const _Cover({required this.entry, required this.width});

  @override
  Widget build(BuildContext context) {
    final colors = ShelfPalette.gradientFor(entry.id);
    return Container(
      width: width,
      height: width * 1.28,
      decoration: BoxDecoration(
        borderRadius: Radii.cardRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: CustomPaint(painter: _StaffPainter()),
    );
  }
}

class _StaffPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    final top = size.height * 0.34;
    final gap = size.height * 0.07;
    for (var i = 0; i < 5; i++) {
      canvas.drawLine(
        Offset(size.width * 0.12, top + gap * i),
        Offset(size.width * 0.88, top + gap * i),
        line,
      );
    }
    final head = Paint()..color = Colors.white.withValues(alpha: 0.8);
    for (final (x, row) in const [(0.28, 3), (0.46, 1), (0.64, 2), (0.80, 0)]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * x, top + gap * row),
          width: gap * 1.3,
          height: gap,
        ),
        head,
      );
    }
  }

  @override
  bool shouldRepaint(_StaffPainter old) => false;
}

class _EarlierRow extends StatelessWidget {
  final ShelfEntry entry;
  final String when;
  final VoidCallback onTap;
  const _EarlierRow({
    required this.entry,
    required this.when,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      borderRadius: Radii.cardRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(
          children: [
            _Cover(entry: entry, width: 36),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PracticePalette.brown,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    [
                      if (entry.composer.isNotEmpty) entry.composer,
                      when,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PracticePalette.mutedBrown,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: PracticePalette.mutedBrown,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  final DiskPage page;
  final VoidCallback onTap;
  const _NavCard({required this.page, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      borderRadius: Radii.cardRadius,
      pressedScale: 0.97,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: _cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: PracticePalette.gold.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(page.icon, size: 20, color: PracticePalette.gold),
            ),
            const SizedBox(height: Space.sm),
            Text(
              page.title,
              style: const TextStyle(
                color: PracticePalette.brown,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.xxs),
            Text(
              page.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: PracticePalette.mutedBrown,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentSkeleton extends StatelessWidget {
  const _RecentSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      base: PracticePalette.lightGold.withValues(alpha: 0.25),
      highlight: PracticePalette.lightGold.withValues(alpha: 0.5),
      child: Container(
        key: const Key('home-recent-loading'),
        height: 152,
        decoration: BoxDecoration(
          color: PracticePalette.lightGold.withValues(alpha: 0.25),
          borderRadius: Radii.cardRadius,
        ),
      ),
    );
  }
}
