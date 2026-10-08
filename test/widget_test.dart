import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debt_tracker/models/person.dart';
import 'package:debt_tracker/models/project.dart';
import 'package:debt_tracker/widgets/person_list_tile.dart';
import 'package:debt_tracker/widgets/project_tabs.dart';

final _holdDuration = kLongPressTimeout + const Duration(milliseconds: 100);

Person _person({int id = 1, bool pinned = false}) => Person(
      id: id,
      name: 'أحمد',
      isPinned: pinned ? 1 : 0,
      createdAt: '2026-01-01',
      updatedAt: '2026-01-01',
    );

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(home: Scaffold(body: child)),
    );

/// Holds [finder] for longer than [kLongPressTimeout] without moving, then
/// releases. [TestGesture] timestamps default to zero, so the release has to
/// carry an explicit timestamp for a hold to be measurable.
Future<void> _holdThenRelease(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(tester.getCenter(finder));
  await tester.pump(_holdDuration);
  await gesture.up(timeStamp: _holdDuration);
  await tester.pump();
}

void main() {
  group('PersonListTile long press', () {
    testWidgets('a plain tap opens Person Detail and never the menu',
        (tester) async {
      var taps = 0;
      var menus = 0;
      await tester.pumpWidget(_wrap(
        PersonListTile(
          person: _person(),
          balance: 100,
          onTap: () => taps++,
          onLongPress: (_) => menus++,
        ),
      ));

      await tester.tap(find.byType(PersonListTile));
      await tester.pump();

      expect(taps, 1);
      expect(menus, 0);
    });

    testWidgets('a hold with no movement opens the context menu, not the tile',
        (tester) async {
      var taps = 0;
      Offset? menuPosition;
      await tester.pumpWidget(_wrap(
        PersonListTile(
          person: _person(),
          balance: 100,
          onTap: () => taps++,
          onLongPress: (position) => menuPosition = position,
        ),
      ));

      final center = tester.getCenter(find.byType(PersonListTile));
      await _holdThenRelease(tester, find.byType(PersonListTile));

      expect(menuPosition, isNotNull);
      expect((menuPosition! - center).distance, lessThan(1));
      expect(taps, 0);
    });

    testWidgets('a hold followed by movement past 8px opens neither',
        (tester) async {
      var taps = 0;
      var menus = 0;
      await tester.pumpWidget(_wrap(
        PersonListTile(
          person: _person(),
          balance: 100,
          onTap: () => taps++,
          onLongPress: (_) => menus++,
        ),
      ));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PersonListTile)),
      );
      await tester.pump(_holdDuration);
      await gesture.moveBy(
        const Offset(0, 40),
        timeStamp: _holdDuration,
      );
      await gesture.up(timeStamp: _holdDuration + const Duration(milliseconds: 20));
      await tester.pump();

      expect(menus, 0);
      expect(taps, 0);
    });

    testWidgets(
        'the menu still opens when the tile is wrapped in '
        'ReorderableDelayedDragStartListener', (tester) async {
      var taps = 0;
      var menus = 0;
      await tester.pumpWidget(_wrap(
        SizedBox(
          height: 300,
          child: ReorderableListView.builder(
            // Mirrors home_screen: no default drag handles, only the pinned
            // tile gets a drag listener.
            buildDefaultDragHandles: false,
            itemCount: 1,
            onReorder: (_, __) {},
            itemBuilder: (context, index) => ReorderableDelayedDragStartListener(
              key: const ValueKey('person_1'),
              index: index,
              child: PersonListTile(
                person: _person(pinned: true),
                balance: 100,
                onTap: () => taps++,
                onLongPress: (_) => menus++,
              ),
            ),
          ),
        ),
      ));

      await _holdThenRelease(tester, find.byType(PersonListTile));

      expect(menus, 1);
      expect(taps, 0);
    });

    testWidgets(
        'inside a ReorderableListView a hold + drag is treated as a reorder, '
        'not as a menu', (tester) async {
      var taps = 0;
      var menus = 0;
      await tester.pumpWidget(_wrap(
        SizedBox(
          height: 300,
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: 2,
            onReorder: (_, __) {},
            itemBuilder: (context, index) => ReorderableDelayedDragStartListener(
              key: ValueKey('person_$index'),
              index: index,
              child: PersonListTile(
                person: _person(id: index + 1, pinned: true),
                balance: 100,
                onTap: () => taps++,
                onLongPress: (_) => menus++,
              ),
            ),
          ),
        ),
      ));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PersonListTile).first),
      );
      await tester.pump(_holdDuration);
      await gesture.moveBy(const Offset(0, 60), timeStamp: _holdDuration);
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up(
        timeStamp: _holdDuration + const Duration(milliseconds: 100),
      );
      await tester.pump();

      expect(menus, 0);
      expect(taps, 0);
    });
  });

  group('ProjectTabs long press', () {
    final projects = [
      Project(
        id: 7,
        personId: 1,
        name: 'الدراسة',
        createdAt: '2026-01-01',
        updatedAt: '2026-01-01',
      ),
    ];

    testWidgets('tapping a project chip selects it', (tester) async {
      int? selected;
      await tester.pumpWidget(_wrap(
        ProjectTabs(
          activeProjectId: null,
          projects: projects,
          onTabChanged: (id) => selected = id,
          onAddProject: () {},
        ),
      ));

      await tester.tap(find.text('الدراسة'));
      await tester.pump();

      expect(selected, 7);
    });

    testWidgets('long pressing a project chip opens its context menu',
        (tester) async {
      Project? pressed;
      Offset? position;
      var tabCalls = 0;
      await tester.pumpWidget(_wrap(
        ProjectTabs(
          activeProjectId: null,
          projects: projects,
          onTabChanged: (_) => tabCalls++,
          onAddProject: () {},
          onProjectLongPress: (project, pos) {
            pressed = project;
            position = pos;
          },
        ),
      ));

      final finder = find.text('الدراسة');
      final gesture = await tester.startGesture(tester.getCenter(finder));
      await tester.pump(_holdDuration);
      await gesture.up(timeStamp: _holdDuration);
      await tester.pump();

      expect(pressed, isNotNull);
      expect(pressed!.id, 7);
      expect(position, isNotNull);
      // The long press must not also select the tab.
      expect(tabCalls, 0);
    });

    testWidgets('the "الكل" tab never opens a context menu', (tester) async {
      var menus = 0;
      var tabCalls = 0;
      await tester.pumpWidget(_wrap(
        ProjectTabs(
          activeProjectId: null,
          projects: projects,
          onTabChanged: (_) => tabCalls++,
          onAddProject: () {},
          onProjectLongPress: (_, __) => menus++,
        ),
      ));

      final gesture = await tester.startGesture(tester.getCenter(find.text('الكل')));
      await tester.pump(_holdDuration);
      await gesture.up(timeStamp: _holdDuration);
      await tester.pump();

      expect(menus, 0);
      expect(tabCalls, 0);

      // The "الكل" tab still responds to a plain tap.
      await tester.tap(find.text('الكل'));
      await tester.pump();
      expect(tabCalls, 1);
    });
  });
}
