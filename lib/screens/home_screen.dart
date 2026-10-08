import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../models/person.dart';
import '../../widgets/balance_card.dart';
import '../../widgets/search_bar_widget.dart';
import '../../widgets/person_list_tile.dart';
import '../../widgets/person_context_menu.dart';
import '../../widgets/collapsing_summary_header.dart';
import '../../providers/persons_provider.dart';
import '../../services/drive_backup_service.dart';
import 'add_person_screen.dart';
import 'edit_person_screen.dart';
import 'person_detail_screen.dart';
import 'settings_screen.dart';
import 'archive_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const double _menuWidth = 280;
  static const double _menuHeight = 250;
  static const double _menuMargin = 8;

  final _searchController = TextEditingController();
  final GlobalKey _bodyStackKey = GlobalKey();
  String _searchQuery = '';
  Person? _contextMenuPerson;
  Offset _contextMenuPosition = Offset.zero;

  /// Measures of the pinned summary header's two states. Both are filled in
  /// right after the first frame so the card never gets a made-up height.
  final GlobalKey _summaryCardKey = GlobalKey();
  final GlobalKey _summaryStripKey = GlobalKey();
  double _summaryMaxExtent = kSummaryCardInitialExtent;
  double _summaryMinExtent = kSummaryStripInitialExtent;
  bool _extentMeasureScheduled = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
    // Daily backup mode: upload once on app open if 24h have passed.
    Future.microtask(() => DriveBackupService.instance.checkAndRunAutoBackup());
  }

  /// Re-measures the card and the strip whenever they may have changed size
  /// (first frame, new person settled, currency width, text scale). Runs once
  /// per frame at most and only rebuilds when a size really moved, so it can
  /// never feed back into itself.
  void _scheduleExtentMeasure() {
    if (_extentMeasureScheduled) return;
    _extentMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _extentMeasureScheduled = false;
      if (!mounted) return;
      final card = measureExtent(_summaryCardKey);
      final strip = measureExtent(_summaryStripKey);
      var changed = false;
      if (card != null && (card - _summaryMaxExtent).abs() > 1) {
        _summaryMaxExtent = card;
        changed = true;
      }
      if (strip != null && (strip - _summaryMinExtent).abs() > 1) {
        _summaryMinExtent = strip;
        changed = true;
      }
      if (_summaryMinExtent > _summaryMaxExtent) {
        _summaryMinExtent = _summaryMaxExtent;
        changed = true;
      }
      if (changed) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final personsAsync = ref.watch(personsProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        // The amounts live in the pinned summary strip now, so the bar keeps
        // nothing but the screen title.
        title: Text('دفتر المعاملات', style: AppTextStyles.headlineSmall),
        actions: [
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ArchiveScreen()),
            ),
            tooltip: 'الأرشيف',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            tooltip: 'الإعدادات',
          ),
        ],
      ),
      body: Stack(
        key: _bodyStackKey,
        children: [
          Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: SearchBarWidget(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),

              // Summary card + section title + persons list are all slivers of
              // ONE scroll view, so the pinned card and every row are driven by
              // the same position and can never drift apart.
              Expanded(
                child: personsAsync.isLoading
                    ? _homeScroll(const [
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ])
                    : personsAsync.error != null
                    ? _homeScroll([
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text('خطأ: ${personsAsync.error}'),
                          ),
                        ),
                      ])
                    : _buildPersonsList(personsAsync.persons),
              ),
            ],
          ),

          // Context Menu Overlay
          if (_contextMenuPerson != null) ..._buildContextMenuOverlay(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddPerson,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBalanceCard() {
    final totalsAsync = ref.watch(overallTotalsProvider);
    final settledTotal =
        ref.watch(overallSettledTotalProvider).valueOrNull ?? 0.0;
    return totalsAsync.when(
      data: (data) {
        final theyOweMe = data['they_owe_me'] ?? 0.0;
        final iOweThem = data['i_owe_them'] ?? 0.0;
        return BalanceCard(
          theyOweMe: theyOweMe,
          iOweThem: iOweThem,
          settledTotal: settledTotal,
        );
      },
      loading: () => BalanceCard(theyOweMe: 0, iOweThem: 0),
      error: (_, __) => BalanceCard(theyOweMe: 0, iOweThem: 0),
      skipLoadingOnReload: true,
    );
  }

  /// Everything that scrolls on the home screen lives in this one
  /// [CustomScrollView]: the pinned summary header first, then whatever the
  /// current state needs below it.
  Widget _homeScroll(List<Widget> slivers) {
    _scheduleExtentMeasure();
    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(pinned: true, delegate: _summaryHeader()),
        ...slivers,
      ],
    );
  }

  CollapsingSummaryHeader _summaryHeader() {
    final totals = ref.watch(overallTotalsProvider).valueOrNull;
    return CollapsingSummaryHeader(
      card: _buildBalanceCard(),
      strip: SummaryStrip(
        theyOweMe: totals?['they_owe_me'] ?? 0.0,
        iOweThem: totals?['i_owe_them'] ?? 0.0,
      ),
      cardKey: _summaryCardKey,
      stripKey: _summaryStripKey,
      maxHeight: _summaryMaxExtent,
      minHeight: _summaryMinExtent,
    );
  }

  Widget _sectionTitleSliver() {
    return const SliverToBoxAdapter(
      key: ValueKey('persons_section_title'),
      child: Padding(
        padding: EdgeInsets.only(top: 16, bottom: 8),
        child: _SectionTitle(),
      ),
    );
  }

  Widget _buildPersonsList(List<Person> persons) {
    final filtered = _searchQuery.isEmpty
        ? persons
        : persons.where((p) => p.name.contains(_searchQuery)).toList();

    if (filtered.isEmpty) {
      return _homeScroll([
        _sectionTitleSliver(),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.people_outline,
                  size: 80,
                  color: AppColors.gray.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  _searchQuery.isEmpty
                      ? 'لا يوجد أشخاص بعد'
                      : 'لا توجد نتائج للبحث',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.gray,
                  ),
                ),
                if (_searchQuery.isEmpty) ...[
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _navigateToAddPerson,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة شخص جديد'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ]);
    }

    // Separate pinned and non-pinned persons
    final pinnedPersons = filtered.where((p) => p.isPinnedBool).toList();
    final nonPinnedPersons = filtered.where((p) => !p.isPinnedBool).toList();
    final hasDivider = pinnedPersons.isNotEmpty && nonPinnedPersons.isNotEmpty;

    // Reordering is only safe on the full list: during a search `pinnedPersons`
    // is a subset, so rewriting pin_order from it would scramble the real order.
    final canReorder = _searchQuery.isEmpty && pinnedPersons.isNotEmpty;

    final items = <_ListItem>[
      for (final person in pinnedPersons)
        _ListItem.person(person, pinned: true),
      if (hasDivider) _ListItem.divider(),
      for (final person in nonPinnedPersons)
        _ListItem.person(person, pinned: false),
    ];

    // SliverReorderableList installs no drag handles of its own, so the list
    // itself never owns a long-press recognizer: only the pinned tiles get one
    // (spec 5.1). The summary header sits above as a separate sliver, so the
    // reorder indices are exactly the row indices and never include it.
    return _homeScroll([
      _sectionTitleSliver(),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          0,
          8,
          0,
          80 + MediaQuery.of(context).padding.bottom,
        ),
        sliver: SliverReorderableList(
          itemCount: items.length,
          onReorderItem: (oldIndex, newIndex) =>
              _reorderPinned(oldIndex, newIndex, pinnedPersons),
          // The lifted row is painted into the overlay, above the Scaffold, so
          // it must bring its own Material: ListTile (and its ink) require one.
          proxyDecorator: (child, index, animation) => Material(
            type: MaterialType.transparency,
            elevation: 6,
            child: child,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            if (item.isDivider) {
              return const KeyedSubtree(
                key: ValueKey('pinned_divider'),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Divider(thickness: 2),
                ),
              );
            }

            final person = item.person!;
            final tile = _buildPersonTile(person);

            return ReorderableDelayedDragStartListener(
              key: ValueKey('person_${person.id}'),
              enabled: item.pinned && canReorder,
              index: index,
              child: tile,
            );
          },
        ),
      ),
    ]);
  }

  void _reorderPinned(int oldIndex, int newIndex, List<Person> pinnedPersons) {
    final pinnedCount = pinnedPersons.length;
    if (pinnedCount == 0 || _searchQuery.isNotEmpty) return;
    if (oldIndex < 0 || oldIndex >= pinnedCount) return;

    // `onReorderItem` already reports the index the row lands at once the
    // source has been removed, so there is nothing to adjust here.
    final target = newIndex.clamp(0, pinnedCount - 1);
    if (target == oldIndex) return;

    final reordered = [...pinnedPersons];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(target, moved);

    final updates = [
      for (var i = 0; i < reordered.length; i++)
        {'id': reordered[i].id, 'pin_order': i},
    ];
    ref.read(personsProvider.notifier).updatePinOrders(updates);
  }

  Widget _buildPersonTile(Person person) {
    final totalsAsync = ref.watch(personTotalsProvider(person.id!));
    return totalsAsync.when(
      data: (data) {
        final balance =
            (data['they_owe_me'] ?? 0.0) - (data['i_owe_them'] ?? 0.0);
        return PersonListTile(
          person: person,
          balance: balance,
          onTap: () => _navigateToPersonDetail(person),
          onLongPress: (position) => _showContextMenu(person, position),
        );
      },
      loading: () => PersonListTile(
        person: person,
        balance: 0,
        onTap: () => _navigateToPersonDetail(person),
        onLongPress: (position) => _showContextMenu(person, position),
      ),
      error: (_, __) => PersonListTile(
        person: person,
        balance: 0,
        onTap: () => _navigateToPersonDetail(person),
        onLongPress: (position) => _showContextMenu(person, position),
      ),
      skipLoadingOnReload: true,
    );
  }

  /// Builds the scrim + the menu itself, anchored to the release point and
  /// clamped so it can never be laid out off-screen (which is what made long
  /// press look like "nothing happened": the menu used to be positioned at a
  /// hard-coded `Offset.zero`, i.e. entirely outside the stack).
  List<Widget> _buildContextMenuOverlay() {
    final person = _contextMenuPerson!;
    return [
      // Light scrim: tapping outside closes the menu (spec 5.2).
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _hideContextMenu,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            builder: (context, t, _) =>
                Container(color: Colors.black.withValues(alpha: 0.15 * t)),
          ),
        ),
      ),
      Positioned(
        left: _contextMenuPosition.dx,
        top: _contextMenuPosition.dy,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            // Scales from the corner nearest the row that was held.
            child: Transform.scale(
              scale: 0.92 + 0.08 * t,
              alignment: Alignment.topRight,
              child: child,
            ),
          ),
          child: PersonContextMenu(
            person: person,
            isPinned: person.isPinnedBool,
            onPinToggle: () {
              _hideContextMenu();
              ref
                  .read(personsProvider.notifier)
                  .togglePin(person.id!, !person.isPinnedBool);
            },
            onEdit: () {
              _hideContextMenu();
              _navigateToEditPerson(person);
            },
            onArchive: () {
              _hideContextMenu();
              _archivePerson(person);
            },
          ),
        ),
      ),
    ];
  }

  void _showContextMenu(Person person, Offset globalPosition) {
    final local = _toStackLocal(globalPosition);
    setState(() {
      _contextMenuPerson = person;
      _contextMenuPosition = _clampMenuPosition(local, _menuHeight);
    });
  }

  void _hideContextMenu() {
    if (_contextMenuPerson == null) return;
    setState(() => _contextMenuPerson = null);
  }

  Offset _toStackLocal(Offset globalPosition) {
    final renderObject = _bodyStackKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.attached) {
      return renderObject.globalToLocal(globalPosition);
    }
    return globalPosition;
  }

  Offset _clampMenuPosition(Offset local, double menuHeight) {
    final renderObject = _bodyStackKey.currentContext?.findRenderObject();
    final size = renderObject is RenderBox ? renderObject.size : Size.zero;
    final maxLeft = math.max(
      _menuMargin,
      size.width - _menuWidth - _menuMargin,
    );
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final maxTop = math.max(
      _menuMargin,
      size.height - menuHeight - math.max(_menuMargin, bottomInset),
    );
    return Offset(
      (local.dx - _menuWidth).clamp(_menuMargin, maxLeft),
      (local.dy - 24).clamp(_menuMargin, maxTop),
    );
  }

  void _navigateToAddPerson() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddPersonScreen()),
    ).then((_) => ref.read(personsProvider.notifier).loadPersons());
  }

  void _navigateToPersonDetail(Person person) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PersonDetailScreen(personId: person.id!),
      ),
    ).then((_) => ref.read(personsProvider.notifier).loadPersons());
  }

  void _navigateToEditPerson(Person person) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditPersonScreen(person: person)),
    ).then((_) => ref.read(personsProvider.notifier).loadPersons());
  }

  void _archivePerson(Person person) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('أرشفة ${person.name}؟'),
        content: const Text(
          'سيتم أرشفة هذا الشخص وإخفاؤه من القائمة الرئيسية. يمكن استرجاعه لاحقاً من الأرشيف.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref
                  .read(personsProvider.notifier)
                  .archivePerson(person.id!);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
            child: const Text('أرشفة'),
          ),
        ],
      ),
    );
  }
}

/// One row of the home list: either a person (pinned or not) or the divider
/// between the two groups.
class _ListItem {
  const _ListItem.person(Person this.person, {required this.pinned})
    : isDivider = false;

  const _ListItem.divider() : person = null, pinned = false, isDivider = true;

  final Person? person;
  final bool pinned;
  final bool isDivider;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [Text('الأشخاص', style: AppTextStyles.titleMedium)]),
    );
  }
}
