import 'package:flutter/material.dart';

import 'package:hu_accomponist/shared/theme/Color_Theme.dart';

/// One destination in the app, as the bottom disks, the disk drawer and the
/// tutorial describe it. The page itself is built by the shell.
class DiskPage {
  final String title;
  final String caption;
  final IconData icon;
  final Color diskColor;

  const DiskPage({
    required this.title,
    required this.caption,
    required this.icon,
    required this.diskColor,
  });
}

/// Positions in [diskPages]. The order is the order of the disks.
abstract final class PageSlot {
  static const int home = 0;
  static const int practice = 1;
  static const int search = 2;
  static const int shelf = 3;
  static const int quiz = 4;
  static const int hum = 5;
  static const int settings = 6;

  /// Everyone reads guidelines here; only admins and verified contributors
  /// can write them.
  static const int guides = 7;
}

/// The Guides disk: how-to-play guidelines, and (for authors) writing them.
const DiskPage guidesDiskPage = DiskPage(
  title: 'Guides',
  caption: 'How-to-play guidelines for eras, composers and pieces',
  icon: Icons.menu_book_rounded,
  diskColor: TurntablePalette.diskGuides,
);

const List<DiskPage> diskPages = [
  DiskPage(
    title: 'Home',
    caption: 'Pick up where you left off',
    icon: Icons.home_rounded,
    diskColor: TurntablePalette.diskHome,
  ),
  DiskPage(
    title: 'Practice',
    caption: 'Play along with a score or an exercise',
    icon: Icons.piano_rounded,
    diskColor: TurntablePalette.diskPractice,
  ),
  DiskPage(
    title: 'Search',
    caption: 'Find sheet music in the library',
    icon: Icons.search_rounded,
    diskColor: TurntablePalette.diskSearch,
  ),
  DiskPage(
    title: 'Shelf',
    caption: 'Your saved scores and hummed songs',
    icon: Icons.collections_bookmark_rounded,
    diskColor: TurntablePalette.diskShelf,
  ),
  DiskPage(
    title: 'Quiz',
    caption: 'Test your theory and history',
    icon: Icons.quiz_rounded,
    diskColor: TurntablePalette.diskQuiz,
  ),
  DiskPage(
    title: 'Hum',
    caption: 'Hum a tune and get a song',
    icon: Icons.mic_rounded,
    diskColor: TurntablePalette.diskHum,
  ),
  DiskPage(
    title: 'Settings',
    caption: 'Your account, support and legal',
    icon: Icons.settings_rounded,
    diskColor: TurntablePalette.diskSettings,
  ),
  guidesDiskPage,
];
