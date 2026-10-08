import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/person.dart';
import '../models/project.dart';
import '../models/transaction.dart';
import '../models/transaction_attachment.dart';
import '../db/person_dao.dart';
import '../db/project_dao.dart';
import '../db/transaction_dao.dart';
import '../db/attachment_dao.dart';
import '../db/payment_dao.dart';
import '../models/transaction_payment.dart';
import '../services/transaction_creator.dart';
import 'persons_provider.dart' as persons_provider;

class PersonDetailState {
  final Person? person;
  final List<Project> projects;
  final List<Transaction> transactions;
  final Map<int, List<TransactionAttachment>> attachmentsMap;

  /// Installment history per transaction, newest first. Empty for rows that
  /// are not on partial payments.
  final Map<int, List<TransactionPayment>> paymentsMap;
  final int? activeProjectId; // null = "الكل" tab
  final TransactionType? filterType;
  final SettlementFilter settlementFilter;
  final DateTime? filterStartDate;
  final DateTime? filterEndDate;
  final bool isLoading;
  final String? error;

  const PersonDetailState({
    this.person,
    this.projects = const [],
    this.transactions = const [],
    this.attachmentsMap = const {},
    this.paymentsMap = const {},
    this.activeProjectId,
    this.filterType,
    this.settlementFilter = SettlementFilter.all,
    this.filterStartDate,
    this.filterEndDate,
    this.isLoading = false,
    this.error,
  });

  PersonDetailState copyWith({
    Object? person = _notProvided,
    Object? projects = _notProvided,
    Object? transactions = _notProvided,
    Object? attachmentsMap = _notProvided,
    Object? paymentsMap = _notProvided,
    Object? activeProjectId = _notProvided,
    Object? filterType = _notProvided,
    Object? settlementFilter = _notProvided,
    Object? filterStartDate = _notProvided,
    Object? filterEndDate = _notProvided,
    Object? isLoading = _notProvided,
    Object? error = _notProvided,
  }) {
    return PersonDetailState(
      person: identical(person, _notProvided) ? this.person : person as Person?,
      projects: identical(projects, _notProvided)
          ? this.projects
          : projects as List<Project>,
      transactions: identical(transactions, _notProvided)
          ? this.transactions
          : transactions as List<Transaction>,
      attachmentsMap: identical(attachmentsMap, _notProvided)
          ? this.attachmentsMap
          : attachmentsMap as Map<int, List<TransactionAttachment>>,
      paymentsMap: identical(paymentsMap, _notProvided)
          ? this.paymentsMap
          : paymentsMap as Map<int, List<TransactionPayment>>,
      activeProjectId: identical(activeProjectId, _notProvided)
          ? this.activeProjectId
          : activeProjectId as int?,
      filterType: identical(filterType, _notProvided)
          ? this.filterType
          : filterType as TransactionType?,
      settlementFilter: identical(settlementFilter, _notProvided)
          ? this.settlementFilter
          : settlementFilter as SettlementFilter,
      filterStartDate: identical(filterStartDate, _notProvided)
          ? this.filterStartDate
          : filterStartDate as DateTime?,
      filterEndDate: identical(filterEndDate, _notProvided)
          ? this.filterEndDate
          : filterEndDate as DateTime?,
      isLoading: identical(isLoading, _notProvided)
          ? this.isLoading
          : isLoading as bool,
      error: identical(error, _notProvided) ? this.error : error as String?,
    );
  }
}

// Sentinel for "not provided" in copyWith
class _NotProvided {
  const _NotProvided();
}

const _notProvided = _NotProvided();

class PersonDetailNotifier extends StateNotifier<PersonDetailState> {
  final PersonDao _personDao;
  final ProjectDao _projectDao;
  final TransactionDao _transactionDao;
  final AttachmentDao _attachmentDao;
  final PaymentDao _paymentDao;
  final TransactionCreator _creator = TransactionCreator();
  final Ref _ref;

  PersonDetailNotifier(
    this._personDao,
    this._projectDao,
    this._transactionDao,
    this._attachmentDao,
    this._paymentDao,
    this._ref,
  ) : super(const PersonDetailState()) {
    // Listen to dataVersionProvider to reload when data changes
    _ref.listen(persons_provider.dataVersionProvider, (_, __) {
      final personId = state.person?.id ?? 0;
      if (personId != 0) {
        loadPersonDetail(personId);
      }
    });
  }

  void _refreshRelatedProviders(int? projectId) {
    // Refresh budget-related providers for the active project
    if (projectId != null) {
      _ref.invalidate(budgetRemainingProvider(projectId));
      _ref.invalidate(projectBalanceProvider(projectId));
      _ref.invalidate(projectTotalsProvider(projectId));
    }
    // Always refresh persons provider (home screen) and overall totals
    _ref.invalidate(persons_provider.personsProvider);
    _ref.invalidate(persons_provider.overallTotalsProvider);
    // Refresh person totals and balance for "All" tab and home screen
    if (state.person != null) {
      final personId = state.person!.id!;
      _ref.invalidate(persons_provider.personBalanceProvider(personId));
      _ref.invalidate(persons_provider.personTotalsProvider(personId));
    }
  }

  Future<void> loadPersonDetail(int personId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final person = await _personDao.getPerson(personId);
      if (person == null) {
        state = state.copyWith(isLoading: false, error: 'الشخص غير موجود');
        return;
      }

      final projects = await _projectDao.getActiveProjectsForPerson(personId);
      await _loadTransactionsAndAttachments(personId, null);

      state = state.copyWith(
        person: person,
        projects: projects,
        activeProjectId: null,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> _loadTransactionsAndAttachments(
    int personId,
    int? projectId,
  ) async {
    final transactions = projectId != null
        ? await _transactionDao.getTransactionsForProject(projectId!)
        : await _transactionDao.getAllTransactionsForPerson(personId);

    final filteredTxns = _applyFilters(transactions);
    final attachmentsMap = <int, List<TransactionAttachment>>{};

    for (final txn in filteredTxns) {
      final attachments = await _attachmentDao.getAttachmentsForTransaction(
        txn.id!,
      );
      if (attachments.isNotEmpty) {
        attachmentsMap[txn.id!] = attachments;
      }
    }

    final paymentsMap = await _paymentDao.getPaymentsForTransactions([
      for (final txn in filteredTxns)
        if (txn.id != null) txn.id!,
    ]);

    state = state.copyWith(
      transactions: filteredTxns,
      attachmentsMap: attachmentsMap,
      paymentsMap: paymentsMap,
    );
  }

  /// Amount already collected/paid on [txn] (0 unless it is on installments).
  double paidOf(Transaction txn) => totalPaid(state.paymentsMap[txn.id]);

  /// What is still outstanding, honouring installments.
  double remainingOf(Transaction txn) => outstandingOf(txn, paidOf(txn));

  List<Transaction> _applyFilters(List<Transaction> transactions) {
    var filtered = transactions;

    if (state.filterType != null) {
      filtered = filtered.where((txn) => txn.type == state.filterType).toList();
    }

    switch (state.settlementFilter) {
      case SettlementFilter.all:
        break;
      case SettlementFilter.unsettled:
        filtered = filtered.where((txn) => !txn.isSettled).toList();
      case SettlementFilter.settled:
        filtered = filtered.where((txn) => txn.isSettled).toList();
    }

    if (state.filterStartDate != null) {
      filtered = filtered.where((txn) {
        final txnDate = DateTime.parse(txn.date);
        return txnDate.isAfter(
          state.filterStartDate!.subtract(const Duration(days: 1)),
        );
      }).toList();
    }

    if (state.filterEndDate != null) {
      filtered = filtered.where((txn) {
        final txnDate = DateTime.parse(txn.date);
        return txnDate.isBefore(
          state.filterEndDate!.add(const Duration(days: 1)),
        );
      }).toList();
    }

    return filtered;
  }

  Future<void> setActiveProject(int? projectId) async {
    if (state.person == null) return;

    state = state.copyWith(activeProjectId: projectId);
    await _loadTransactionsAndAttachments(state.person!.id!, projectId);
  }

  Future<void> setFilterType(TransactionType? type) async {
    state = state.copyWith(filterType: type);
    await _refreshTransactions();
  }

  Future<void> setSettlementFilter(SettlementFilter filter) async {
    state = state.copyWith(settlementFilter: filter);
    await _refreshTransactions();
  }

  Future<void> setFilterDateRange(DateTime? start, DateTime? end) async {
    state = state.copyWith(filterStartDate: start, filterEndDate: end);
    await _refreshTransactions();
  }

  Future<void> _refreshTransactions() async {
    if (state.person == null) return;
    await _loadTransactionsAndAttachments(
      state.person!.id!,
      state.activeProjectId,
    );
  }

  Future<void> addProject(Project project) async {
    try {
      final id = await _projectDao.insertProject(project);
      final newProject = project.copyWith(id: id);
      state = state.copyWith(projects: [...state.projects, newProject]);
      _refreshRelatedProviders(state.activeProjectId);
      _ref.read(persons_provider.dataVersionProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> updateProject(Project project) async {
    try {
      await _projectDao.updateProject(project);
      final index = state.projects.indexWhere((p) => p.id == project.id);
      if (index != -1) {
        final newProjects = [...state.projects];
        newProjects[index] = project;
        state = state.copyWith(projects: newProjects);
      }
      _refreshRelatedProviders(state.activeProjectId);
      _ref.read(persons_provider.dataVersionProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> archiveProject(int projectId) async {
    try {
      await _projectDao.archiveProject(projectId);
      state = state.copyWith(
        projects: state.projects.where((p) => p.id != projectId).toList(),
        activeProjectId: state.activeProjectId == projectId
            ? null
            : state.activeProjectId,
      );
      if (state.activeProjectId == projectId) {
        await _loadTransactionsAndAttachments(state.person!.id!, null);
      }
      _refreshRelatedProviders(state.activeProjectId);
      _ref.read(persons_provider.dataVersionProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> unarchiveProject(int projectId) async {
    try {
      await _projectDao.unarchiveProject(projectId);
      final project = await _projectDao.getProject(projectId);
      if (project != null) {
        state = state.copyWith(projects: [...state.projects, project]);
      }
      _refreshRelatedProviders(state.activeProjectId);
      _ref.read(persons_provider.dataVersionProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> permanentlyDeleteProject(
    int projectId,
    Future<void> Function(String) deleteFile,
  ) async {
    try {
      await _projectDao.permanentlyDeleteProject(projectId, deleteFile);
      state = state.copyWith(
        projects: state.projects.where((p) => p.id != projectId).toList(),
        activeProjectId: state.activeProjectId == projectId
            ? null
            : state.activeProjectId,
      );
      if (state.activeProjectId == projectId) {
        await _loadTransactionsAndAttachments(state.person!.id!, null);
      }
      _refreshRelatedProviders(state.activeProjectId);
      _ref.read(persons_provider.dataVersionProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  /// Creates a transaction through [TransactionCreator] — the same path the
  /// Add Person screen uses — so a row born settled carries its payment from
  /// the very first write.
  Future<int> addTransaction(Transaction transaction) async {
    try {
      print(
        '[addTransaction] Starting insert for personId=${state.person?.id}, projectId=${transaction.projectId}, amount=${transaction.amount}, type=${transaction.type}',
      );
      final id = await _creator.create(transaction);
      print('[addTransaction] Insert returned id=$id');
      final newTxn = transaction.copyWith(id: id);
      state = state.copyWith(transactions: [newTxn, ...state.transactions]);
      print(
        '[addTransaction] State updated with new transaction, count=${state.transactions.length}',
      );
      // Reload to refresh totals
      await _loadTransactionsAndAttachments(
        state.person!.id!,
        state.activeProjectId,
      );
      print(
        '[addTransaction] Reload complete, transaction count=${state.transactions.length}',
      );
      print(
        '[addTransaction] Calling _refreshRelatedProviders with activeProjectId=${state.activeProjectId}',
      );
      _refreshRelatedProviders(state.activeProjectId);
      _ref.read(persons_provider.dataVersionProvider.notifier).state++;
      return id;
    } catch (e) {
      print('[addTransaction] ERROR: $e');
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> updateTransaction(Transaction oldTxn, Transaction newTxn) async {
    try {
      print('[updateTransaction] Updating transaction id=${oldTxn.id}');
      // Rule: an amount may never drop below what has already been paid.
      // Throws [PaymentValidationException] with the Arabic message to show.
      if (oldTxn.id != null) {
        await _paymentDao.ensureAmountCoversPaid(oldTxn.id!, newTxn.amount);
      }
      await _transactionDao.updateTransaction(oldTxn, newTxn);
      // The ceiling moved, so the derived status may have moved too.
      if (oldTxn.id != null) {
        await _paymentDao.syncStatus(oldTxn.id!);
      }
      await _loadTransactionsAndAttachments(
        state.person!.id!,
        state.activeProjectId,
      );
      _refreshRelatedProviders(state.activeProjectId);
      _ref.read(persons_provider.dataVersionProvider.notifier).state++;
      print('[updateTransaction] Reload complete');
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  /// Un-settle from the transaction tile: the caller confirms first, then
  /// the payment history is wiped and the derived status falls back.
  Future<void> clearPayments(int txnId) async {
    try {
      print('[clearPayments] id=$txnId');
      await _paymentDao.clearPayments(txnId);
      await _loadTransactionsAndAttachments(
        state.person!.id!,
        state.activeProjectId,
      );
      _refreshRelatedProviders(state.activeProjectId);
      _ref.read(persons_provider.dataVersionProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> deleteTransaction(int txnId) async {
    try {
      print('[deleteTransaction] Deleting transaction id=$txnId');
      await _transactionDao.deleteTransaction(txnId);
      await _loadTransactionsAndAttachments(
        state.person!.id!,
        state.activeProjectId,
      );
      _refreshRelatedProviders(state.activeProjectId);
      _ref.read(persons_provider.dataVersionProvider.notifier).state++;
      print('[deleteTransaction] Reload complete');
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> addAttachments(int txnId, List<String> filePaths) async {
    try {
      for (final path in filePaths) {
        final attachment = TransactionAttachment(
          transactionId: txnId,
          filePath: path,
          createdAt: DateTime.now().toIso8601String(),
        );
        await _attachmentDao.insertAttachment(attachment);
      }
      await _refreshTransactions();
      _refreshRelatedProviders(state.activeProjectId);
      _ref.read(persons_provider.dataVersionProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> deleteAttachment(int attachmentId, String filePath) async {
    try {
      await _attachmentDao.deleteAttachment(attachmentId);
      await _refreshTransactions();
      _refreshRelatedProviders(state.activeProjectId);
      _ref.read(persons_provider.dataVersionProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }
}

final personDetailProvider =
    StateNotifierProvider.family<PersonDetailNotifier, PersonDetailState, int>((
      ref,
      personId,
    ) {
      final personDao = ref.watch(persons_provider.personDaoProvider);
      final projectDao = ref.watch(persons_provider.projectDaoProvider);
      final transactionDao = ref.watch(persons_provider.transactionDaoProvider);
      final attachmentDao = ref.watch(persons_provider.attachmentDaoProvider);
      final paymentDao = ref.watch(paymentDaoProvider);

      final notifier = PersonDetailNotifier(
        personDao,
        projectDao,
        transactionDao,
        attachmentDao,
        paymentDao,
        ref,
      );
      notifier.loadPersonDetail(personId);
      return notifier;
    });

// Project balance - use FutureProvider.autoDispose for reactive updates
final projectBalanceProvider = FutureProvider.autoDispose.family<double, int>((
  ref,
  projectId,
) async {
  ref.watch(persons_provider.dataVersionProvider);
  final projectDao = ref.watch(persons_provider.projectDaoProvider);
  return projectDao.getProjectBalance(projectId);
});

final projectTotalsProvider = FutureProvider.autoDispose
    .family<Map<String, double>, int>((ref, projectId) async {
      ref.watch(persons_provider.dataVersionProvider);
      final projectDao = ref.watch(persons_provider.projectDaoProvider);
      return projectDao.getProjectTotals(projectId);
    });

/// Signed settled total for the "مسدَّد: X" line on project balance cards.
final projectSettledTotalProvider = FutureProvider.autoDispose
    .family<double, int>((ref, projectId) async {
      ref.watch(persons_provider.dataVersionProvider);
      final projectDao = ref.watch(persons_provider.projectDaoProvider);
      return projectDao.getProjectSettledTotal(projectId);
    });

final budgetRemainingProvider = FutureProvider.autoDispose.family<double, int>((
  ref,
  projectId,
) async {
  ref.watch(persons_provider.dataVersionProvider);
  final projectDao = ref.watch(persons_provider.projectDaoProvider);
  final project = await ref
      .read(persons_provider.projectDaoProvider)
      .getProject(projectId);
  if (project == null || project.budget == null) return 0.0;
  return projectDao.getBudgetRemaining(projectId);
});

// Archived projects
final archivedProjectsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  ref.watch(persons_provider.dataVersionProvider);
  final projectDao = ref.watch(persons_provider.projectDaoProvider);
  return projectDao.getArchivedProjects();
});
