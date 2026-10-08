import 'package:sqflite_common/sqlite_api.dart' hide Transaction;

import '../db/db_helper.dart';
import '../db/payment_dao.dart';
import '../models/transaction.dart';

/// The one place a transaction row is born.
///
/// Two screens create transactions: the Add Transaction sheet (through the
/// person-detail notifier) and the "أول معاملة" section of Add Person. Both
/// call [create], so validation, the row that gets written and the payment
/// that settles it are decided in one place instead of two.
///
/// A transaction born with `isSettled = true` also gets the single payment
/// that makes it settled — the payment book is what derives the status, so
/// a bare flag would be immediately re-derived away.
class TransactionCreator {
  TransactionCreator({PaymentDao? payments}) : _payments = payments ?? PaymentDao();

  final PaymentDao _payments;

  /// Writes [transaction] and returns its id.
  ///
  /// Pass [db] to join a `db.transaction` the caller already opened; without
  /// it the row lives in its own transaction. Throws
  /// [PaymentValidationException] with Arabic text when the amount is not a
  /// positive number, so a bad row never reaches the schema's own CHECK.
  Future<int> create(Transaction transaction, {DatabaseExecutor? db}) async {
    if (transaction.amount <= 0) {
      throw PaymentValidationException('أدخل مبلغ أكبر من صفر');
    }
    if (db != null) return _createOn(db, transaction);

    final database = await DatabaseHelper.instance.database;
    return database.transaction((txn) => _createOn(txn, transaction));
  }

  Future<int> _createOn(DatabaseExecutor db, Transaction transaction) async {
    final id = await db.insert('transactions', transaction.toMapForInsert());

    if (transaction.isSettled) {
      final at = transaction.settledAt ?? DateTime.now();
      await _payments.addPaymentOn(
        db,
        transactionId: id,
        amount: transaction.amount,
        date: at.toIso8601String(),
      );
    }
    return id;
  }
}
