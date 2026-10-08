import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

import 'package:debt_tracker/db/db_helper.dart';
import 'package:debt_tracker/db/person_dao.dart';
import 'package:debt_tracker/db/transaction_dao.dart';
import 'package:debt_tracker/models/person.dart';
import 'package:debt_tracker/models/transaction.dart';
import 'package:debt_tracker/providers/persons_provider.dart';
import 'package:debt_tracker/screens/home_screen.dart';
import 'package:debt_tracker/screens/person_detail_screen.dart';
import 'package:debt_tracker/widgets/collapsing_summary_header.dart';
import 'package:debt_tracker/widgets/person_list_tile.dart';
import 'package:debt_tracker/widgets/project_tabs.dart';
import 'package:debt_tracker/widgets/transaction_tile.dart';

/// Everything that scrolls on the two main screens is driven by one position,
/// so these tests drive that position directly instead of flinging: a fling
/// would settle wherever the physics liked and would make the thresholds
/// impossible to reason about.
///
/// The database is real (sqflite over ffi), which does real asynchronous work
/// and therefore cannot finish inside the fake clock `testWidgets` runs on —
/// every first build goes through [pumpApp], which opens a real-async window
/// until the screen has its data.
void main() {
  Directory? tempDir;
  int? personId;

  String dbPath() => p.join(tempDir!.path, 'debt_tracker.db');

  setUpAll(() => initializeDateFormatting('ar_EG'));

  setUp(() async {
    await DatabaseHelper.instance.close();
    if (tempDir != null && tempDir!.existsSync()) {
      tempDir!.deleteSync(recursive: true);
    }
    tempDir = Directory.systemTemp.createTempSync('debt_tracker_sliver');
    DatabaseHelper.databasePathOverride = dbPath();
    // HomeScreen kicks off an auto backup on open; the daily mode is off by
    // default, which is all it needs to return immediately.
    SharedPreferences.setMockInitialValues({});

    personId = await PersonDao().insertPerson(
      Person(name: 'سارة', isPinned: 1, pinOrder: 0, createdAt: '', updatedAt: ''),
    );
    // Enough unpinned rows that the home list is genuinely scrollable: a
    // header can only collapse if there is content to scroll past it.
    for (var i = 1; i <= 8; i++) {
      await PersonDao().insertPerson(
        Person(name: 'شخص$i', createdAt: '', updatedAt: ''),
      );
    }
    for (var i = 0; i < 20; i++) {
      await TransactionDao().insertTransaction(
        Transaction(
          personId: personId!,
          amount: 100.0 + i,
          type: i.isEven ? TransactionType.theyOweMe : TransactionType.iOweThem,
          date: '2026-01-${(i % 28) + 1}T10:00:00.000',
          createdAt: '2026-01-01T10:00:00.000',
        ),
      );
    }
  });

  tearDown(() async {
    await DatabaseHelper.instance.close();
    DatabaseHelper.databasePathOverride = null;
    if (tempDir != null && tempDir!.existsSync()) {
      tempDir!.deleteSync(recursive: true);
    }
    tempDir = null;
  });

  Widget app(Widget home) => ProviderScope(child: MaterialApp(home: home));

  ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );

  /// Pumps [home] inside a real-async window and waits until [until] is on
  /// screen, so every provider query started by the first build has finished
  /// before the fake clock takes over again.
  Future<void> pumpApp(WidgetTester tester, Widget home, Finder until) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(app(home));
      for (var i = 0; i < 60; i++) {
        if (until.evaluate().isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
      // Let the totals queries, which started alongside the marker, land too.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    });
    await tester.pumpAndSettle();
  }

  /// Lets work that was started by a gesture finish on the real event loop.
  ///
  /// Finishing a write invalidates the providers, which re-arms their queries
  /// on the following rebuild - so one window is never enough: the window is
  /// retried until nothing on screen is still waiting for the database.
  Future<void> flushReal(WidgetTester tester) async {
    var cycles = 0;
    while (true) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 700)),
      );
      // A duration, not a bare pump: the database layer yields with timers,
      // and timers only fire when the fake clock moves.
      await tester.pump(const Duration(milliseconds: 250));
      cycles++;
      final waiting =
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
      if (!waiting && cycles >= 4) break;
      if (cycles >= 10) break;
    }
    // Close on a real window with no trailing pump: whatever the last rebuild
    // started has to be allowed to land, and the caller's next pump() applies
    // it without kicking off anything new.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 700)),
    );
  }

  /// Waits until [isReady] is true.
  ///
  /// A write re-arms the providers, and those queries only make progress on
  /// the real event loop while their continuations land in the test's fake
  /// clock - so the two have to be interleaved until the read is through.
  /// Anything left waiting for the database once the tree is torn down fails
  /// the test on a pending timer, so "done" has to be observed, not guessed.
  Future<void> waitFor(WidgetTester tester, bool Function() isReady) async {
    for (var i = 0; i < 60 && !isReady(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The header's own render object is a sliver, so the thing whose height
  /// we care about is its clipped child box.
  Finder headerBox() => find.descendant(
        of: find.byType(SliverPersistentHeader),
        matching: find.byType(ClipRect),
      );

  /// The scroll position behind the screen under test. The scroll view owns
  /// the first [Scrollable] in its own subtree; the filter tabs add their own
  /// horizontal scrollers further down.
  ScrollPosition positionOf(WidgetTester tester) {
    final finder = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    );
    return tester.state<ScrollableState>(finder.first).position;
  }

  group('home summary header', () {
    testWidgets('is one pinned sliver that collapses into the strip',
        (tester) async {
      await pumpApp(tester, const HomeScreen(), find.text('سارة'));

      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(SliverPersistentHeader), findsOneWidget);
      expect(headerBox(), findsOneWidget);

      final expanded = tester.getSize(headerBox()).height;
      expect(expanded, greaterThan(150), reason: 'the full card should show');

      // A pinned header never scrolls away: a big drag only shrinks it.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
      await tester.pumpAndSettle();

      final collapsed = tester.getSize(headerBox()).height;
      expect(collapsed, greaterThan(0), reason: 'still pinned on screen');
      expect(collapsed, lessThan(expanded));
      expect(collapsed, closeTo(kSummaryStripInitialExtent, 12));

      // The numbers moved into the strip, the bar kept only the title.
      expect(find.byType(SummaryStrip), findsOneWidget);
      expect(find.text('دفتر الديون'), findsOneWidget);

      // Rows that scrolled into view started their own totals queries; let
      // them finish so no database timer is left behind.
      await flushReal(tester);
      await tester.pumpAndSettle();
    });

    testWidgets('the section title and rows sit below it, not inside it',
        (tester) async {
      await pumpApp(tester, const HomeScreen(), find.text('سارة'));

      final headerBottom = tester.getBottomLeft(headerBox()).dy;
      final titleTop = tester.getTopLeft(find.text('الأشخاص')).dy;
      expect(titleTop, greaterThanOrEqualTo(headerBottom - 1));
      expect(find.byType(PersonListTile), findsWidgets);

      await flushReal(tester);
      await tester.pumpAndSettle();
    });
  });

  group('person detail filter tabs', () {
    testWidgets('start open and retire on the way down', (tester) async {
      await pumpApp(
        tester,
        PersonDetailScreen(personId: personId!),
        find.byType(TransactionTile),
      );

      expect(find.byType(ProjectTabs), findsOneWidget);
      // A collapsed (zero height) box is treated as offstage by the finder,
      // which is exactly the state we want to measure.
      final collapseBox = find.byKey(
        const ValueKey('filter_tabs_collapse'),
        skipOffstage: false,
      );
      expect(collapseBox, findsOneWidget);

      final open = tester.getSize(collapseBox).height;
      expect(open, greaterThan(50), reason: 'filters start open');

      positionOf(tester).jumpTo(500);
      await tester.pumpAndSettle();
      expect(tester.getSize(collapseBox).height, lessThan(1),
          reason: 'downward scrolling hides them');
    });

    testWidgets('stay hidden until four rows of upward scrolling',
        (tester) async {
      await pumpApp(
        tester,
        PersonDetailScreen(personId: personId!),
        find.byType(TransactionTile),
      );

      // A collapsed (zero height) box is treated as offstage by the finder,
      // which is exactly the state we want to measure.
      final collapseBox = find.byKey(
        const ValueKey('filter_tabs_collapse'),
        skipOffstage: false,
      );
      final position = positionOf(tester);

      position.jumpTo(500);
      await tester.pumpAndSettle();
      expect(tester.getSize(collapseBox).height, lessThan(1));

      // A short flick back is not enough: the accumulator is still short of
      // four rows and we are well clear of the top of the list.
      position.jumpTo(400);
      await tester.pumpAndSettle();
      expect(tester.getSize(collapseBox).height, lessThan(1));
      expect(position.pixels, greaterThan(1));

      // Four rows (or more) of upward travel brings them back.
      position.jumpTo(50);
      await tester.pumpAndSettle();
      expect(tester.getSize(collapseBox).height, greaterThan(50));
      expect(position.pixels, greaterThan(1),
          reason: 'this came back on the accumulator, not the top threshold');
    });

    testWidgets('come back by themselves at the top of the list',
        (tester) async {
      await pumpApp(
        tester,
        PersonDetailScreen(personId: personId!),
        find.byType(TransactionTile),
      );

      // A collapsed (zero height) box is treated as offstage by the finder,
      // which is exactly the state we want to measure.
      final collapseBox = find.byKey(
        const ValueKey('filter_tabs_collapse'),
        skipOffstage: false,
      );

      positionOf(tester).jumpTo(400);
      await tester.pumpAndSettle();
      expect(tester.getSize(collapseBox).height, lessThan(1));

      positionOf(tester).jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.getSize(collapseBox).height, greaterThan(50));
    });

    testWidgets('the project tabs never move', (tester) async {
      await pumpApp(
        tester,
        PersonDetailScreen(personId: personId!),
        find.byType(TransactionTile),
      );

      final before = tester.getTopLeft(find.byType(ProjectTabs));

      positionOf(tester).jumpTo(500);
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.byType(ProjectTabs)), before);
    });
  });

  group('pinned persons reorder', () {
    testWidgets('a hold + drag inside the sliver list rewrites pin_order',
        (tester) async {
      // The test body runs on the fake clock, so the write needs its own
      // real-async window.
      final second = await tester.runAsync(
        () => PersonDao().insertPerson(
          Person(name: 'خالد', isPinned: 1, pinOrder: 1, createdAt: '', updatedAt: ''),
        ),
      );

      await pumpApp(tester, const HomeScreen(), find.text('خالد'));

      final pinned = () => containerOf(tester)
          .read(personsProvider)
          .persons
          .where((person) => person.isPinnedBool)
          .toList();
      expect(pinned().map((person) => person.name), ['سارة', 'خالد']);

      final firstTile = find.byType(PersonListTile).first;
      final hold = kLongPressTimeout + const Duration(milliseconds: 100);
      final gesture = await tester.startGesture(tester.getCenter(firstTile));
      await tester.pump(hold);
      await gesture.moveBy(const Offset(0, 150), timeStamp: hold);
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up(
        timeStamp: hold + const Duration(milliseconds: 100),
      );
      await tester.pumpAndSettle();

      // The drop writes to the database, which needs a real-async window.
      await flushReal(tester);
      await tester.pumpAndSettle();

      expect(pinned().map((person) => person.name), ['خالد', 'سارة'],
          reason: 'the dragged row should have moved down');
      expect(pinned().first.id, second);

      // Reordering bumps the data version, which arms the debounced backup
      // timer; let it fire so the test does not end with a timer pending.
      await tester.pump(const Duration(seconds: 31));
      await flushReal(tester);

      // ...and wait for the settled-total read the data bump re-armed.
      await waitFor(
        tester,
        () => !containerOf(tester).read(overallSettledTotalProvider).isLoading,
      );
      expect(
        containerOf(tester).read(overallSettledTotalProvider).isLoading,
        isFalse,
        reason: 'the re-armed read must land before the test ends',
      );
      await tester.pumpAndSettle();
    });
  });
}
