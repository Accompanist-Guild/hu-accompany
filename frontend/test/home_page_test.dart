import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hu_accomponist/features/home/home_page.dart';
import 'package:hu_accomponist/features/shell/disk_pages.dart';
import 'package:hu_accomponist/features/shell/shell_controller.dart';
import 'package:hu_accomponist/features/shelf/Shelf_Manager.dart';

ShelfEntry entry(String id, String title, String composer, DateTime at) =>
    ShelfEntry(id: id, title: title, composer: composer, playedAt: at);

void main() {
  final now = DateTime(2026, 10, 14, 15, 40);
  late ShellController shell;
  late List<ShelfEntry> opened;

  setUp(() {
    shell = ShellController();
    opened = [];
  });

  tearDown(() => shell.dispose());

  Future<void> pumpHome(
    WidgetTester tester, {
    required Future<List<ShelfEntry>> Function() recent,
    Size size = const Size(400, 900),
    DateTime? at,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: ShellScope(controller: shell, child: child!),
        ),
        home: HomePage(
          userName: 'Ada',
          loadRecent: recent,
          openEntry: (context, e) async => opened.add(e),
          now: () => at ?? now,
        ),
      ),
    );
  }

  final recent = [
    entry('1', 'Prelude in C', 'J. S. Bach', DateTime(2026, 10, 14, 9, 5)),
    entry('2', 'Gymnopédie No. 1', 'Erik Satie', DateTime(2026, 10, 13, 20, 0)),
    entry('3', 'Clair de Lune', 'Claude Debussy', DateTime(2026, 10, 9, 8, 0)),
    entry('4', 'Fur Elise', 'Beethoven', DateTime(2026, 9, 1, 8, 0)),
  ];

  testWidgets('greets the person by the time of day', (tester) async {
    await pumpHome(tester, recent: () async => []);
    await tester.pump();
    expect(find.text('Good afternoon, Ada'), findsOneWidget);

    await pumpHome(
      tester,
      recent: () async => [],
      at: DateTime(2026, 10, 14, 8),
    );
    await tester.pump();
    expect(find.text('Good morning, Ada'), findsOneWidget);
  });

  testWidgets('shows a placeholder while the recent scores load', (
    tester,
  ) async {
    final pending = Completer<List<ShelfEntry>>();
    await pumpHome(tester, recent: () => pending.future);
    expect(find.byKey(const Key('home-recent-loading')), findsOneWidget);
    pending.complete(recent);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('home-recent-loading')), findsNothing);
  });

  testWidgets('offers to continue the most recent score', (tester) async {
    await pumpHome(tester, recent: () async => recent);
    await tester.pump();
    await tester.pump();

    expect(find.text('Prelude in C'), findsOneWidget);
    expect(find.text('J. S. Bach'), findsOneWidget);
    expect(find.text('Last played · Today, 9:05 AM'), findsOneWidget);

    await tester.tap(find.text('Continue Practicing'));
    await tester.pump();
    expect(opened.single.id, '1');
  });

  testWidgets('lists the two before it, and opens them too', (tester) async {
    await pumpHome(tester, recent: () async => recent);
    await tester.pump();
    await tester.pump();

    expect(find.text('Gymnopédie No. 1'), findsOneWidget);
    expect(find.text('Erik Satie · Yesterday'), findsOneWidget);
    expect(find.text('Clair de Lune'), findsOneWidget);
    expect(find.text('Fur Elise'), findsNothing); // only two earlier ones

    await tester.tap(find.text('Gymnopédie No. 1'));
    await tester.pump();
    expect(opened.single.id, '2');
  });

  testWidgets('with nothing played, says so and points the way', (
    tester,
  ) async {
    await pumpHome(tester, recent: () async => []);
    await tester.pump();
    await tester.pump();

    expect(find.text('Nothing played yet'), findsOneWidget);
    expect(find.text('Continue Practicing'), findsNothing);

    await tester.tap(find.text('Find a score'));
    expect(shell.index, PageSlot.search);
    await tester.tap(find.text('Try an exercise'));
    expect(shell.index, PageSlot.practice);
  });

  testWidgets('a store that cannot be read looks like an empty one', (
    tester,
  ) async {
    await pumpHome(tester, recent: () async => throw Exception('disk full'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Nothing played yet'), findsOneWidget);
  });

  testWidgets('has a card for every other page, each going there', (
    tester,
  ) async {
    await pumpHome(tester, recent: () async => recent);
    await tester.pump();
    await tester.pump();

    for (var slot = PageSlot.practice; slot < diskPages.length; slot++) {
      expect(
        find.text(diskPages[slot].caption, skipOffstage: false),
        findsOneWidget,
        reason: diskPages[slot].title,
      );
    }
    final hum = find.text(diskPages[PageSlot.hum].caption);
    await tester.ensureVisible(hum);
    await tester.pumpAndSettle();
    await tester.tap(hum);
    expect(shell.index, PageSlot.hum);
  });

  for (final size in const [Size(320, 568), Size(400, 900), Size(1024, 768)]) {
    testWidgets('fits a ${size.width.toInt()} wide screen', (tester) async {
      await pumpHome(tester, recent: () async => recent, size: size);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Continue Practicing'), findsOneWidget);
    });
  }

  test('says when a score was last played', () {
    String label(DateTime d) => lastPlayedLabel(d, now);
    expect(label(DateTime(2026, 10, 14, 0, 7)), 'Today, 12:07 AM');
    expect(label(DateTime(2026, 10, 14, 12, 30)), 'Today, 12:30 PM');
    expect(label(DateTime(2026, 10, 14, 23, 59)), 'Today, 11:59 PM');
    expect(label(DateTime(2026, 10, 13, 23, 59)), 'Yesterday');
    expect(label(DateTime(2026, 10, 10)), 'Saturday');
    expect(label(DateTime(2026, 10, 7)), 'Oct 7');
    expect(label(DateTime(2025, 12, 31)), 'Dec 31');
  });
}
