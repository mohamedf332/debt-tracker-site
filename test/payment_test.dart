import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

import 'package:debt_tracker/db/db_helper.dart';
import 'package:debt_tracker/db/payment_dao.dart';
import 'package:debt_tracker/db/person_dao.dart';
import 'package:debt_tracker/db/project_dao.dart';
import 'package:debt_tracker/db/transaction_dao.dart';
import 'package:debt_tracker/models/person.dart';
import 'package:debt_tracker/models/project.dart';
import 'package:debt_tracker/models/transaction.dart';
import 'package:debt_tracker/models/transaction_payment.dart';
import 'package:debt_tracker/services/export_service.dart';
import 'package:debt_tracker/services/import_service.dart';

/// The payment book is the single source of truth for settlement, so these
/// tests run against the real schema: migration, derived status, validation
/// and the export/import round trip all share one throw-away database.
void main() {
  Directory? tempDir;

  String dbPath() => p.join(tempDir!.path, 'debt_tracker.db');

  void wipeTemp() {
    final existing = tempDir;
    if (existing != null && existing.existsSync()) {
      existing.deleteSync(recursive: true);
    }
  }

  void newTemp() {
    wipeTemp();
    tempDir = Directory.systemTemp.createTempSync('debt_tracker_payment');
  }

  /// Closes whatever is open and points the app at an empty folder.
  Future<void> freshDb() async {
    await DatabaseHelper.instance.close();
    newTemp();
    DatabaseHelper.databasePathOverride = dbPath();
  }

  Future<int> seedPerson([String name = 'سارة']) =>
      PersonDao().insertPerson(Person(name: name, createdAt: '', updatedAt: ''));

  Future<Transaction> seedTxn({
    required int personId,
    int? projectId,
    double amount = 100,
    TransactionType type = TransactionType.theyOweMe,
    bool isSettled = false,
    DateTime? settledAt,
    String date = '2026-01-01T10:00:00.000',
    String? note,
  }) async {
    final id = await TransactionDao().insertTransaction(
      Transaction(
        personId: personId,
        projectId: projectId,
        amount: amount,
        type: type,
        note: note,
        date: date,
        createdAt: date,
        isSettled: isSettled,
        settledAt: settledAt,
      ),
    );
    return (await TransactionDao().getTransaction(id))!;
  }

  Future<Transaction> reload(int id) async =>
      (await TransactionDao().getTransaction(id))!;

  // `DateFormatter` builds its formats against `ar_EG`, which the test VM
  // does not load on its own.
  setUpAll(() => initializeDateFormatting('ar_EG'));

  setUp(freshDb);

  tearDown(() async {
    await DatabaseHelper.instance.close();
    wipeTemp();
    tempDir = null;
  });

  group('migration 4 -> 5', () {
    test('gives every settled row one full payment and leaves the rest alone',
        () async {
      sqfliteFfiInit();
      final oldDb = await databaseFactoryFfi.openDatabase(
        dbPath(),
        options: OpenDatabaseOptions(
          version: 4,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE persons (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                is_pinned INTEGER NOT NULL DEFAULT 0,
                pin_order INTEGER NULL,
                is_archived INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE transactions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                person_id INTEGER NOT NULL REFERENCES persons(id) ON DELETE CASCADE,
                project_id INTEGER NULL,
                amount REAL NOT NULL CHECK (amount > 0),
                type TEXT NOT NULL CHECK (type IN ('they_owe_me', 'i_owe_them')),
                note TEXT NULL,
                date TEXT NOT NULL,
                created_at TEXT NOT NULL,
                is_settled INTEGER NOT NULL DEFAULT 0,
                settled_at TEXT NULL
              )
            ''');
          },
        ),
      );
      await oldDb.insert('persons', {
        'name': 'أحمد',
        'created_at': '2026-01-01',
        'updated_at': '2026-01-01',
      });
      Future<void> insertTxn(Map<String, Object?> values) =>
          oldDb.insert('transactions', {
            'person_id': 1,
            'created_at': '2025-06-01T09:00:00.000',
            ...values,
          });

      // Settled with a settlement date -> payment dated when it landed.
      await insertTxn({
        'amount': 250.0,
        'type': 'they_owe_me',
        'note': 'مسدَّدة بتاريخ',
        'date': '2025-06-01T09:00:00.000',
        'is_settled': 1,
        'settled_at': '2025-07-01T09:00:00.000',
      });
      // Settled without a settlement date -> payment falls back to the date.
      await insertTxn({
        'amount': 80.0,
        'type': 'i_owe_them',
        'note': 'مسدَّدة بلا تاريخ',
        'date': '2025-06-02T09:00:00.000',
        'is_settled': 1,
      });
      // Never settled -> no payments at all.
      await insertTxn({
        'amount': 45.0,
        'type': 'they_owe_me',
        'note': 'مفتوحة',
        'date': '2025-06-03T09:00:00.000',
        'is_settled': 0,
      });
      await oldDb.close();

      final db = await DatabaseHelper.instance.database;

      final columns = await db.rawQuery('PRAGMA table_info(transactions)');
      final names = {for (final c in columns) c['name'] as String};
      expect(names, isNot(contains('allow_partial')));

      final payments = await db.query(
        'transaction_payments',
        orderBy: 'transaction_id',
      );
      expect(payments, hasLength(2),
          reason: 'only the two settled rows get history');
      expect(payments[0]['amount'], 250.0);
      expect(payments[0]['date'], '2025-07-01T09:00:00.000');
      expect(payments[1]['amount'], 80.0);
      expect(payments[1]['date'], '2025-06-02T09:00:00.000');

      // `paid = SUM(payments)` now holds for the migrated data.
      final dao = PaymentDao();
      expect(await dao.sumPaid(payments[0]['transaction_id'] as int), 250.0);
      expect(await dao.sumPaid(payments[1]['transaction_id'] as int), 80.0);
      expect(await dao.sumPaid(3), 0.0);
    });
  });

  group('derived status', () {
    test('moves unsettled -> partially paid -> settled and back', () async {
      final personId = await seedPerson();
      final dao = PaymentDao();
      final txn = await seedTxn(personId: personId, amount: 100);

      expect(txn.isSettled, isFalse);
      expect(txn.settledAt, isNull);

      await dao.addPayment(transactionId: txn.id!, amount: 40, date: '2026-02-01');
      var after = await reload(txn.id!);
      expect(after.isSettled, isFalse, reason: 'a part payment is not settled');
      expect(after.settledAt, isNull);
      expect(await dao.sumPaid(txn.id!), 40);

      // The "سدّد المتبقي" shortcut: everything that is still open.
      await dao.addPayment(
        transactionId: txn.id!,
        amount: outstandingOf(after, 40),
        date: '2026-03-01',
      );
      after = await reload(txn.id!);
      expect(after.isSettled, isTrue, reason: 'reaching the full amount closes it');
      expect(after.settledAt, isNotNull);
      expect(await dao.sumPaid(txn.id!), 100);

      final payments = await dao.getPaymentsForTransaction(txn.id!);
      await dao.deletePayment(payments.first.id!);
      after = await reload(txn.id!);
      expect(after.isSettled, isFalse, reason: 'removing a payment reopens it');
      expect(after.settledAt, isNull);
      expect(await dao.sumPaid(txn.id!), 40);
    });

    test('settling an unpaid row in one step closes it instantly', () async {
      final personId = await seedPerson();
      final dao = PaymentDao();
      final txn = await seedTxn(personId: personId, amount: 100);

      await dao.addPayment(
        transactionId: txn.id!,
        amount: txn.amount,
        date: '2026-02-01',
      );

      final after = await reload(txn.id!);
      expect(after.isSettled, isTrue);
      expect(await dao.sumPaid(txn.id!), 100);
      expect(outstandingOf(after, 100), 0);
    });

    test('un-settling wipes the history', () async {
      final personId = await seedPerson();
      final dao = PaymentDao();
      final txn = await seedTxn(personId: personId, amount: 100);
      await dao.addPayment(transactionId: txn.id!, amount: 30, date: '2026-02-01');
      await dao.addPayment(transactionId: txn.id!, amount: 70, date: '2026-03-01');
      expect((await reload(txn.id!)).isSettled, isTrue);

      await dao.clearPayments(txn.id!);

      final after = await reload(txn.id!);
      expect(after.isSettled, isFalse);
      expect(after.settledAt, isNull);
      expect(await dao.getPaymentsForTransaction(txn.id!), isEmpty);
      expect(await dao.sumPaid(txn.id!), 0);
    });

    test('an edit re-saves its own amount without hitting the ceiling',
        () async {
      final personId = await seedPerson();
      final dao = PaymentDao();
      final txn = await seedTxn(personId: personId, amount: 100);
      await dao.addPayment(transactionId: txn.id!, amount: 40, date: '2026-02-01');
      final payment = (await dao.getPaymentsForTransaction(txn.id!)).single;

      await dao.updatePayment(payment, amount: 40, date: '2026-02-05');

      expect(await dao.sumPaid(txn.id!), 40);
      expect((await dao.getPaymentsForTransaction(txn.id!)).single.date,
          '2026-02-05');
      expect((await reload(txn.id!)).isSettled, isFalse);
    });
  });

  group('validation', () {
    test('rejects paying more than the transaction is worth', () async {
      final personId = await seedPerson();
      final dao = PaymentDao();
      final txn = await seedTxn(personId: personId, amount: 100);

      await dao.addPayment(transactionId: txn.id!, amount: 100, date: '2026-02-01');
      expect(
        () => dao.addPayment(transactionId: txn.id!, amount: 1, date: '2026-03-01'),
        throwsA(isA<PaymentValidationException>()),
      );
      expect(await dao.sumPaid(txn.id!), 100);
    });

    test('refuses to lower the amount below what was already paid', () async {
      final personId = await seedPerson();
      final dao = PaymentDao();
      final txn = await seedTxn(personId: personId, amount: 100);
      await dao.addPayment(transactionId: txn.id!, amount: 70, date: '2026-02-01');

      await expectLater(
        dao.ensureAmountCoversPaid(txn.id!, 60),
        throwsA(isA<PaymentValidationException>()),
      );
      await expectLater(dao.ensureAmountCoversPaid(txn.id!, 70), completes);
      await expectLater(dao.ensureAmountCoversPaid(txn.id!, 100), completes);
    });

    test('rejects a non-positive payment', () async {
      final personId = await seedPerson();
      final dao = PaymentDao();
      final txn = await seedTxn(personId: personId, amount: 100);

      expect(
        () => dao.addPayment(transactionId: txn.id!, amount: 0, date: '2026-02-01'),
        throwsA(isA<PaymentValidationException>()),
      );
    });

    test('a status that was hand-set but unpaid is corrected', () async {
      final personId = await seedPerson();
      final dao = PaymentDao();
      final txn = await seedTxn(personId: personId, amount: 100, isSettled: true);

      await dao.syncStatus(txn.id!);

      expect((await reload(txn.id!)).isSettled, isFalse,
          reason: 'the payment book wins over a stale flag');
    });
  });

  group('money queries', () {
    test('a balance only counts what is still outstanding', () async {
      final personId = await seedPerson();
      final dao = PaymentDao();
      final txn = await seedTxn(personId: personId, amount: 100);
      await dao.addPayment(transactionId: txn.id!, amount: 40, date: '2026-02-01');

      expect(await PersonDao().getPersonBalance(personId), 60);
      final totals = await PersonDao().getPersonTotals(personId);
      expect(totals['they_owe_me'], 60);

      await dao.addPayment(transactionId: txn.id!, amount: 60, date: '2026-03-01');
      expect(await PersonDao().getPersonBalance(personId), 0,
          reason: 'a settled row leaves the balance entirely');
    });

    test('the budget only counts the part that has actually landed', () async {
      final personId = await seedPerson();
      final dao = PaymentDao();
      final projectDao = ProjectDao();
      const budget = 1000.0;

      Future<int> project(String name) => projectDao.insertProject(
            Project(
              personId: personId,
              name: name,
              budget: budget,
              createdAt: '',
              updatedAt: '',
            ),
          );

      // A half-paid row contributes only its paid half.
      final partialProject = await project('جزئي');
      final partial = await seedTxn(
        personId: personId,
        projectId: partialProject,
        amount: 200,
        type: TransactionType.iOweThem,
      );
      await dao.addPayment(transactionId: partial.id!, amount: 50, date: '2026-02-01');
      expect(await projectDao.getBudgetRemaining(partialProject), budget + 50);

      // Paying the rest converges on the same number a settled row gives.
      await dao.addPayment(transactionId: partial.id!, amount: 150, date: '2026-03-01');
      expect(await projectDao.getBudgetRemaining(partialProject), budget + 200);

      // A row with no history contributes nothing.
      final openProject = await project('مفتوح');
      await seedTxn(
        personId: personId,
        projectId: openProject,
        amount: 200,
        type: TransactionType.iOweThem,
      );
      expect(await projectDao.getBudgetRemaining(openProject), budget);
    });
  });

  group('export / import', () {
    Future<Map<String, dynamic>> seedRoundTripData() async {
      final personId = await seedPerson('سارة');
      final dao = PaymentDao();
      final partial = await seedTxn(
        personId: personId,
        amount: 100,
        note: 'كرسي',
        date: '2026-01-05T10:00:00.000',
      );
      await dao.addPayment(transactionId: partial.id!, amount: 40, date: '2026-01-10');
      await dao.addPayment(transactionId: partial.id!, amount: 30, date: '2026-01-20');
      // A settled row, exported as one full payment.
      final settled = await seedTxn(
        personId: personId,
        amount: 25,
        note: 'قهوة',
        date: '2026-01-06T10:00:00.000',
      );
      await dao.addPayment(
        transactionId: settled.id!,
        amount: 25,
        date: '2026-01-07T10:00:00.000',
      );
      return ExportService.instance.buildFullExportData();
    }

    Map<String, dynamic> txnNote(Map<String, dynamic> data, String note) {
      final persons = data['persons'] as List;
      final withoutProject =
          (persons.first as Map)['transactions_without_project'] as List;
      return withoutProject
          .map((row) => (row as Map).cast<String, dynamic>())
          .singleWhere((row) => row['note'] == note);
    }

    test('the payload carries the payments', () async {
      await seedRoundTripData();
      final data = await ExportService.instance.buildFullExportData();

      expect(data['export_version'], 1);
      final partial = txnNote(data, 'كرسي');
      expect(partial['payments'], hasLength(2));
      expect((partial['payments'] as List).first.keys.toSet(),
          {'amount', 'date', 'note'});
      expect(txnNote(data, 'قهوة')['payments'], hasLength(1));
    });

    test('restoring into the same device adds nothing twice', () async {
      await seedRoundTripData();
      final json = jsonEncode(await ExportService.instance.buildFullExportData());

      await ImportService.instance.importFromJsonString(json);

      final db = await DatabaseHelper.instance.database;
      expect(await db.query('transactions'), hasLength(2));
      expect(await db.query('transaction_payments'), hasLength(3),
          reason: 'identical installments are recognised as already present');
      final rows =
          await db.query('transactions', where: 'note = ?', whereArgs: ['كرسي']);
      expect(rows.single['is_settled'], 0);
    });

    test('restoring into an empty device rebuilds the whole story', () async {
      final json = jsonEncode(await seedRoundTripData());

      await DatabaseHelper.instance.close();
      newTemp();
      DatabaseHelper.databasePathOverride = dbPath();

      await ImportService.instance.importFromJsonString(json);

      final db = await DatabaseHelper.instance.database;
      expect(await db.query('persons'), hasLength(1));
      expect(await db.query('transactions'), hasLength(2));
      expect(await db.query('transaction_payments'), hasLength(3));

      final partial = (await db.query('transactions',
              where: 'note = ?', whereArgs: ['كرسي']))
          .single;
      expect(partial['is_settled'], 0);
      expect(await PaymentDao().sumPaid(partial['id'] as int), 70);

      final settled = (await db.query('transactions',
              where: 'note = ?', whereArgs: ['قهوة']))
          .single;
      expect(settled['is_settled'], 1);
      expect(await PaymentDao().sumPaid(settled['id'] as int), 25);
    });

    test('a v1 file settles a marked row with one full payment', () async {
      await seedPerson('قديم');
      final legacy = jsonEncode({
        'export_version': 1,
        'persons': [
          {
            'name': 'قديم',
            'projects': <Map<String, dynamic>>[],
            'transactions_without_project': [
              {
                'amount': 90,
                'type': 'they_owe_me',
                'note': 'قبل التحديث',
                'date': '2025-01-01T10:00:00.000',
                'is_settled': 1,
              },
              {
                'amount': 40,
                'type': 'i_owe_them',
                'note': 'مفتوحة قديمة',
                'date': '2025-01-02T10:00:00.000',
                'is_settled': 0,
              },
            ],
          },
        ],
      });

      await ImportService.instance.importFromJsonString(legacy);

      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('transactions', orderBy: 'id');
      expect(rows, hasLength(2));

      final settledRow =
          rows.firstWhere((row) => row['note'] == 'قبل التحديث');
      expect(settledRow['is_settled'], 1);
      expect(await PaymentDao().sumPaid(settledRow['id'] as int), 90,
          reason: 'a settled v1 row becomes one full payment');

      final payments = await db.query(
        'transaction_payments',
        where: 'transaction_id = ?',
        whereArgs: [settledRow['id']],
      );
      expect(payments.single['date'], '2025-01-01T10:00:00.000',
          reason: 'dated with the transaction, as the migration did');

      final openRow = rows.firstWhere((row) => row['note'] == 'مفتوحة قديمة');
      expect(openRow['is_settled'], 0);
      expect(await PaymentDao().sumPaid(openRow['id'] as int), 0);
    });
  });
}
