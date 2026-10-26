import 'package:flutter/material.dart';

import 'package:hu_accomponist/features/guides/guides_page.dart';
import 'package:hu_accomponist/features/home/home_page.dart';
import 'package:hu_accomponist/features/hum/hum_page.dart';
import 'package:hu_accomponist/features/onboarding/onboarding_store.dart';
import 'package:hu_accomponist/features/quiz/Quiz_Home_Page.dart';
import 'package:hu_accomponist/features/search/Music_Library_Page.dart';
import 'package:hu_accomponist/features/settings/settings_page.dart';
import 'package:hu_accomponist/features/shell/disk_bar.dart';
import 'package:hu_accomponist/features/shell/disk_drawer.dart';
import 'package:hu_accomponist/features/shell/disk_pages.dart';
import 'package:hu_accomponist/features/shell/shell_controller.dart';
import 'package:hu_accomponist/features/shell/tutorial_overlay.dart';
import 'package:hu_accomponist/features/shelf/Shelf_Page.dart';
import 'package:hu_accomponist/integrations/auth/auth_controller.dart';
import 'package:hu_accomponist/main.dart' show ScoreViewerPage;
import 'package:hu_accomponist/shared/theme/Color_Theme.dart';
import 'package:hu_accomponist/shared/theme/Design_Tokens.dart';

/// The signed-in app: the current page, the disk bar along the bottom, the
/// disk drawer and, the first time, the tutorial.
///
/// Pages are hosted here rather than pushed, so changing page doesn't stack
/// routes. Practice is kept alive once built (a score, an exercise and a
/// recording in progress should survive a look at Settings); every other
/// page is built when shown and dropped when left, as it was when each was a
/// pushed route, so a hum doesn't keep playing from another page.
class AppShell extends StatefulWidget {
  final AuthController auth;
  final ShellController controller;
  final OnboardingStore onboarding;

  /// Builds the page for a slot; tests stand in for the real pages, which
  /// need the microphone, a WebView and the server.
  @visibleForTesting
  final Widget Function(int slot)? pageBuilder;

  const AppShell({
    super.key,
    required this.auth,
    required this.controller,
    this.onboarding = const OnboardingStore(),
    this.pageBuilder,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  ShellController get _shell => widget.controller;

  late final AnimationController _fade;

  bool _drawerOpen = false;

  /// The tutorial step being shown, or null when there is no tutorial.
  int? _tutorialStep;
  int _tutorialRequestsSeen = 0;
  int _lastIndex = PageSlot.home;

  /// The person has done the swipe the tutorial asked for.
  bool _swipeDone = false;

  /// Practice is built the first time it is shown and kept after that.
  bool _practiceBuilt = false;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, duration: Motion.base, value: 1);
    _lastIndex = _shell.index;
    _practiceBuilt = _shell.index == PageSlot.practice;
    _tutorialRequestsSeen = _shell.tutorialRequests;
    _shell.addListener(_onShellChanged);
    widget.auth.addListener(_onAuthChanged);
    _startTutorialIfFirstRun();
  }

  @override
  void dispose() {
    _shell.removeListener(_onShellChanged);
    widget.auth.removeListener(_onAuthChanged);
    _fade.dispose();
    super.dispose();
  }

  // ── Tutorial ───────────────────────────────────────────────────────

  Future<void> _startTutorialIfFirstRun() async {
    final done = await widget.onboarding.hasCompleted();
    if (!done && mounted && _tutorialStep == null) _beginTutorial();
  }

  void _beginTutorial() {
    _shell.goTo(PageSlot.home);
    setState(() {
      _drawerOpen = false;
      _swipeDone = false;
      _tutorialStep = TutorialStep.welcome;
    });
  }

  void _setStep(int step) {
    if (!mounted || _tutorialStep == null) return;
    setState(() => _tutorialStep = step);
  }

  void _nextStep() {
    final step = _tutorialStep;
    if (step == null) return;
    if (step == TutorialStep.hold) {
      // Skipping the hold: show what it would have done.
      _openDrawer();
      return;
    }
    if (step == TutorialStep.drawer) {
      setState(() => _drawerOpen = false);
    }
    _setStep(step + 1);
    if (step + 1 == TutorialStep.tour) _shell.goTo(PageSlot.home);
  }

  /// The disk bar reports a swipe that changed the page. Only that counts
  /// for the tutorial: tapping a disk or using the drawer doesn't.
  void _onSwiped(int page) {
    if (_tutorialStep != TutorialStep.swipe || _swipeDone) return;
    setState(() => _swipeDone = true);
    // Let the congratulation be seen, and the new page, before moving on.
    Future<void>.delayed(const Duration(milliseconds: 1100), () {
      if (mounted && _tutorialStep == TutorialStep.swipe) {
        _swipeDone = false;
        _setStep(TutorialStep.hold);
      }
    });
  }

  /// Ends the tour, finished or skipped, and remembers it so it doesn't
  /// start by itself again.
  Future<void> _endTutorial() async {
    setState(() {
      _tutorialStep = null;
      _drawerOpen = false;
    });
    _shell.goTo(PageSlot.home);
    await widget.onboarding.setCompleted(true);
  }

  // ── Shell changes ──────────────────────────────────────────────────

  List<DiskPage> get _pages => diskPages;

  /// Roles arrive with the account: the Guides page shows its editing
  /// tools only to authors, so it rebuilds when they change.
  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  void _onShellChanged() {
    if (_shell.tutorialRequests != _tutorialRequestsSeen) {
      _tutorialRequestsSeen = _shell.tutorialRequests;
      _beginTutorial();
    }
    if (_shell.index == PageSlot.practice) _practiceBuilt = true;
    if (_shell.index != _lastIndex) {
      _lastIndex = _shell.index;
      _fade.forward(from: 0);
    }
    if (mounted) setState(() {});
  }

  void _openDrawer() {
    if (_drawerOpen) return;
    setState(() {
      _drawerOpen = true;
      if (_tutorialStep == TutorialStep.swipe ||
          _tutorialStep == TutorialStep.hold) {
        _tutorialStep = TutorialStep.drawer;
      }
    });
  }

  void _closeDrawer() {
    if (!_drawerOpen) return;
    setState(() {
      _drawerOpen = false;
      if (_tutorialStep == TutorialStep.drawer) {
        _tutorialStep = TutorialStep.tour;
      }
    });
    if (_tutorialStep == TutorialStep.tour) _shell.goTo(PageSlot.home);
  }

  void _pickFromDrawer(int index) {
    _shell.goTo(index);
    _closeDrawer();
  }

  // ── Build ──────────────────────────────────────────────────────────

  Widget _page(int slot) => widget.pageBuilder?.call(slot) ?? _realPage(slot);

  Widget _realPage(int slot) => switch (slot) {
    PageSlot.home => HomePage(userName: widget.auth.user?.displayName),
    PageSlot.practice => ScoreViewerPage(selected: _shell.practiceScore),
    PageSlot.search => const Music_Library_Page(),
    PageSlot.shelf => const Shelf_Page(),
    PageSlot.quiz => const Quiz_Home_Page(),
    PageSlot.hum => const HumPage(),
    PageSlot.guides => GuidesPage(auth: widget.auth),
    _ => SettingsPage(auth: widget.auth),
  };

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // The bar steps aside for the keyboard rather than riding up on it, and
    // for a page that wants the whole screen.
    final barVisible = media.viewInsets.bottom == 0 && !_shell.immersive;
    final barHeight = DiskBar.heightFor(context);
    final pages = _pages;
    // A slot not offered (a stale Guides index) shows Home meanwhile.
    final index = _shell.index < pages.length ? _shell.index : PageSlot.home;
    final blocking = _drawerOpen || _tutorialStep != null;

    // Pages are told the bar's height is part of the bottom inset, so their
    // SafeAreas and scroll views already keep clear of it.
    final pageMedia = media.copyWith(
      padding: media.padding.copyWith(
        bottom: barVisible ? barHeight : media.padding.bottom,
      ),
      viewPadding: media.viewPadding.copyWith(
        bottom: barVisible ? barHeight : media.viewPadding.bottom,
      ),
    );

    return PopScope(
      // Back closes the drawer or the tour first, then returns to Practice,
      // and only then leaves the app.
      canPop: !blocking && index == PageSlot.home,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_drawerOpen) {
          _closeDrawer();
        } else if (_tutorialStep != null) {
          _endTutorial();
        } else {
          _shell.goTo(PageSlot.home);
        }
      },
      child: ColoredBox(
        color: TurntablePalette.background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MediaQuery(
              data: pageMedia,
              child: InShellPage(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    for (var slot = 0; slot < pages.length; slot++)
                      if ((slot == PageSlot.practice && _practiceBuilt) ||
                          slot == index)
                        _hosted(slot, active: slot == index),
                  ],
                ),
              ),
            ),
            if (barVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DiskBar(
                  index: index,
                  onSelected: _shell.goTo,
                  onSwiped: _onSwiped,
                  onHold: _openDrawer,
                  pages: pages,
                ),
              ),
            DiskDrawer(
              open: _drawerOpen,
              index: index,
              onSelected: _pickFromDrawer,
              onClose: _closeDrawer,
              pages: pages,
            ),
            if (_tutorialStep case final step?)
              Positioned.fill(
                child: TutorialOverlay(
                  step: step,
                  barHeight: barHeight,
                  succeeded: _swipeDone,
                  onNext: _nextStep,
                  onSkip: _endTutorial,
                  onDone: _endTutorial,
                  pages: pages,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// One page of the shell. Practice stays in the tree while another page is
  /// shown, hidden and with its animations stopped. The wrapper widgets are
  /// the same whether or not the page is active, so switching never rebuilds
  /// the page from scratch.
  Widget _hosted(int slot, {required bool active}) {
    return Offstage(
      key: ValueKey(slot),
      offstage: !active,
      child: TickerMode(
        enabled: active,
        child: FadeTransition(
          opacity: active ? _fade : const AlwaysStoppedAnimation<double>(1),
          child: _page(slot),
        ),
      ),
    );
  }
}
