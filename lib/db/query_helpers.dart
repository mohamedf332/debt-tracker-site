/// Shared query helpers for filtering out archived projects and persons.
///
/// The core rule: a transaction is visible only if it has no project
/// (project_id IS NULL) OR its project is not archived (p.is_archived = 0).
/// This ensures archived projects' transactions are hidden everywhere:
/// Home totals, Person Detail, project tabs, PDF reports, exports, etc.
class VisibleTxnQuery {
  VisibleTxnQuery._();

  /// The WHERE clause fragment that filters out archived projects.
  ///
  /// Use this in any query that selects from `transactions` and wants to
  /// respect the archive status of the project.
  static const String whereVisibleProjects =
      '(t.project_id IS NULL OR p.is_archived = 0)';

  /// The LEFT JOIN clause to bring in the project's archive status.
  static const String joinProjects = 'LEFT JOIN projects p ON t.project_id = p.id';

  /// Builds a complete SELECT query for visible transactions with all
  /// standard columns, suitable for listing or aggregation.
  ///
  /// [extraWhere] — optional additional WHERE clauses (AND-ed).
  /// [extraArgs] — arguments for [extraWhere].
  /// [tableAlias] — table alias for transactions (default 't').
  static String select({
    String tableAlias = 't',
    String? extraWhere,
    List<Object?> extraArgs = const [],
    String orderBy = 't.created_at DESC, t.id DESC',
    String? limit,
  }) {
    final whereParts = <String>[
      '$tableAlias.project_id IS NULL OR p.is_archived = 0',
    ];
    if (extraWhere != null && extraWhere.isNotEmpty) {
      whereParts.add(extraWhere);
    }
    final whereClause = whereParts.join(' AND ');

    final sql = StringBuffer()
      ..write('SELECT $tableAlias.* ')
      ..write('FROM transactions $tableAlias ')
      ..write('LEFT JOIN projects p ON $tableAlias.project_id = p.id ')
      ..write('WHERE $whereClause ')
      ..write('ORDER BY $orderBy');
    if (limit != null) sql.write(' LIMIT $limit');
    return sql.toString();
  }

  /// Builds an aggregation query (SUM, COUNT, etc.) for visible transactions.
  ///
  /// [selectClause] — the aggregation expression, e.g.
  ///   `SUM(CASE WHEN type = 'they_owe_me' THEN amount ELSE 0 END)`
  /// [extraWhere] / [extraArgs] — same as [select].
  static String aggregate({
    required String selectClause,
    String tableAlias = 't',
    String? extraWhere,
    List<Object?> extraArgs = const [],
  }) {
    final whereParts = <String>[
      '$tableAlias.project_id IS NULL OR p.is_archived = 0',
    ];
    if (extraWhere != null && extraWhere.isNotEmpty) {
      whereParts.add(extraWhere);
    }
    final whereClause = whereParts.join(' AND ');

    return '''
      SELECT $selectClause
      FROM transactions $tableAlias
      LEFT JOIN projects p ON $tableAlias.project_id = p.id
      WHERE $whereClause
    ''';
  }

  /// Adds the visible-projects filter to an existing raw query's WHERE clause.
  ///
  /// Useful when you already have a complex query and just need to append
  /// the archive filter. Returns the modified WHERE clause and the combined args.
  static ({String where, List<Object?> args}) appendFilter({
    required String baseWhere,
    required List<Object?> baseArgs,
  }) {
    const filter = '(t.project_id IS NULL OR p.is_archived = 0)';
    return (
      where: '$baseWhere AND $filter',
      args: baseArgs,
    );
  }
}