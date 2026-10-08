import 'package:sqflite_common/sqlite_api.dart';
import 'package:flutter/foundation.dart';
import '../models/project.dart';
import 'db_helper.dart';
import 'payment_sql.dart';

class ProjectDao {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<Database> get _db => _dbHelper.database;

  Future<int> insertProject(Project project) async {
    final db = await _db;
    return db.insert('projects', project.toMapForInsert());
  }

  Future<int> updateProject(Project project) async {
    final db = await _db;
    return db.update(
      'projects',
      project.toMapForUpdate(),
      where: 'id = ?',
      whereArgs: [project.id],
    );
  }

  Future<int> deleteProject(int id) async {
    final db = await _db;
    return db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  Future<Project?> getProject(int id) async {
    final db = await _db;
    final maps = await db.query(
      'projects',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Project.fromMap(maps.first);
  }

  Future<List<Project>> getProjectsForPerson(
    int personId, {
    bool includeArchived = false,
  }) async {
    final db = await _db;
    final where = includeArchived
        ? 'person_id = ?'
        : 'person_id = ? AND is_archived = 0';
    final maps = await db.query(
      'projects',
      where: where,
      whereArgs: [personId],
      orderBy: 'created_at DESC',
    );
    return maps.map((map) => Project.fromMap(map)).toList();
  }

  Future<List<Project>> getActiveProjectsForPerson(int personId) async {
    return getProjectsForPerson(personId, includeArchived: false);
  }

  Future<List<Map<String, dynamic>>> getArchivedProjects() async {
    final db = await _db;
    return db.rawQuery('''
      SELECT p.*, pe.name as person_name
      FROM projects p
      JOIN persons pe ON p.person_id = pe.id
      WHERE p.is_archived = 1
      ORDER BY p.updated_at DESC
    ''');
  }

  Future<int> archiveProject(int id) async {
    final db = await _db;
    return db.update(
      'projects',
      {'is_archived': 1, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> unarchiveProject(int id) async {
    final db = await _db;
    final rows = await db.rawUpdate(
      'UPDATE projects SET is_archived = 0, updated_at = ? WHERE id = ?',
      [DateTime.now().toIso8601String(), id],
    );
    debugPrint('[ProjectDao] unarchiveProject id=$id rows=$rows');
    return rows;
  }

  /// Checks if the project's person is archived.
  Future<bool> isPersonArchived(int projectId) async {
    final db = await _db;
    final result = await db.rawQuery(
      '''
      SELECT pe.is_archived
      FROM projects p
      JOIN persons pe ON p.person_id = pe.id
      WHERE p.id = ?
    ''',
      [projectId],
    );
    if (result.isEmpty) return false;
    return (result.first['is_archived'] as int) == 1;
  }

  /// Permanently deletes a project and all its transactions and attachments.
  ///
  /// Order: (1) collect all attachment file paths for transactions with that
  /// project_id, (2) delete those files via [deleteFile], (3) delete attachment
  /// rows, (4) delete transactions, (5) delete the project. All DB steps run
  /// in a single transaction.
  Future<int> permanentlyDeleteProject(
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
        WHERE t.project_id = ?
      ''',
        [id],
      );
      paths.addAll(attachments.map((row) => row['file_path'] as String));
      await txn.rawDelete(
        '''
        DELETE FROM transaction_attachments
        WHERE transaction_id IN (SELECT id FROM transactions WHERE project_id = ?)
      ''',
        [id],
      );
      await txn.rawDelete('DELETE FROM transactions WHERE project_id = ?', [
        id,
      ]);
      return txn.rawDelete('DELETE FROM projects WHERE id = ?', [id]);
    });
    debugPrint('[ProjectDao] permanentlyDeleteProject id=$id rows=$rows');
    for (final path in paths) {
      await deleteFile(path);
    }
    return rows;
  }

  /// Unsettled balance only (rule 3).
  ///
  /// [startDate] / [endDate] are optional ISO-8601 bounds (inclusive) so a
  /// range report can reuse this exact rule instead of re-deriving it.
  Future<double> getProjectBalance(
    int projectId, {
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
      WHERE ${_unsettledScope('t.project_id', startDate, endDate)}
    ''',
      [projectId, ..._scopeArgs(startDate, endDate)],
    );

    final row = result.first;
    final theyOweMe = (row['they_owe_me'] as num?)?.toDouble() ?? 0.0;
    final iOweThem = (row['i_owe_them'] as num?)?.toDouble() ?? 0.0;
    return theyOweMe - iOweThem;
  }

  /// Unsettled totals, for the balance cards.
  Future<Map<String, double>> getProjectTotals(
    int projectId, {
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
      WHERE ${_unsettledScope('t.project_id', startDate, endDate)}
    ''',
      [projectId, ..._scopeArgs(startDate, endDate)],
    );

    final row = result.first;
    return {
      'they_owe_me': (row['they_owe_me'] as num?)?.toDouble() ?? 0.0,
      'i_owe_them': (row['i_owe_them'] as num?)?.toDouble() ?? 0.0,
    };
  }

  /// Signed settled total: they_owe_me positive, i_owe_them negative.
  Future<double> getProjectSettledTotal(int projectId) async {
    final db = await _db;
    final result = await db.rawQuery(
      '''
      SELECT
        SUM(CASE WHEN type = 'they_owe_me' THEN amount ELSE 0 END) as they_owe_me,
        SUM(CASE WHEN type = 'i_owe_them' THEN amount ELSE 0 END) as i_owe_them
      FROM transactions
      WHERE project_id = ? AND is_settled = 1
    ''',
      [projectId],
    );

    final row = result.first;
    final theyOweMe = (row['they_owe_me'] as num?)?.toDouble() ?? 0.0;
    final iOweThem = (row['i_owe_them'] as num?)?.toDouble() ?? 0.0;
    return theyOweMe - iOweThem;
  }

  /// Budget remaining counts money that has actually changed hands (rule 3):
  ///   budget + i_owe_them - they_owe_me
  ///
  /// A fully-settled row contributes its whole amount; an installment row
  /// contributes only the payments received so far, so the budget never
  /// spends money the app has not seen yet.
  ///
  /// [startDate] / [endDate] optionally restrict that same rule to a range so
  /// a dated report stays consistent with its own transaction table.
  Future<double> getBudgetRemaining(
    int projectId, {
    String? startDate,
    String? endDate,
  }) async {
    final project = await getProject(projectId);
    if (project == null || project.budget == null) return 0.0;

    final db = await _db;
    // No `is_settled` filter here: [PaymentSql.settledValue] already yields 0
    // for rows that bring nothing in, and it is the only expression that also
    // gives a half-paid installment its due share.
    final result = await db.rawQuery(
      '''
      SELECT
        SUM(CASE WHEN type = 'they_owe_me' THEN ${PaymentSql.settledValue('t')} ELSE 0 END) as they_owe_me,
        SUM(CASE WHEN type = 'i_owe_them' THEN ${PaymentSql.settledValue('t')} ELSE 0 END) as i_owe_them
      FROM transactions t
      ${PaymentSql.join('t')}
      WHERE ${_scope('t.project_id', startDate, endDate)}
    ''',
      [projectId, ..._scopeArgs(startDate, endDate)],
    );

    final row = result.first;
    // Aliases keep the historical names; they now hold the money that has
    // actually changed hands rather than the raw settled rows.
    final theyOweMe = (row['they_owe_me'] as num?)?.toDouble() ?? 0.0;
    final iOweThem = (row['i_owe_them'] as num?)?.toDouble() ?? 0.0;

    return project.budget! + iOweThem - theyOweMe;
  }

  /// `column = ?`, `is_settled = 0` and any inclusive date bounds.
  static String _unsettledScope(
    String column,
    String? startDate,
    String? endDate,
  ) {
    return _scope(column, startDate, endDate, unsettledOnly: true);
  }

  /// `column = ?` plus any inclusive date bounds.
  static String _scope(
    String column,
    String? startDate,
    String? endDate, {
    bool unsettledOnly = false,
  }) {
    final parts = <String>['$column = ?'];
    if (unsettledOnly) parts.add('is_settled = 0');
    if (startDate != null) parts.add('date >= ?');
    if (endDate != null) parts.add('date <= ?');
    return parts.join(' AND ');
  }

  static List<Object?> _scopeArgs(String? startDate, String? endDate) => [
    ?startDate,
    ?endDate,
  ];
}
