import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hu_accomponist/features/onboarding/onboarding_store.dart';
import 'package:hu_accomponist/features/shell/app_shell.dart';
import 'package:hu_accomponist/features/shell/disk_bar.dart';
import 'package:hu_accomponist/features/shell/disk_drawer.dart';
import 'package:hu_accomponist/features/shell/disk_pages.dart';
import 'package:hu_accomponist/features/shell/mini_disk.dart';
import 'package:hu_accomponist/features/shell/shell_controller.dart';
import 'package:hu_accomponist/integrations/auth/auth_controller.dart';
import 'package:hu_accomponist/integrations/auth/session_store.dart';

import 'support/auth_fakes.dart';

/// A page that remembers a count, to tell a page kept alive from a rebuilt one.
class _Counter extends StatefulWidget {
  const _Counter({required this.name});
  final String name;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => setState(() => taps++),
        child: Text('${widget.name}:$taps'),
      ),
    ),
  );
}

void main() {
  late ShellController shell;
  late AuthController auth;
  late List<String> haptics;
  late double? lastPageBottomInset;

  setUp(() {
    shell = ShellController();
    lastPageBottomInset = null;
    haptics = [];
  });

  tearDown(() => shell.dispose());

  Future<void> pumpShell(
    WidgetTester tester, {
    bool onboardingDone = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      OnboardingStore.key: onboardingDone,
    });
    auth = AuthController(
      store: MemorySessionStore(const StoredSession(token: 't', user: ada)),
      repository: FakeAuthRepository(),
    );
    addTearDown(auth.dispose);
    await auth.restore();

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        // Stops the tutorial's pulsing outline, which would otherwise keep
        // pumpAndSettle waiting forever.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: ShellScope(controller: shell, child: child!),
        ),
        home: AppShell(
          auth: auth,
          controller: shell,
          pageBuilder: (slot) => switch (slot) {
            PageSlot.practice => const _Counter(name: 'practice'),
            PageSlot.shelf => const _Counter(name: 'shelf'),
            _ => Builder(
              builder: (context) {
                lastPageBottomInset = MediaQuery.paddingOf(context).bottom;
                return Scaffold(
                  body: Center(child: Text('page:${diskPages[slot].title}')),
                );
              },
            ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> swipeBar(WidgetTester tester, double dx) async {
    await tester.drag(find.byType(DiskBar), Offset(dx, 0));
    await tester.pumpAndSettle();
  }

  group('bottom disk bar', () {
    testWidgets('opens on Home with its disk in the middle', (tester) async {
      await pumpShell(tester);
      expect(shell.index, PageSlot.home);
      expect(find.text('page:Home'), findsOneWidget);
      final active = tester
          .widgetList<MiniDisk>(find.byType(MiniDisk))
          .where((disk) => disk.active);
      expect(active.single.icon, diskPages[PageSlot.home].icon);
    });

    testWidgets('shows three disks, the middle one marked', (tester) async {
      await pumpShell(tester);
      final disks = tester.widgetList<MiniDisk>(find.byType(MiniDisk));
      // The page before, this one and the page after (the next one beyond is
      // still fully faded out).
      final visible = tester.widgetList<Opacity>(
        find.descendant(
          of: find.byType(DiskBar),
          matching: find.byType(Opacity),
        ),
      );
      expect(visible.where((o) => o.opacity > 0.99).length, 3);
      expect(disks.where((d) => d.active).length, 1);
    });

    testWidgets('the three disks sit in a row, evenly spaced', (tester) async {
      await pumpShell(tester);
      final centers = [
        for (final icon in [
          diskPages[PageSlot.settings].icon,
          diskPages[PageSlot.home].icon,
          diskPages[PageSlot.practice].icon,
        ])
          tester.getCenter(
            find.byWidgetPredicate((w) => w is MiniDisk && w.icon == icon),
          ),
      ];
      expect(centers[0].dy, closeTo(centers[1].dy, 0.5));
      expect(centers[1].dy, closeTo(centers[2].dy, 0.5));
      expect(
        centers[1].dx - centers[0].dx,
        closeTo(centers[2].dx - centers[1].dx, 0.5),
      );
      expect(centers[1].dx, closeTo(200, 0.5)); // middle of a 400-wide screen
    });

    testWidgets('swiping left cycles to the next page, right to the last', (
      tester,
    ) async {
      await pumpShell(tester);
      await swipeBar(tester, -100);
      expect(shell.index, PageSlot.practice);
      expect(find.text('practice:0'), findsOneWidget);

      await swipeBar(tester, 100);
      expect(shell.index, PageSlot.home);
    });

    testWidgets('swiping right from the first page wraps to the last', (
      tester,
    ) async {
      await pumpShell(tester);
      await swipeBar(tester, 100);
      expect(shell.index, PageSlot.settings);
      expect(find.text('page:Settings'), findsOneWidget);

      await swipeBar(tester, -100);
      expect(shell.index, PageSlot.home);
    });

    testWidgets('a short drag settles back on the same page', (tester) async {
      await pumpShell(tester);
      await swipeBar(tester, -30);
      expect(shell.index, PageSlot.home);
      // And the disks are back where they were: the middle one is centred.
      final middle = find.byWidgetPredicate(
        (w) => w is MiniDisk && w.icon == diskPages[PageSlot.home].icon,
      );
      expect(tester.getCenter(middle).dx, closeTo(200, 0.5));
    });

    testWidgets('a fling can browse past the neighbouring page', (
      tester,
    ) async {
      await pumpShell(tester);
      await tester.fling(find.byType(DiskBar), const Offset(-200, 0), 2000);
      await tester.pumpAndSettle();
      expect(shell.index, greaterThan(PageSlot.practice));
    });

    testWidgets('tapping a neighbouring disk goes to its page', (tester) async {
      await pumpShell(tester);
      final practiceDisk = find.byWidgetPredicate(
        (w) => w is MiniDisk && w.icon == diskPages[PageSlot.practice].icon,
      );
      await tester.tap(practiceDisk);
      await tester.pumpAndSettle();
      expect(shell.index, PageSlot.practice);
      expect(find.text('practice:0'), findsOneWidget);
    });

    testWidgets('pages are given the bar as part of their bottom inset', (
      tester,
    ) async {
      await pumpShell(tester);
      shell.goTo(PageSlot.quiz);
      await tester.pumpAndSettle();
      expect(lastPageBottomInset, tester.getSize(find.byType(DiskBar)).height);
    });

    testWidgets('Practice is kept while another page is shown', (tester) async {
      await pumpShell(tester);
      shell.goTo(PageSlot.practice);
      await tester.pumpAndSettle();
      await tester.tap(find.text('practice:0'));
      await tester.pump();
      expect(find.text('practice:1'), findsOneWidget);

      shell.goTo(PageSlot.shelf);
      await tester.pumpAndSettle();
      expect(find.text('practice:1', skipOffstage: false), findsOneWidget);
      expect(find.text('practice:1'), findsNothing); // hidden
      await tester.tap(find.text('shelf:0'));
      await tester.pump();
      expect(find.text('shelf:1'), findsOneWidget);

      shell.goTo(PageSlot.practice);
      await tester.pumpAndSettle();
      expect(find.text('practice:1'), findsOneWidget);

      // Other pages start afresh each visit.
      shell.goTo(PageSlot.shelf);
      await tester.pumpAndSettle();
      expect(find.text('shelf:0'), findsOneWidget);
    });

    testWidgets('Practice is not built until it is first shown', (
      tester,
    ) async {
      await pumpShell(tester);
      expect(find.text('practice:0', skipOffstage: false), findsNothing);
    });
  });

  group('disk drawer', () {
    testWidgets('holding the bar buzzes and opens every page', (tester) async {
      await pumpShell(tester);
      expect(find.text('QUIZ'), findsNothing);

      await tester.longPress(find.byType(DiskBar));
      await tester.pumpAndSettle();

      expect(haptics, contains('HapticFeedbackType.mediumImpact'));
      for (final page in diskPages) {
        expect(find.text(page.title.toUpperCase()), findsWidgets);
      }
      expect(find.text('QUIZ'), findsOneWidget);
      expect(find.text('SETTINGS'), findsOneWidget);
    });

    testWidgets('labels are plain text, centred under their disk', (
      tester,
    ) async {
      await pumpShell(tester);
      await tester.longPress(find.byType(DiskBar));
      await tester.pumpAndSettle();

      for (final page in diskPages) {
        final label = tester.widget<Text>(find.text(page.title.toUpperCase()));
        // No fallback style: the yellow double underline that shows when
        // text has no Material above it.
        final style = DefaultTextStyle.of(
          tester.element(find.text(page.title.toUpperCase())),
        );
        expect(style.style.decoration, isNot(TextDecoration.underline));
        expect(label.style?.decoration, isNull);

        final disk = tester.getCenter(
          find.descendant(
            of: find.byType(DiskDrawer),
            matching: find.byWidgetPredicate(
              (w) => w is MiniDisk && w.icon == page.icon,
            ),
          ),
        );
        expect(
          tester.getCenter(find.text(page.title.toUpperCase())).dx,
          closeTo(disk.dx, 0.5),
          reason: page.title,
        );
      }
    });

    testWidgets('tapping a disk goes there and closes the drawer', (
      tester,
    ) async {
      await pumpShell(tester);
      await tester.longPress(find.byType(DiskBar));
      await tester.pumpAndSettle();

      await tester.tap(find.text('QUIZ'));
      await tester.pumpAndSettle();

      expect(shell.index, PageSlot.quiz);
      expect(find.text('page:Quiz'), findsOneWidget);
      expect(find.text('SETTINGS'), findsNothing);
    });

    testWidgets('tapping outside the disks closes it where it was', (
      tester,
    ) async {
      await pumpShell(tester);
      await tester.longPress(find.byType(DiskBar));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(shell.index, PageSlot.home);
      expect(find.text('QUIZ'), findsNothing);
    });

    testWidgets('dims the page behind it with a blur', (tester) async {
      await pumpShell(tester);
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.longPress(find.byType(DiskBar));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);
    });
  });

  group('first-run tutorial', () {
    testWidgets('does not appear once it has been completed', (tester) async {
      await pumpShell(tester);
      expect(find.text('Meet your disks'), findsNothing);
    });

    testWidgets('appears on first run, over Home', (tester) async {
      await pumpShell(tester, onboardingDone: false);
      expect(find.text('Meet your disks'), findsOneWidget);
      expect(shell.index, PageSlot.home);
    });

    testWidgets('Skip closes it and it never starts by itself again', (
      tester,
    ) async {
      await pumpShell(tester, onboardingDone: false);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('Meet your disks'), findsNothing);
      expect(await const OnboardingStore().hasCompleted(), isTrue);
    });

    testWidgets('the intro does not let a swipe through to the disks', (
      tester,
    ) async {
      await pumpShell(tester, onboardingDone: false);
      await tester.drag(
        find.byType(DiskBar),
        const Offset(-100, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(shell.index, PageSlot.home);
      expect(find.text('Meet your disks'), findsOneWidget);
    });

    testWidgets('waits for a real swipe, and has no button to skip past it', (
      tester,
    ) async {
      await pumpShell(tester, onboardingDone: false);
      await tester.tap(find.text('Show me'));
      await tester.pumpAndSettle();
      expect(find.text('Swipe to explore your disks'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      expect(find.text('Skip'), findsOneWidget);

      // Tapping a disk changes the page but is not the swipe.
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is MiniDisk && w.icon == diskPages[PageSlot.practice].icon,
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Swipe to explore your disks'), findsOneWidget);
      expect(find.text('Nice swipe!'), findsNothing);

      // A drag too short to change the page is not it either.
      await tester.drag(find.byType(DiskBar), const Offset(-20, 0));
      await tester.pumpAndSettle();
      expect(find.text('Nice swipe!'), findsNothing);
    });

    testWidgets('walks through the swipe, the hold, the drawer and the tour', (
      tester,
    ) async {
      await pumpShell(tester, onboardingDone: false);
      await tester.tap(find.text('Show me'));
      await tester.pumpAndSettle();
      expect(find.text('Swipe to explore your disks'), findsOneWidget);

      // The swipe is done on the real disks, through the hole in the dimming.
      await swipeBar(tester, -100);
      expect(shell.index, PageSlot.practice);
      expect(find.text('Nice swipe!'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      expect(find.text('Press and hold for the disk drawer'), findsOneWidget);

      await tester.longPress(find.byType(DiskBar));
      await tester.pumpAndSettle();
      expect(find.text('Tap a disk to jump there'), findsOneWidget);

      await tester.tap(find.text('QUIZ'));
      await tester.pumpAndSettle();
      expect(find.text('Where things are'), findsOneWidget);
      expect(shell.index, PageSlot.home);
      expect(await const OnboardingStore().hasCompleted(), isFalse);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text('Where things are'), findsNothing);
      expect(await const OnboardingStore().hasCompleted(), isTrue);
    });

    testWidgets('Next moves past the hold without doing it', (tester) async {
      await pumpShell(tester, onboardingDone: false);
      await tester.tap(find.text('Show me'));
      await tester.pumpAndSettle();
      await swipeBar(tester, -100);
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpAndSettle();
      expect(find.text('Press and hold for the disk drawer'), findsOneWidget);

      // Skipping the hold shows what it would have opened.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Tap a disk to jump there'), findsOneWidget);
      expect(find.text('QUIZ'), findsOneWidget);
    });

    testWidgets('the dimmed area does not let touches through to the page', (
      tester,
    ) async {
      await pumpShell(tester, onboardingDone: false);
      shell.goTo(PageSlot.practice);
      await tester.pumpAndSettle();
      await tester.tap(find.text('practice:0'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('practice:0'), findsOneWidget); // not incremented
    });

    testWidgets('can be replayed from anywhere in the app', (tester) async {
      await pumpShell(tester);
      shell.goTo(PageSlot.settings);
      await tester.pumpAndSettle();
      shell.replayTutorial();
      await tester.pumpAndSettle();
      expect(find.text('Meet your disks'), findsOneWidget);
      expect(shell.index, PageSlot.home);
    });
  });
}
