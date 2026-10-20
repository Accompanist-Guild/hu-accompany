import 'package:flutter/widgets.dart';

import 'package:hu_accomponist/features/shell/disk_pages.dart';
import 'package:hu_accomponist/integrations/scores/score_models.dart';

/// Which page the shell is showing, and the few things other pages can ask
/// of it. It lives above the Navigator (see [ShellScope]) so that a page
/// pushed on top of the shell, like the shelf opened from the library, can
/// still send the person to Practice.
class ShellController extends ChangeNotifier {
  int _index = PageSlot.home;
  LoadedScore? _practiceScore;
  int _tutorialRequests = 0;

  int get index => _index;

  /// The score Practice was last told to open, if any.
  LoadedScore? get practiceScore => _practiceScore;

  /// Counts "show the tutorial" requests; the shell compares it with the
  /// count it has already honoured.
  int get tutorialRequests => _tutorialRequests;

  void goTo(int index) {
    assert(index >= 0 && index < diskPages.length);
    if (index == _index) return;
    _index = index;
    notifyListeners();
  }

  /// Opens [score] in Practice. Always notifies, even if Practice is already
  /// showing, since the score itself has changed.
  void openScore(LoadedScore score) {
    _practiceScore = score;
    _index = PageSlot.practice;
    notifyListeners();
  }

  void replayTutorial() {
    _index = PageSlot.home;
    _tutorialRequests++;
    notifyListeners();
  }

  /// Back to a fresh start, for the next person who signs in.
  void reset() {
    _index = PageSlot.home;
    _practiceScore = null;
    notifyListeners();
  }
}

/// Makes the [ShellController] reachable from every route.
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.controller, required super.child});

  final ShellController controller;

  /// Null when the app isn't running inside the shell (a page under test).
  static ShellController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellScope>()?.controller;

  @override
  bool updateShouldNotify(ShellScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Marks the pages the shell hosts directly, as opposed to the same pages
/// pushed as routes. A hosted page has nowhere to go "back" to, so it hides
/// its back and close buttons.
class InShellPage extends InheritedWidget {
  const InShellPage({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<InShellPage>() != null;

  @override
  bool updateShouldNotify(InShellPage oldWidget) => false;
}
