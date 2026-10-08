import 'package:sqflite_common/sqlite_api.dart';
import '../models/transaction_payment.dart';
import '../utils/currency_formatter.dart';
import 'db_helper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final paymentDaoProvider = Provider<PaymentDao>((ref) {
  return PaymentDao();
});

/// Thrown whenever a payment (or an edit of the parent amount) would leave
/// the installment book inconsistent. Carries the Arabic text shown to the
/// user verbatim, so callers never have to rewrite it.
class PaymentValidationException implements Exception {
  PaymentValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// CRUD for installments plus the one place a transaction's `is_settled` flag
/// is re-derived — from `SUM(payments.amount)` and nothing else.
///
/// Every mutating call runs inside a single `db.transaction`: the payment row
/// and the parent's status always move together, so a crash can never leave a
/// fully-paid transaction looking unpaid (or the other way around).
class PaymentDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<Database> get _db => _dbHelper.database;

  /// History for one transaction, newest first.
  Future<List<TransactionPayment>> getPaymentsForTransaction(
    int transactionId,
  ) async {
    final db = await _db;
    final maps = await db.query(
      'transaction_payments',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
      orderBy: 'date DESC, id DESC',
    );
    return maps.map(TransactionPayment.fromMap).toList();
  }

  /// One query for a whole list, so a transaction screen does not fire a
  /// round trip per row. Result is keyed by transaction id.
  Future<Map<int, List<TransactionPayment>>> getPaymentsForTransactions(
    List<int> transactionIds,
  ) async {
    if (transactionIds.isEmpty) return const {};
    final db = await _db;
    final placeholders = List.filled(transactionIds.length, '?').join(',');
    final maps = await db.query(
      'transaction_payments',
      where: 'transaction_id IN ($placeholders)',
      whereArgs: transactionIds,
      orderBy: 'date DESC, id DESC',
    );

    final result = <int, List<TransactionPayment>>{};
    for (final map in maps) {
      final payment = TransactionPayment.fromMap(map);
      result.putIfAbsent(payment.transactionId, () => []).add(payment);
    }
    return result;
  }

  /// Sum of every installment on [transactionId] (0 when there are none).
  Future<double> sumPaid(int transactionId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT IFNULL(SUM(amount), 0) AS paid FROM transaction_payments '
      'WHERE transaction_id = ?',
      [transactionId],
    );
    return (rows.first['paid'] as num?)?.toDouble() ?? 0.0;
  }

  // ------------------------------------------------------------- mutations

  /// Adds an installment. [amount] may not exceed what is still outstanding.
  Future<void> addPayment({
    required int transactionId,
    required double amount,
    required String date,
    String? note,
  }) async {
    final db = await _db;
    await db.transaction(
      (txn) => addPaymentOn(
        txn,
        transactionId: transactionId,
        amount: amount,
        date: date,
        note: note,
      ),
    );
  }

  /// Same installment insert, but into an already open `db.transaction` — so
  /// a caller can create a transaction and settle it in one atomic unit.
  Future<void> addPaymentOn(
    DatabaseExecutor db, {
    required int transactionId,
    required double amount,
    required String date,
    String? note,
  }) async {
    final parent = await _requireParent(db, transactionId);
    final paid = await _sumPaidOn(db, transactionId);
    _validate(amount, parent.amount - paid);
    await db.insert('transaction_payments', {
      'transaction_id': transactionId,
      'amount': amount,
      'date': date,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _syncStatus(db, transactionId, parent);
  }

  /// Edits an installment in place. The ceiling is what is still outstanding
  /// *plus this row's own old amount*, so a payment can be re-saved unchanged.
  Future<void> updatePayment(
    TransactionPayment old, {
    required double amount,
    required String date,
    String? note,
  }) async {
    final id = old.id;
    if (id == null) {
      throw PaymentValidationException('دفعة غير موجودة');
    }
    final db = await _db;
    await db.transaction((txn) async {
      final parent = await _requireParent(txn, old.transactionId);
      final paid = await _sumPaidOn(txn, old.transactionId);
      _validate(amount, parent.amount - (paid - old.amount));
      await txn.update(
        'transaction_payments',
        {'amount': amount, 'date': date, 'note': note},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _syncStatus(txn, old.transactionId, parent);
    });
  }

  Future<void> deletePayment(int paymentId) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'transaction_payments',
        where: 'id = ?',
        whereArgs: [paymentId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final transactionId = rows.first['transaction_id'] as int;
      final parent = await _requireParent(txn, transactionId);
      await txn.delete(
        'transaction_payments',
        where: 'id = ?',
        whereArgs: [paymentId],
      );
      await _syncStatus(txn, transactionId, parent);
    });
  }

  /// The "un-settle" action: wipes the payment history and lets
  /// [_syncStatus] drop the row back to unsettled.
  ///
  /// Callers own the confirmation dialog — this only does the work.
  Future<void> clearPayments(int transactionId) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      await txn.delete(
        'transaction_payments',
        where: 'transaction_id = ?',
        whereArgs: [transactionId],
      );
      await _syncStatus(txn, transactionId, _Parent.from(rows.first));
    });
  }

  /// Recomputes `is_settled` / `settled_at` from the payment history.
  ///
  /// Called after anything that can move the ceiling without touching a
  /// payment (e.g. lowering the transaction amount).
  Future<void> syncStatus(int transactionId) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      await _syncStatus(txn, transactionId, _Parent.from(rows.first));
    });
  }

  /// Blocks an amount edit that would fall below what has already been paid.
  Future<void> ensureAmountCoversPaid(int transactionId, double newAmount) async {
    final db = await _db;
    final rows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final paid = await sumPaid(transactionId);
    if (newAmount + 1e-9 < paid) {
      throw PaymentValidationException(
        'لا يمكن خفض المبلغ إلى ${CurrencyFormatter.format(newAmount)} '
        'لأنه مدفع منه بالفعل ${CurrencyFormatter.format(paid)}. '
        'المبلغ الجديد يجب ألا يقل عن المدفوع.',
      );
    }
  }

  // -------------------------------------------------------------- internals

  /// `paid == 0` unsettled, `0 < paid < amount` partially paid,
  /// `paid >= amount` settled. The user never sets this by hand.
  Future<void> _syncStatus(
    DatabaseExecutor db,
    int transactionId,
    _Parent parent,
  ) async {
    final paid = await _sumPaidOn(db, transactionId);
    final settled = paid >= parent.amount - 1e-9;
    await db.update(
      'transactions',
      {
        'is_settled': settled ? 1 : 0,
        'settled_at': settled
            ? (parent.settledAt ?? DateTime.now().toIso8601String())
            : null,
      },
      where: 'id = ?',
      whereArgs: [transactionId],
    );
  }

  Future<double> _sumPaidOn(DatabaseExecutor db, int transactionId) async {
    final rows = await db.rawQuery(
      'SELECT IFNULL(SUM(amount), 0) AS paid FROM transaction_payments '
      'WHERE transaction_id = ?',
      [transactionId],
    );
    return (rows.first['paid'] as num?)?.toDouble() ?? 0.0;
  }

  /// Loads the parent row, or throws when the transaction has been deleted
  /// out from under a payment.
  Future<_Parent> _requireParent(
    DatabaseExecutor db,
    int transactionId,
  ) async {
    final rows = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw PaymentValidationException('المعاملة غير موجودة');
    }
    return _Parent.from(rows.first);
  }

  void _validate(double amount, double maxAllowed) {
    if (amount <= 0) {
      throw PaymentValidationException('مبلغ الدفعة يجب أن يكون أكبر من صفر');
    }
    if (amount > maxAllowed + 1e-9) {
      throw PaymentValidationException(
        'مبلغ الدفعة ${CurrencyFormatter.format(amount)} يتجاوز المتبقي '
        '${CurrencyFormatter.format(maxAllowed < 0 ? 0 : maxAllowed)}',
      );
    }
  }
}

class _Parent {
  const _Parent({required this.amount, required this.settledAt});

  final double amount;
  final String? settledAt;

  factory _Parent.from(Map<String, dynamic> row) {
    final settledAtRaw = row['settled_at'];
    return _Parent(
      amount: (row['amount'] as num).toDouble(),
      settledAt: settledAtRaw is String ? settledAtRaw : null,
    );
  }
}
