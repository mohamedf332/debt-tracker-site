import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../models/person.dart';
import '../../models/project.dart';
import '../../models/transaction.dart';
import '../../models/transaction_attachment.dart';
import '../../models/transaction_payment.dart';
import '../../widgets/balance_card.dart';
import '../../widgets/budget_card.dart';
import '../../widgets/project_tabs.dart';
import '../../widgets/filter_tabs.dart';
import '../../widgets/transaction_tile.dart';
import '../../widgets/add_transaction_sheet.dart';
import '../../widgets/transaction_details_sheet.dart';
import '../../widgets/add_edit_project_dialog.dart';
import '../../widgets/project_context_menu.dart';
import '../../widgets/collapsing_summary_header.dart';
import '../../providers/person_detail_provider.dart';
import '../../providers/persons_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/pdf_report_service.dart';
import '../../services/export_service.dart';
import 'edit_person_screen.dart';
import 'report_preview_screen.dart';

class PersonDetailScreen extends ConsumerStatefulWidget {
  final int personId;

  const PersonDetailScreen({super.key, required this.personId});

  @override
  ConsumerState<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends ConsumerState<PersonDetailScreen> {
  static const double _menuWidth = 280;
  static const double _menuHeight = 190;
  static const double _menuMargin = 8;

  final GlobalKey _bodyStackKey = GlobalKey();

  int? _longPressedProjectId;
  Project? _contextMenuProject;
  Offset _contextMenuPosition = Offset.zero;
  PersonDetailState? _detailState;

  /// One scroll position drives the summary card, the filter tabs and every
  /// transaction row, so they can never disagree about what is on screen.
  final ScrollController _headerScroll = ScrollController();

  /// Measured sizes of the pinned summary header's two states.
  final GlobalKey _summaryCardKey = GlobalKey();
  final GlobalKey _summaryStripKey = GlobalKey();
  double _summaryMaxExtent = kSummaryCardInitialExtent;
  double _summaryMinExtent = kSummaryStripInitialExtent;
  bool _extentMeasureScheduled = false;

  /// Auto-hiding filter tabs (rule 5): hidden as soon as the list moves down,
  /// handed back only after [kFiltersRevealDistance] of upward scrolling or
  /// once the list is back at the very top.
  bool _filtersVisible = true;
  double _lastScrollOffset = 0;
  double _scrollUpAccumulator = 0;

  /// How far the list must travel up before the filter tabs return: four rows.
  static const double kFiltersRevealDistance =
      4 * kTransactionRowHeightEstimate;

  /// Below this offset the filters are always shown, whatever the accumulator
  /// says, because at the top of the list they are the whole point.
  static const double kFiltersTopThreshold = 1;

  int? _lastActiveProjectId;

  @override
  void initState() {
    super.initState();
    _headerScroll.addListener(_onHeaderScroll);
  }

  void _onHeaderScroll() {
    final offset = _headerScroll.offset;
    final delta = offset - _lastScrollOffset;
    _lastScrollOffset = offset;

    if (offset <= kFiltersTopThreshold) {
      // At the top of the list the filters are always shown, whatever the
      // direction of travel that got us here.
      _scrollUpAccumulator = 0;
      _setFiltersVisible(true);
      return;
    }

    if (delta < -0.5) {
      // Scrolling up: only bring the tabs back once a few rows have gone by,
      // so a small flick cannot make them bounce in and out.
      _scrollUpAccumulator += -delta;
      if (_scrollUpAccumulator >= kFiltersRevealDistance) {
        _scrollUpAccumulator = 0;
        _setFiltersVisible(true);
      }
      return;
    }

    if (delta > 0.5) {
      // Scrolling down: hide right away and drop the saved upward distance.
      _scrollUpAccumulator = 0;
      _setFiltersVisible(false);
    }
  }

  void _setFiltersVisible(bool visible) {
    if (_filtersVisible == visible) return;
    setState(() => _filtersVisible = visible);
  }

  /// Re-measures the card and the strip after every frame that may have
  /// changed them (first frame, project tab swap, budget line appearing,
  /// text scale). At most one pass per frame and only rebuilds when a size
  /// really moved, so it cannot feed back into itself.
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
    _headerScroll.removeListener(_onHeaderScroll);
    _headerScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _detailState = ref.watch(personDetailProvider(widget.personId));

    final person = _detailState!.person;
    if (person == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الشخص')),
        body: _detailState!.isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: Text(
                  _detailState!.error ?? 'الشخص غير موجود',
                  style: AppTextStyles.bodyLarge.copyWith(color: AppColors.red),
                ),
              ),
      );
    }

    final activeProjectId = _detailState!.activeProjectId;

    // Switching tabs swaps the card (budget card appears/disappears), so the
    // old scroll position, the filters and the measured height are all
    // meaningless. A different card is picked up by the post-frame measure.
    if (_lastActiveProjectId != activeProjectId) {
      _lastActiveProjectId = activeProjectId;
      _filtersVisible = true;
      _scrollUpAccumulator = 0;
      _lastScrollOffset = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_headerScroll.hasClients) _headerScroll.jumpTo(0);
      });
    }

    return Scaffold(
      appBar: AppBar(
        // The amounts live in the pinned summary strip now, so the bar keeps
        // nothing but the person's name.
        title: Text(person.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _navigateToEditPerson(person),
          ),
          IconButton(
            icon: const Icon(Icons.print_outlined),
            onPressed: () => _showPdfReportDialog(),
            tooltip: 'طباعة/تصدير PDF',
          ),
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            onPressed: () => _showArchiveDialog(person),
            tooltip: 'أرشفة الشخص',
          ),
        ],
      ),
      body: Stack(
        key: _bodyStackKey,
        children: [
          Column(
            children: [
              // Project Tabs
              ProjectTabs(
                activeProjectId: activeProjectId,
                projects: _detailState!.projects,
                onTabChanged: (projectId) => ref
                    .read(personDetailProvider(widget.personId).notifier)
                    .setActiveProject(projectId),
                onAddProject: () => _showAddProjectDialog(),
                onProjectLongPress: _showProjectContextMenu,
                longPressedProjectId: _longPressedProjectId,
              ),

              // Summary card, filter tabs and transactions are all slivers of
              // ONE scroll view. The project tabs above stay pinned.
              Expanded(child: _buildScrollArea(_detailState!)),
            ],
          ),

          // Context Menu Overlay
          if (_contextMenuProject != null) ..._buildProjectContextMenuOverlay(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddTransactionSheet(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildAllTabBalanceCard() {
    final totalsAsync = ref.watch(personTotalsProvider(widget.personId));
    final settledTotal =
        ref.watch(personSettledTotalProvider(widget.personId)).valueOrNull ??
        0.0;
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

  Widget _buildProjectBalanceCard(int projectId) {
    print('🎨 [BudgetCard] building for projectId=$projectId');
    final budgetRemainingAsync = ref.watch(budgetRemainingProvider(projectId));
    final projectTotalsAsync = ref.watch(projectTotalsProvider(projectId));
    final projectSettledTotal =
        ref.watch(projectSettledTotalProvider(projectId)).valueOrNull ?? 0.0;
    final project = _detailState!.projects.firstWhere(
      (p) => p.id == projectId,
      orElse: () => Project(
        id: null,
        personId: 0,
        name: '',
        createdAt: '',
        updatedAt: '',
      ),
    );

    return Column(
      children: [
        projectTotalsAsync.when(
          data: (data) {
            final theyOweMe = data['they_owe_me'] ?? 0.0;
            final iOweThem = data['i_owe_them'] ?? 0.0;
            return BalanceCard(
              theyOweMe: theyOweMe,
              iOweThem: iOweThem,
              settledTotal: projectSettledTotal,
            );
          },
          loading: () => BalanceCard(theyOweMe: 0, iOweThem: 0),
          error: (_, __) => BalanceCard(theyOweMe: 0, iOweThem: 0),
          skipLoadingOnReload: true,
        ),
        if (project.hasBudget)
          budgetRemainingAsync.when(
            data: (budgetRemaining) {
              print(
                '🎨 [BudgetCard] rebuilt with value: $budgetRemaining for projectId=$projectId',
              );
              return BudgetCard(
                project: project,
                budgetRemaining: budgetRemaining,
              );
            },
            loading: () => BudgetCard(project: project, budgetRemaining: 0),
            error: (_, __) => BudgetCard(project: project, budgetRemaining: 0),
            skipLoadingOnReload: true,
          ),
      ],
    );
  }

  /// Balance card (plus the budget card on a project tab) that the pinned
  /// summary header collapses. Measured after layout by the header itself, so
  /// no height is guessed here.
  Widget _headerCards() {
    final activeProjectId = _detailState!.activeProjectId;
    if (activeProjectId == null) return _buildAllTabBalanceCard();
    return _buildProjectBalanceCard(activeProjectId);
  }

  CollapsingSummaryHeader _summaryHeader() {
    final activeProjectId = _detailState?.activeProjectId;
    final totals =
        (activeProjectId == null
                ? ref.watch(personTotalsProvider(widget.personId))
                : ref.watch(projectTotalsProvider(activeProjectId)))
            .valueOrNull;
    return CollapsingSummaryHeader(
      card: _headerCards(),
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

  /// Filter tabs live inside the scroll view so they can retire while the list
  /// travels down. [AnimatedSize] with a zero height factor collapses them in
  /// place rather than unmounting them, so the tabs keep their state and the
  /// rows underneath glide up instead of jumping.
  Widget _filterTabsSliver(PersonDetailState state) {
    return SliverToBoxAdapter(
      child: AnimatedSize(
        // Keyed so tests (and anything else) can measure the collapsed box:
        // the tabs themselves keep their natural height and are clipped.
        key: const ValueKey('filter_tabs_collapse'),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: _filtersVisible ? 1.0 : 0.0,
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: FilterTabs(
                  selectedType: state.filterType,
                  settlementFilter: state.settlementFilter,
                  startDate: state.filterStartDate,
                  endDate: state.filterEndDate,
                  onTypeChanged: (type) => ref
                      .read(personDetailProvider(widget.personId).notifier)
                      .setFilterType(type),
                  onSettlementChanged: (filter) => ref
                      .read(personDetailProvider(widget.personId).notifier)
                      .setSettlementFilter(filter),
                  onStartDateChanged: (date) => ref
                      .read(personDetailProvider(widget.personId).notifier)
                      .setFilterDateRange(date, state.filterEndDate),
                  onEndDateChanged: (date) => ref
                      .read(personDetailProvider(widget.personId).notifier)
                      .setFilterDateRange(state.filterStartDate, date),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollArea(PersonDetailState state) {
    _scheduleExtentMeasure();
    return CustomScrollView(
      controller: _headerScroll,
      slivers: [
        SliverPersistentHeader(pinned: true, delegate: _summaryHeader()),
        _filterTabsSliver(state),
        if (state.transactions.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 80,
                    color: AppColors.gray.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'لا توجد معاملات',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.gray,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'اضغط على + لإضافة معاملة جديدة',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.gray,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              0,
              8,
              0,
              80 + MediaQuery.of(context).padding.bottom,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final transaction = state.transactions[index];
                final attachments = state.attachmentsMap[transaction.id!] ?? [];
                final projectName = state.projects
                    .firstWhere(
                      (p) => p.id == transaction.projectId,
                      orElse: () => Project(
                        id: null,
                        personId: 0,
                        name: '',
                        createdAt: '',
                        updatedAt: '',
                      ),
                    )
                    .name;

                return TransactionTile(
                  transaction: transaction,
                  attachments: attachments,
                  projectName: state.activeProjectId == null
                      ? (projectName.isNotEmpty ? projectName : null)
                      : null,
                  paidAmount: totalPaid(state.paymentsMap[transaction.id]),
                  onTap: () =>
                      _showTransactionDetails(transaction, attachments),
                  onLongPress: () =>
                      _showTransactionContextMenu(transaction, attachments),
                );
              }, childCount: state.transactions.length),
            ),
          ),
      ],
    );
  }

  void _showAddTransactionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: AddTransactionSheet(
            personId: widget.personId,
            initialProjectId: _detailState!.activeProjectId,
            projects: _detailState!.projects,
          ),
        ),
      ),
    );
  }

  void _showTransactionDetails(
    Transaction transaction,
    List<TransactionAttachment> attachments,
  ) {
    final projects = _detailState?.projects ?? const <Project>[];
    final projectName = projects
        .where((p) => p.id == transaction.projectId)
        .map((p) => p.name)
        .firstOrNull;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: TransactionDetailsSheet(
            personId: widget.personId,
            transaction: transaction,
            attachments: attachments,
            projectName: projectName,
          ),
        ),
      ),
    );
  }

  void _showTransactionContextMenu(
    Transaction transaction,
    List<TransactionAttachment> attachments,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('تعديل'),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditTransactionSheet(transaction);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.delete_outlined,
                    color: AppColors.red,
                  ),
                  title: Text(
                    'حذف',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.red,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _deleteTransaction(transaction);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditTransactionSheet(Transaction transaction) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: AddTransactionSheet(
            personId: widget.personId,
            initialProjectId: transaction.projectId,
            projects: _detailState!.projects,
            transaction: transaction,
          ),
        ),
      ),
    );
  }

  Future<void> _deleteTransaction(Transaction transaction) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المعاملة؟'),
        content: const Text(
          'سيتم حذف المعاملة ومرفقاتها نهائياً. لا يمكن التراجع.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref
          .read(personDetailProvider(widget.personId).notifier)
          .deleteTransaction(transaction.id!);
    }
  }

  void _showAddProjectDialog() {
    showDialog(
      context: context,
      builder: (_) => AddEditProjectDialog(personId: widget.personId),
    );
  }

  void _showEditProjectDialog(Project project) {
    showDialog(
      context: context,
      builder: (_) =>
          AddEditProjectDialog(personId: widget.personId, project: project),
    );
  }

  void _archiveProject(Project project) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('أرشفة مشروع ${project.name}؟'),
        content: const Text(
          'سيتم أرشفة المشروع وإخفاؤه من التابات. ستظل معاملاته محفوظة لكنها لن تظهر في تبويب "الكل" أو الأرصدة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref
                    .read(personDetailProvider(widget.personId).notifier)
                    .archiveProject(project.id!);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'تمت أرشفة المشروع. يمكنك استرجاعه من الأرشيف.',
                    ),
                  ),
                );
              } catch (error) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تعذرت أرشفة المشروع: $error')),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
            child: const Text('أرشفة'),
          ),
        ],
      ),
    );
  }

  void _showPdfReportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تقرير / تصدير'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('تقرير PDF - كل الفترة'),
              onTap: () => _generatePdfReport(null, null),
            ),
            ListTile(
              leading: const Icon(Icons.date_range),
              title: const Text('تقرير PDF - نطاق مخصص'),
              onTap: () => _showCustomDateRangePicker(),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.file_download,
                color: AppColors.primary,
              ),
              title: const Text('تصدير بيانات هذا الشخص (JSON)'),
              subtitle: const Text('حفظ في مجلد Downloads'),
              onTap: () => _exportPersonData(),
            ),
            ListTile(
              leading: const Icon(Icons.share, color: AppColors.primary),
              title: const Text('مشاركة بيانات هذا الشخص (JSON)'),
              subtitle: const Text('مشاركة عبر التطبيقات الأخرى'),
              onTap: () => _sharePersonData(),
            ),
          ],
        ),
      ),
    );
  }

  /// Export this person's data to JSON file using file_picker's save dialog.
  Future<void> _exportPersonData() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text('جاري التصدير...'),
          ],
        ),
        duration: Duration(days: 1),
      ),
    );

    try {
      final person = ref
          .read(personDetailProvider(widget.personId).notifier)
          .state
          .person;
      if (person == null) throw Exception('الشخص غير موجود');

      final exportData = await ref.read(exportServiceProvider).buildExportData([
        person,
      ]);
      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      final saved = await ref
          .read(exportServiceProvider)
          .saveExportToDevice(jsonString);

      if (mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
        if (saved) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('تم حفظ الملف في مجلد Downloads')),
          );
        } else {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('تم الإلغاء')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('فشل الحفظ: $e')),
        );
      }
    }
  }

  /// Share this person's data as JSON via the system share sheet.
  Future<void> _sharePersonData() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text('جاري التصدير...'),
          ],
        ),
        duration: Duration(days: 1),
      ),
    );

    try {
      final person = await ref
          .read(personDetailProvider(widget.personId).notifier)
          .state
          .person;
      if (person == null) throw Exception('الشخص غير موجود');
      final exportData = await ref.read(exportServiceProvider).buildExportData([
        person,
      ]);
      await ref
          .read(exportServiceProvider)
          .shareExportFile(context, 'debt-tracker', exportData);
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('خطأ في المشاركة: $e')),
        );
      }
    }
  }

  void _showCustomDateRangePicker() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar'),
    );

    if (range != null) {
      _generatePdfReport(range.start, range.end);
    }
  }

  Future<void> _generatePdfReport(DateTime? start, DateTime? end) async {
    Navigator.pop(context); // close the report options dialog
    if (!mounted) return;

    // Hold a real Route handle so the indicator can never be left behind:
    // showDialog() hides its route, and a fast report would race a pop().
    final navigator = Navigator.of(context);
    final loadingRoute = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('جاري توليد التقرير...'),
              ],
            ),
          ),
        ),
      ),
    );
    navigator.push(loadingRoute);

    Object? failure;
    ReportPdf? report;
    try {
      final activeProjectId = _detailState!.activeProjectId;
      final service = ref.read(pdfReportServiceProvider);

      report = activeProjectId != null
          ? await service.buildProjectReport(
              projectId: activeProjectId,
              startDate: start,
              endDate: end,
            )
          : await service.buildPersonReport(
              personId: widget.personId,
              startDate: start,
              endDate: end,
            );
    } catch (e) {
      failure = e;
    }

    if (loadingRoute.isCurrent) navigator.pop();
    if (!mounted) return;

    if (failure != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ في توليد التقرير: $failure')));
      return;
    }

    if (report != null) await _showReportActions(report);
  }

  /// What to do with a finished report: read it in the app, hand it to a real
  /// PDF reader (the only place the appendix links work), or send it out.
  Future<void> _showReportActions(ReportPdf report) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf),
                  title: const Text('معاينة التقرير'),
                  subtitle: const Text(ReportPreviewScreen.linkHint),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ReportPreviewScreen(report: report),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.open_in_new),
                  title: const Text('فتح في قارئ PDF'),
                  subtitle: const Text('عشان روابط الصور تشتغل'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    try {
                      await ref
                          .read(pdfReportServiceProvider)
                          .openExternally(report);
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تعذّر فتح الملف: $e')),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('مشاركة / حفظ'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    try {
                      await ref.read(pdfReportServiceProvider).share(report);
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تعذّرت المشاركة: $e')),
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showArchiveDialog(Person person) {
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
              if (mounted) Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
            child: const Text('أرشفة'),
          ),
        ],
      ),
    );
  }

  void _navigateToEditPerson(Person person) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditPersonScreen(person: person)),
    ).then((_) => ref.read(personsProvider.notifier).loadPersons());
  }

  void _hideContextMenu() {
    if (_contextMenuProject == null) return;
    setState(() {
      _contextMenuProject = null;
      _longPressedProjectId = null;
    });
  }

  void _showProjectContextMenu(Project project, Offset globalPosition) {
    final local = _toStackLocal(globalPosition);
    setState(() {
      _contextMenuProject = project;
      _longPressedProjectId = project.id;
      _contextMenuPosition = _clampMenuPosition(local, _menuHeight);
    });
  }

  /// Scrim + menu, anchored under the pressed chip and clamped to the stack so
  /// it can never be laid out off-screen.
  List<Widget> _buildProjectContextMenuOverlay() {
    final project = _contextMenuProject!;
    return [
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
            // Scales from the corner nearest the chip that was held.
            child: Transform.scale(
              scale: 0.92 + 0.08 * t,
              alignment: Alignment.topRight,
              child: child,
            ),
          ),
          child: ProjectContextMenu(
            projectName: project.name,
            onEdit: () {
              _hideContextMenu();
              _showEditProjectDialog(project);
            },
            onArchive: () {
              _hideContextMenu();
              _archiveProject(project);
            },
          ),
        ),
      ),
    ];
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
      (local.dy + 12).clamp(_menuMargin, maxTop),
    );
  }
}
