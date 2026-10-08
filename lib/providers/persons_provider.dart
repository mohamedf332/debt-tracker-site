import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/person.dart';
import '../models/transaction.dart';
import '../models/transaction_payment.dart';
import '../db/person_dao.dart';
import '../db/project_dao.dart';
import '../db/transaction_dao.dart';
import '../db/attachment_dao.dart';
import '../db/payment_dao.dart';
import '../db/db_helper.dart';
import '../services/image_storage_service.dart';
import '../services/pdf_report_service.dart';
import '../services/drive_backup_service.dart';
import '../services/transaction_creator.dart';

final personDaoProvider = Provider((ref) => PersonDao());
final projectDaoProvider = Provider((ref) => ProjectDao());
final transactionDaoProvider = Provider((ref) => TransactionDao());
final attachmentDaoProvider = Provider((ref) => AttachmentDao());
final imageStorageProvider = Provider((ref) => ImageStorageService.instance);
final databaseHelperProvider = Provider((ref) => DatabaseHelper.instance);
final transactionCreatorProvider = Provider((ref) => TransactionCreator());
final pdfReportServiceProvider = Provider((ref) => PdfReportService.instance);

// Version provider to trigger refreshes across all related providers
final dataVersionProvider = StateProvider<int>((ref) => 0);

/// Transaction mutations that must work from any screen (e.g. the quick
/// settle toggle on a tile), not only from the person-detail notifier.
class TransactionActions {
  TransactionActions(this._ref);

  final Ref _ref;

  /// Flip the settlement state of [txn].
  ///
  /// Rule 2: settling stamps `settled_at` (defaults to now), un-settling
  /// clears it. Bumping [dataVersionProvider] refreshes balances, budget,
  /// totals and any open detail screen at once.
  ///
  /// Installment rows are excluded by the caller: their status is derived
  Future<void> addPayment({
    required int transactionId,
    required double amount,
    required String date,
    String? note,
  }) async {
    await _ref
        .read(paymentDaoProvider)
        .addPayment(
          transactionId: transactionId,
          amount: amount,
          date: date,
          note: note,
        );
    _bump();
  }

  Future<void> updatePayment(
    TransactionPayment old, {
    required double amount,
    required String date,
    String? note,
  }) async {
    await _ref
        .read(paymentDaoProvider)
        .updatePayment(old, amount: amount, date: date, note: note);
    _bump();
  }

  Future<void> deletePayment(int paymentId) async {
    await _ref.read(paymentDaoProvider).deletePayment(paymentId);
    _bump();
  }

  /// The "un-settle" action. The caller has already shown the confirm
  /// dialog; this only wipes the history and lets the status fall back.
  Future<void> clearPayments(int transactionId) async {
    await _ref.read(paymentDaoProvider).clearPayments(transactionId);
    _bump();
  }

  /// One version bump: every balance, budget, tile and summary watches it.
  void _bump() => _ref.read(dataVersionProvider.notifier).state++;
}

final transactionActionsProvider = Provider((ref) => TransactionActions(ref));

// Persons state
class PersonsState {
  final List<Person> persons;
  final bool isLoading;
  final String? error;

  const PersonsState({
    this.persons = const [],
    this.isLoading = false,
    this.error,
  });

  PersonsState copyWith({
    List<Person>? persons,
    bool? isLoading,
    String? error,
  }) {
    return PersonsState(
      persons: persons ?? this.persons,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class PersonsNotifier extends StateNotifier<PersonsState> {
  final PersonDao _personDao;
  final Ref _ref;

  PersonsNotifier(this._personDao, this._ref) : super(const PersonsState()) {
    _ref.listen(dataVersionProvider, (_, __) {
      loadPersons();
      // Any data change schedules a debounced Drive upload when the user is
      // in "after every change" backup mode.
      DriveBackupService.instance.triggerBackupAfterChange();
    });
    loadPersons();
  }

  Future<void> loadPersons() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final persons = await _personDao.getActivePersons();
      state = state.copyWith(persons: persons, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void refreshData() {
    _ref.read(dataVersionProvider.notifier).state++;
  }

  /// Creates the person and — when the caller has one — its first transaction
  /// inside a single `db.transaction`.
  ///
  /// A failing transaction insert rolls the person back too, so nobody is
  /// left on the home list with a balance that was never written, and the
  /// error is rethrown for the screen to show. [initialTransaction] is a
  /// builder because the new person's id only exists after it is inserted.
  Future<void> addPerson(
    Person person, {
    Transaction Function(int personId)? initialTransaction,
  }) async {
    try {
      final db = await _ref.read(databaseHelperProvider).database;
      final id = await db.transaction((txn) async {
        final personId = await _personDao.insertPersonOn(txn, person);
        if (initialTransaction != null) {
          final txnToCreate = initialTransaction(personId);
          await _ref
              .read(transactionCreatorProvider)
              .create(txnToCreate, db: txn);
        }
        return personId;
      });
      final newPerson = person.copyWith(id: id);
      state = state.copyWith(persons: [newPerson, ...state.persons]);
      _ref.read(dataVersionProvider.notifier).state++;
    } catch (e, st) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> updatePerson(Person person) async {
    try {
      await _personDao.updatePerson(person);
      final index = state.persons.indexWhere((p) => p.id == person.id);
      if (index != -1) {
        final newPersons = [...state.persons];
        newPersons[index] = person;
        state = state.copyWith(persons: newPersons);
      }
      _ref.read(dataVersionProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> togglePin(int personId, bool isPinned) async {
    try {
      await _personDao.togglePin(personId, isPinned);
      await loadPersons();
      _ref.read(dataVersionProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> updatePinOrders(List<Map<String, dynamic>> updates) async {
    try {
      await _personDao.updatePinOrdersBatch(updates);
      await loadPersons();
      _ref.read(dataVersionProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> archivePerson(int personId) async {
    try {
      await _personDao.archivePerson(personId);
      state = state.copyWith(
        persons: state.persons.where((p) => p.id != personId).toList(),
      );
      _ref.read(dataVersionProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> unarchivePerson(int personId) async {
    try {
      await _personDao.unarchivePerson(personId);
      await loadPersons();
      _ref.read(dataVersionProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }

  Future<void> permanentlyDeletePerson(
    int personId,
    Future<void> Function(String) deleteFile,
  ) async {
    try {
      await _personDao.permanentlyDeletePerson(personId, deleteFile);
      state = state.copyWith(
        persons: state.persons.where((p) => p.id != personId).toList(),
      );
      _ref.read(dataVersionProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      rethrow;
    }
  }
}

final personsProvider = StateNotifierProvider<PersonsNotifier, PersonsState>((
  ref,
) {
  final personDao = ref.watch(personDaoProvider);
  final refObj = ref;
  return PersonsNotifier(personDao, refObj);
});

// Person totals - FutureProvider.autoDispose for reactive updates
final personBalanceProvider = FutureProvider.autoDispose.family<double, int>((
  ref,
  personId,
) async {
  ref.watch(dataVersionProvider);
  final personDao = ref.watch(personDaoProvider);
  return personDao.getPersonBalance(personId);
});

final personTotalsProvider = FutureProvider.autoDispose
    .family<Map<String, double>, int>((ref, personId) async {
      ref.watch(dataVersionProvider);
      final personDao = ref.watch(personDaoProvider);
      return personDao.getPersonTotals(personId);
    });

/// Signed settled total (they_owe_me +, i_owe_them -) for the "مسدَّد: X" line.
final personSettledTotalProvider = FutureProvider.autoDispose
    .family<double, int>((ref, personId) async {
      ref.watch(dataVersionProvider);
      final personDao = ref.watch(personDaoProvider);
      return personDao.getPersonSettledTotal(personId);
    });

// Archived persons
final archivedPersonsProvider = FutureProvider.autoDispose<List<Person>>((
  ref,
) async {
  ref.watch(dataVersionProvider);
  final personDao = ref.watch(personDaoProvider);
  return personDao.getArchivedPersons();
});

// Overall totals
final overallTotalsProvider = FutureProvider.autoDispose<Map<String, double>>((
  ref,
) async {
  ref.watch(dataVersionProvider);
  final personDao = ref.watch(personDaoProvider);
  final persons = await personDao.getActivePersons();

  double totalTheyOweMe = 0;
  double totalIOweThem = 0;

  for (final person in persons) {
    if (person.id == null) continue;
    final balance = await ref
        .read(personDaoProvider)
        .getPersonBalance(person.id!);
    if (balance > 0) {
      totalTheyOweMe += balance;
    } else if (balance < 0) {
      totalIOweThem += balance.abs();
    }
  }

  return {
    'they_owe_me': totalTheyOweMe,
    'i_owe_them': totalIOweThem,
    'net': totalTheyOweMe - totalIOweThem,
  };
});

/// Signed settled total across all active persons (for the home balance card).
final overallSettledTotalProvider = FutureProvider.autoDispose<double>((
  ref,
) async {
  ref.watch(dataVersionProvider);
  final personDao = ref.watch(personDaoProvider);
  final persons = await personDao.getActivePersons();

  double total = 0;
  for (final person in persons) {
    if (person.id == null) continue;
    total += await personDao.getPersonSettledTotal(person.id!);
  }
  return total;
});
