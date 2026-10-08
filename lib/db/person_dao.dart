import 'package:sqflite_common/sqlite_api.dart';
import 'package:flutter/foundation.dart';
import '../models/person.dart';
import 'db_helper.dart';
import 'payment_sql.dart';

class PersonDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<Database> get _db => _dbHelper.database;

  Future<int> insertPerson(Person person) async {
    final db = await _db;
    return insertPersonOn(db, person);
  }

  /// Same insert, but into an already open `db.transaction` — lets a caller
  /// make the person and its first transaction one atomic unit.
  Future<int> insertPersonOn(DatabaseExecutor db, Person person) async {
    return db.insert('persons', person.toMapForInsert());
  }

  Future<int> updatePerson(Person person) async {
    final db = await _db;
    return db.update(
      'persons',
      person.toMapForUpdate(),
      where: 'id = ?',
      whereArgs: [person.id],
    );
  }

  Future<int> deletePerson(int id) async {
    final db = await _db;
    return db.delete('persons', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> togglePin(int id, bool isPinned) async {
    final db = await _db;
    int newPinOrder = 0;
    if (isPinned) {
      final maxOrderResult = await db.rawQuery(
        'SELECT MAX(pin_order) as max_order FROM persons WHERE is_pinned = 1',
      );
      newPinOrder = (maxOrderResult.first['max_order'] as int? ?? 0) + 1;
    }
    return db.update(
      'persons',
      {
        'is_pinned': isPinned ? 1 : 0,
        'pin_order': isPinned ? newPinOrder : null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updatePinOrder(int id, int pinOrder) async {
    final db = await _db;
    return db.update(
      'persons',
      {'pin_order': pinOrder, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updatePinOrdersBatch(List<Map<String, dynamic>> updates) async {
    final db = await _db;
    final batch = db.batch();
    for (final update in updates) {
      batch.update(
        'persons',
        {
          'pin_order': update['pin_order'],
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [update['id']],
      );
    }
    await batch.commit(noResult: true);
    return 1;
  }

  Future<Person?> getPerson(int id) async {
    final db = await _db;
    final maps = await db.query(
      'persons',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Person.fromMap(maps.first);
  }

  Future<List<Person>> getAllPersons({bool includeArchived = false}) async {
    final db = await _db;
    final where = includeArchived ? '' : 'WHERE p.is_archived = 0';
    final maps = await db.rawQuery(
      _personsListSql('''
      $where
    '''),
    );
    return maps.map((map) => Person.fromMap(map)).toList();
  }

  Future<List<Person>> getActivePersons() async {
    final db = await _db;
    final maps = await db.rawQuery(
      _personsListSql('''
      WHERE p.is_archived = 0
    '''),
    );
    return maps.map((map) => Person.fromMap(map)).toList();
  }

  /// Person list ordering:
  ///
  ///  1. pinned first, in the order the user dragged them (`pin_order`);
  ///  2. then everyone else by *last activity* — whichever is more recent
  ///     between creating the person and creating one of their transactions.
  ///     A brand-new person therefore outranks people whose only activity is
  ///     older, and adding a transaction bumps that person to the top.
  ///
  /// Ties fall back to `id DESC` (newest row first) so the order is stable.
  static String _personsListSql(String where) =>
      '''
      SELECT p.*,
             CASE WHEN t.last_txn_created > p.created_at THEN t.last_txn_created
                  ELSE p.created_at END AS last_activity
      FROM persons p
      LEFT JOIN (
        SELECT person_id, MAX(created_at) AS last_txn_created
        FROM transactions
        GROUP BY person_id
      ) t ON p.id = t.person_id
      $where
      ORDER BY p.is_pinned DESC, p.pin_order ASC, last_activity DESC, p.id DESC
    ''';

  Future<List<Person>> getArchivedPersons() async {
    final db = await _db;
    final maps = await db.query(
      'persons',
      where: 'is_archived = 1',
      orderBy: 'updated_at DESC',
    );
    return maps.map((map) => Person.fromMap(map)).toList();
  }

  Future<int> archivePerson(int id) async {
    final db = await _db;
    return db.update(
      'persons',
      {'is_archived': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> unarchivePerson(int id) async {
    final db = await _db;
    await db.transaction((txn) async {
      // First unarchive the person
      await txn.update(
        'persons',
        {'is_archived': 0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
      // Then unarchive all their projects
      await txn.update(
        'projects',
        {'is_archived': 0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'person_id = ?',
        whereArgs: [id],
      );
    });
    return 1;
  }

  Future<int> permanentlyDeletePerson(
    int id,
    Future<void> Function(String) deleteFile,
  ) async {
    final db = await _db;
    final paths = <String>[];
    final rows = await db.transaction((txn) async {
      final attachments = await txn.rawQuery(
        '''
        SELECT a.file_path
        FROM transaction_attachments a
        JOIN transactions t ON t.id = a.transaction_id
        WHERE t.person_id = ?
      ''',
        [id],
      );
      paths.addAll(attachments.map((row) => row['file_path'] as String));
      await txn.rawDelete(
        '''
        DELETE FROM transaction_attachments
        WHERE transaction_id IN (SELECT id FROM transactions WHERE person_id = ?)
      ''',
        [id],
      );
      await txn.rawDelete('DELETE FROM transactions WHERE person_id = ?', [id]);
      await txn.rawDelete(
        '''
        DELETE FROM projects WHERE person_id = ?
      ''',
        [id],
      );
      return txn.rawDelete('DELETE FROM persons WHERE id = ?', [id]);
    });
    debugPrint('[PersonDao] permanentlyDeletePerson id=$id rows=$rows');
    for (final path in paths) {
      await deleteFile(path);
    }
    return rows;
  }

  /// Unsettled balance only (rule 3): settled rows are money already
  /// received/paid, so they no longer count as outstanding.
  ///
  /// A partially-paid installment contributes only what is left of it.
  ///
  /// [startDate] / [endDate] are optional ISO-8601 bounds (inclusive) so a
  /// range report can reuse this exact rule instead of re-deriving it.
  Future<double> getPersonBalance(
    int personId, {
    String? startDate,
    String? endDate,
  }) async {
    final db = await _db;
    final result = await db.rawQuery(
      '''
      SELECT
        SUM(CASE WHEN type = 'they_owe_me' THEN ${PaymentSql.outstanding('t')} ELSE 0 END) as they_owe_me,
        SUM(CASE WHEN type = 'i_owe_them' THEN ${PaymentSql.outstanding('t')} ELSE 0 END) as i_owe_them
      FROM transactions t
      ${PaymentSql.join('t')}
      LEFT JOIN projects p ON t.project_id = p.id
      WHERE ${_unsettledScope('t.person_id', startDate, endDate)}
        AND (t.project_id IS NULL OR p.is_archived = 0)
    ''',
      [personId, ..._scopeArgs(startDate, endDate)],
    );

    final row = result.first;
    final theyOweMe = (row['they_owe_me'] as num?)?.toDouble() ?? 0.0;
    final iOweThem = (row['i_owe_them'] as num?)?.toDouble() ?? 0.0;
    return theyOweMe - iOweThem;
  }

  /// Unsettled totals (they_owe_me / i_owe_them), for the balance cards.
  Future<Map<String, double>> getPersonTotals(
    int personId, {
    String? startDate,
    String? endDate,
  }) async {
    final db = await _db;
    final result = await db.rawQuery(
      '''
      SELECT
        SUM(CASE WHEN type = 'they_owe_me' THEN ${PaymentSql.outstanding('t')} ELSE 0 END) as they_owe_me,
        SUM(CASE WHEN type = 'i_owe_them' THEN ${PaymentSql.outstanding('t')} ELSE 0 END) as i_owe_them
      FROM transactions t
      ${PaymentSql.join('t')}
      LEFT JOIN projects p ON t.project_id = p.id
      WHERE ${_unsettledScope('t.person_id', startDate, endDate)}
        AND (t.project_id IS NULL OR p.is_archived = 0)
    ''',
      [personId, ..._scopeArgs(startDate, endDate)],
    );

    final row = result.first;
    return {
      'they_owe_me': (row['they_owe_me'] as num?)?.toDouble() ?? 0.0,
      'i_owe_them': (row['i_owe_them'] as num?)?.toDouble() ?? 0.0,
    };
  }

  /// `column = ?` plus `is_settled = 0` and any inclusive date bounds.
  static String _unsettledScope(
    String column,
    String? startDate,
    String? endDate,
  ) {
    final parts = <String>['$column = ?', 'is_settled = 0'];
    if (startDate != null) parts.add('date >= ?');
    if (endDate != null) parts.add('date <= ?');
    return parts.join(' AND ');
  }

  static List<Object?> _scopeArgs(String? startDate, String? endDate) => [
    ?startDate,
    ?endDate,
  ];

  /// Signed settled total: they_owe_me positive, i_owe_them negative.
  /// Shown as the secondary "مسدَّد: X" figure.
  Future<double> getPersonSettledTotal(int personId) async {
    final db = await _db;
    final result = await db.rawQuery(
      '''
      SELECT
        SUM(CASE WHEN type = 'they_owe_me' THEN amount ELSE 0 END) as they_owe_me,
        SUM(CASE WHEN type = 'i_owe_them' THEN amount ELSE 0 END) as i_owe_them
      FROM transactions t
      LEFT JOIN projects p ON t.project_id = p.id
      WHERE t.person_id = ? AND t.is_settled = 1
        AND (t.project_id IS NULL OR p.is_archived = 0)
    ''',
      [personId],
    );

    final row = result.first;
    final theyOweMe = (row['they_owe_me'] as num?)?.toDouble() ?? 0.0;
    final iOweThem = (row['i_owe_them'] as num?)?.toDouble() ?? 0.0;
    return theyOweMe - iOweThem;
  }

  Future<DateTime?> getLastTransactionDate(int personId) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT MAX(date) as max_date FROM transactions WHERE person_id = ?',
      [personId],
    );
    final maxDateStr = result.first['max_date'] as String?;
    if (maxDateStr == null) return null;
    return DateTime.parse(maxDateStr).toLocal();
  }
}
