import 'package:sqflite_common/sqlite_api.dart';
import '../models/transaction.dart' as txn_model;
import 'db_helper.dart';

class TransactionDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<Database> get _db => _dbHelper.database;

  Future<int> insertTransaction(txn_model.Transaction transaction) async {
    final db = await _db;
    final id = await db.insert('transactions', transaction.toMapForInsert());
    return id;
  }

  Future<int> updateTransaction(txn_model.Transaction oldTransaction, txn_model.Transaction newTransaction) async {
    final db = await _db;
    final result = await db.update(
      'transactions',
      newTransaction.toMapForUpdate(),
      where: 'id = ?',
      whereArgs: [oldTransaction.id],
    );

    return result;
  }

  Future<int> deleteTransaction(int id) async {
    final db = await _db;

    return db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<txn_model.Transaction?> getTransaction(int id) async {
    final db = await _db;
    final maps = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return txn_model.Transaction.fromMap(maps.first);
  }

  Future<List<txn_model.Transaction>> getTransactionsForPerson(
    int personId, {
    int? projectId,
    String? startDate,
    String? endDate,
    txn_model.TransactionType? type,
  }) async {
    final db = await _db;
    final whereClauses = <String>['t.person_id = ?'];
    final whereArgs = <dynamic>[personId];

    if (projectId != null) {
      whereClauses.add('t.project_id = ?');
      whereArgs.add(projectId);
    }

    if (startDate != null) {
      whereClauses.add('t.date >= ?');
      whereArgs.add(startDate);
    }

    if (endDate != null) {
      whereClauses.add('t.date <= ?');
      whereArgs.add(endDate);
    }

    if (type != null) {
      whereClauses.add('t.type = ?');
      whereArgs.add(type.value);
    }

    // Filter out archived projects when no specific project is selected
    if (projectId == null) {
      whereClauses.add('(t.project_id IS NULL OR p.is_archived = 0)');
    }

    final maps = await db.rawQuery('''
      SELECT t.*
      FROM transactions t
      LEFT JOIN projects p ON t.project_id = p.id
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY t.created_at DESC, t.id DESC
    ''', whereArgs);
    return maps.map((map) => txn_model.Transaction.fromMap(map)).toList();
  }

  Future<List<txn_model.Transaction>> getTransactionsForProject(
    int projectId, {
    String? startDate,
    String? endDate,
    txn_model.TransactionType? type,
  }) async {
    final db = await _db;
    final whereClauses = <String>['t.project_id = ?'];
    final whereArgs = <dynamic>[projectId];

    if (startDate != null) {
      whereClauses.add('t.date >= ?');
      whereArgs.add(startDate);
    }

    if (endDate != null) {
      whereClauses.add('t.date <= ?');
      whereArgs.add(endDate);
    }

    if (type != null) {
      whereClauses.add('t.type = ?');
      whereArgs.add(type.value);
    }

    final maps = await db.rawQuery('''
      SELECT t.*
      FROM transactions t
      WHERE ${whereClauses.join(' AND ')}
      ORDER BY t.created_at DESC, t.id DESC
    ''', whereArgs);
    return maps.map((map) => txn_model.Transaction.fromMap(map)).toList();
  }

  Future<List<txn_model.Transaction>> getAllTransactionsForPerson(int personId) async {
    final db = await _db;
    final maps = await db.rawQuery('''
      SELECT t.*
      FROM transactions t
      LEFT JOIN projects p ON t.project_id = p.id
      WHERE t.person_id = ? AND (t.project_id IS NULL OR p.is_archived = 0)
      ORDER BY t.created_at DESC, t.id DESC
    ''', [personId]);
    return maps.map((map) => txn_model.Transaction.fromMap(map)).toList();
  }

  Future<List<txn_model.Transaction>> getTransactionsWithoutProject(int personId) async {
    final db = await _db;
    final maps = await db.query(
      'transactions',
      where: 'person_id = ? AND project_id IS NULL',
      whereArgs: [personId],
      orderBy: 'created_at DESC, id DESC',
    );
    return maps.map((map) => txn_model.Transaction.fromMap(map)).toList();
  }
}