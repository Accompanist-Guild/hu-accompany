import 'package:flutter/material.dart';

import 'package:hu_accomponist/shared/theme/Color_Theme.dart';

/// One destination in the app, as the bottom disks, the disk drawer and the
/// tutorial describe it. The page itself is built by the shell. Sub-tabs
/// inside a section use the same description.
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

  /// Shown when a mouse rests on the page's disk or tab.
  String get tooltip => '$title\n$caption';
}

/// How long the mouse rests on a disk or tab before its tooltip shows.
const Duration navTooltipWait = Duration(milliseconds: 400);

/// The pages of the shell. The first ones are [diskPages], in the order of
/// the disks; User Account has no disk and is opened from the person's icon
/// on Home.
abstract final class PageSlot {
  static const int home = 0;

  /// Practice, Search and Shelf, as tabs ([PracticeTab]).
  static const int practiceRoom = 1;
  static const int discussion = 2;

  /// Guides and Quiz, as tabs ([LearningTab]).
  static const int learning = 3;

  /// The extras, as tabs ([MinigameTab]).
  static const int minigames = 4;

  /// Account, support and legal (the Settings page). Not a disk.
  static const int account = 5;

  static const int count = 6;
}

/// Tabs of the Practice Room, in [sectionTabs] order.
abstract final class PracticeTab {
  static const int practice = 0;
  static const int search = 1;
  static const int shelf = 2;
}

/// Tabs of the Learning Area. Everyone reads guidelines; only admins and
/// verified contributors can write them.
abstract final class LearningTab {
  static const int guides = 0;
  static const int quiz = 1;
}

/// Tabs of Minigames.
abstract final class MinigameTab {
  static const int hum = 0;
}

const List<DiskPage> diskPages = [
  DiskPage(
    title: 'Home',
    caption: 'Pick up where you left off',
    icon: Icons.home_rounded,
    diskColor: TurntablePalette.diskHome,
  ),
  DiskPage(
    title: 'Practice Room',
    caption: 'Practice, find sheet music and keep your scores',
    icon: Icons.piano_rounded,
    diskColor: TurntablePalette.diskPractice,
  ),
  DiskPage(
    title: 'Discussion Hub',
    caption: 'Talk music with other players (coming soon)',
    icon: Icons.forum_rounded,
    diskColor: TurntablePalette.diskDiscussion,
  ),
  DiskPage(
    title: 'Learning Area',
    caption: 'How-to-play guides and quizzes',
    icon: Icons.menu_book_rounded,
    diskColor: TurntablePalette.diskGuides,
  ),
  DiskPage(
    title: 'Minigames',
    caption: 'Extras to play with, like humming a song',
    icon: Icons.videogame_asset_rounded,
    diskColor: TurntablePalette.diskHum,
  ),
];

/// User Account: opened from the person's icon on Home, not from a disk.
const DiskPage accountPage = DiskPage(
  title: 'User Account',
  caption: 'Your account, support and legal',
  icon: Icons.person_rounded,
  diskColor: TurntablePalette.diskSettings,
);

/// The description of any [PageSlot], disk or not.
DiskPage pageFor(int slot) =>
    slot == PageSlot.account ? accountPage : diskPages[slot];

/// The tabs of each section that has them, keyed by [PageSlot].
const Map<int, List<DiskPage>> sectionTabs = {
  PageSlot.practiceRoom: [
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
  ],
  PageSlot.learning: [
    DiskPage(
      title: 'Guides',
      caption: 'How-to-play guidelines for eras, composers and pieces',
      icon: Icons.menu_book_rounded,
      diskColor: TurntablePalette.diskGuides,
    ),
    DiskPage(
      title: 'Quiz',
      caption: 'Test your theory and history',
      icon: Icons.quiz_rounded,
      diskColor: TurntablePalette.diskQuiz,
    ),
  ],
  PageSlot.minigames: [
    DiskPage(
      title: 'Hum',
      caption: 'Hum a tune and get a song',
      icon: Icons.mic_rounded,
      diskColor: TurntablePalette.diskHum,
    ),
  ],
};
