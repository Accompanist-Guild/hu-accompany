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
          pageBuilder: (slot, tab) => switch ((slot, tab)) {
            (PageSlot.practiceRoom, PracticeTab.practice) => const _Counter(
              name: 'practice',
            ),
            (PageSlot.practiceRoom, PracticeTab.shelf) => const _Counter(
              name: 'shelf',
            ),
            _ => Builder(
              builder: (context) {
                lastPageBottomInset = MediaQuery.paddingOf(context).bottom;
                final page = sectionTabs[slot]?[tab] ?? pageFor(slot);
                return Scaffold(
                  body: Center(child: Text('page:${page.title}')),
                );
              },
            ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('bottom disk bar', () {
    testWidgets('opens on Home with its disk marked', (tester) async {
      await pumpShell(tester);
      expect(shell.index, PageSlot.home);
      expect(find.text('page:Home'), findsOneWidget);
      final active = tester
          .widgetList<MiniDisk>(find.byType(MiniDisk))
          .where((disk) => disk.active);
      expect(active.single.icon, diskPages[PageSlot.home].icon);
    });

    testWidgets('shows every disk, one marked', (tester) async {
      await pumpShell(tester);
      final disks = tester.widgetList<MiniDisk>(
        find.descendant(
          of: find.byType(DiskBar),
          matching: find.byType(MiniDisk),
        ),
      );
      expect(disks.map((d) => d.icon), [for (final p in diskPages) p.icon]);
      expect(disks.where((d) => d.active).length, 1);
    });

    testWidgets('the disks sit in a row, evenly spaced and centred', (
      tester,
    ) async {
      await pumpShell(tester);
      final centers = [
        for (final page in diskPages)
          tester.getCenter(
            find.descendant(
              of: find.byType(DiskBar),
              matching: find.byWidgetPredicate(
                (w) => w is MiniDisk && w.icon == page.icon,
              ),
            ),
          ),
      ];
      final step = centers[1].dx - centers[0].dx;
      for (var i = 1; i < centers.length; i++) {
        expect(centers[i].dy, closeTo(centers[0].dy, 0.5));
        expect(centers[i].dx - centers[i - 1].dx, closeTo(step, 0.5));
      }
      final middle = (centers.first.dx + centers.last.dx) / 2;
      expect(middle, closeTo(200, 0.5)); // middle of a 400-wide screen
      expect(centers.first.dx, greaterThan(0));
      expect(centers.last.dx, lessThan(400));
    });

    testWidgets('fits every disk on a narrow phone', (tester) async {
      await pumpShell(tester);
      tester.view.physicalSize = const Size(320, 568);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final page in diskPages) {
        final rect = tester.getRect(
          find.descendant(
            of: find.byType(DiskBar),
            matching: find.byWidgetPredicate(
              (w) => w is MiniDisk && w.icon == page.icon,
            ),
          ),
        );
        expect(rect.left, greaterThanOrEqualTo(0), reason: page.title);
        expect(rect.right, lessThanOrEqualTo(320), reason: page.title);
      }
    });

    testWidgets('has no disk for User Account, and marks none while it shows', (
      tester,
    ) async {
      await pumpShell(tester);
      shell.goTo(PageSlot.account);
      await tester.pumpAndSettle();
      expect(find.text('page:User Account'), findsOneWidget);
      final disks = tester.widgetList<MiniDisk>(
        find.descendant(
          of: find.byType(DiskBar),
          matching: find.byType(MiniDisk),
        ),
      );
      expect(disks.any((d) => d.icon == accountPage.icon), isFalse);
      expect(disks.where((d) => d.active), isEmpty);
    });

    testWidgets('dragging along the row does not change page', (tester) async {
      await pumpShell(tester);
      await tester.drag(find.byType(DiskBar), const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(shell.index, PageSlot.home);
    });

    testWidgets('tapping any disk goes to its page', (tester) async {
      await pumpShell(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(DiskBar),
          matching: find.byWidgetPredicate(
            (w) =>
                w is MiniDisk && w.icon == diskPages[PageSlot.minigames].icon,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(shell.index, PageSlot.minigames);
      expect(find.text('page:Hum'), findsOneWidget);
    });

    testWidgets('tapping the next disk goes to its page', (tester) async {
      await pumpShell(tester);
      final practiceDisk = find.byWidgetPredicate(
        (w) => w is MiniDisk && w.icon == diskPages[PageSlot.practiceRoom].icon,
      );
      await tester.tap(practiceDisk);
      await tester.pumpAndSettle();
      expect(shell.index, PageSlot.practiceRoom);
      expect(find.text('practice:0'), findsOneWidget);
    });

    testWidgets('pages are given the bar as part of their bottom inset', (
      tester,
    ) async {
      await pumpShell(tester);
      shell.goTo(PageSlot.learning, tab: LearningTab.quiz);
      await tester.pumpAndSettle();
      expect(lastPageBottomInset, tester.getSize(find.byType(DiskBar)).height);
    });

    testWidgets('Practice is kept while another page is shown', (tester) async {
      await pumpShell(tester);
      shell.goTo(PageSlot.practiceRoom);
      await tester.pumpAndSettle();
      await tester.tap(find.text('practice:0'));
      await tester.pump();
      expect(find.text('practice:1'), findsOneWidget);

      shell.goTo(PageSlot.practiceRoom, tab: PracticeTab.shelf);
      await tester.pumpAndSettle();
      expect(find.text('practice:1', skipOffstage: false), findsOneWidget);
      expect(find.text('practice:1'), findsNothing); // hidden
      await tester.tap(find.text('shelf:0'));
      await tester.pump();
      expect(find.text('shelf:1'), findsOneWidget);

      shell.goTo(PageSlot.practiceRoom, tab: PracticeTab.practice);
      await tester.pumpAndSettle();
      expect(find.text('practice:1'), findsOneWidget);

      // And while another section is shown.
      shell.goTo(PageSlot.account);
      await tester.pumpAndSettle();
      expect(find.text('practice:1', skipOffstage: false), findsOneWidget);
      shell.goTo(PageSlot.practiceRoom);
      await tester.pumpAndSettle();
      expect(find.text('practice:1'), findsOneWidget);

      // Other pages start afresh each visit.
      shell.goTo(PageSlot.practiceRoom, tab: PracticeTab.shelf);
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
      expect(find.text('MINIGAMES'), findsNothing);

      await tester.longPress(find.byType(DiskBar));
      await tester.pumpAndSettle();

      expect(haptics, contains('HapticFeedbackType.mediumImpact'));
      for (final page in diskPages) {
        expect(find.text(page.title.toUpperCase()), findsWidgets);
      }
      expect(find.text('MINIGAMES'), findsOneWidget);
      // User Account is opened from the person's icon on Home only.
      expect(find.text('USER ACCOUNT'), findsNothing);
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

      await tester.tap(find.text('MINIGAMES'));
      await tester.pumpAndSettle();

      expect(shell.index, PageSlot.minigames);
      expect(find.text('page:Hum'), findsOneWidget);
      expect(find.text('LEARNING AREA'), findsNothing);
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
      expect(find.text('MINIGAMES'), findsNothing);
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

    testWidgets('the intro does not let a tap through to the disks', (
      tester,
    ) async {
      await pumpShell(tester, onboardingDone: false);
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is MiniDisk && w.icon == diskPages[PageSlot.practiceRoom].icon,
        ),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(shell.index, PageSlot.home);
      expect(find.text('Meet your disks'), findsOneWidget);
    });

    testWidgets('walks through the hold, the drawer and the tour', (
      tester,
    ) async {
      await pumpShell(tester, onboardingDone: false);
      await tester.tap(find.text('Show me'));
      await tester.pumpAndSettle();
      expect(find.text('Press and hold for the disk drawer'), findsOneWidget);

      // The hold is done on the real disks, through the hole in the dimming.
      await tester.longPress(find.byType(DiskBar));
      await tester.pumpAndSettle();
      expect(find.text('Tap a disk to jump there'), findsOneWidget);

      await tester.tap(find.text('MINIGAMES'));
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
      expect(find.text('Press and hold for the disk drawer'), findsOneWidget);

      // Skipping the hold shows what it would have opened.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Tap a disk to jump there'), findsOneWidget);
      expect(find.text('MINIGAMES'), findsOneWidget);
    });

    testWidgets('the dimmed area does not let touches through to the page', (
      tester,
    ) async {
      await pumpShell(tester, onboardingDone: false);
      shell.goTo(PageSlot.practiceRoom);
      await tester.pumpAndSettle();
      await tester.tap(find.text('practice:0'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('practice:0'), findsOneWidget); // not incremented
    });

    testWidgets('can be replayed from anywhere in the app', (tester) async {
      await pumpShell(tester);
      shell.goTo(PageSlot.account);
      await tester.pumpAndSettle();
      shell.replayTutorial();
      await tester.pumpAndSettle();
      expect(find.text('Meet your disks'), findsOneWidget);
      expect(shell.index, PageSlot.home);
    });
  });
}
