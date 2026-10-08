/// Shared SQL fragments so every money query counts installments the same way.
///
/// Kept in one file because the person balance, the project balance and the
/// budget remaining are all *supposed* to disagree with each other only in
/// which rows they filter on — never in how a partially-paid row is valued.
abstract final class PaymentSql {
  /// Attaches the payment total of each row as `pay.paid` (0 when there is
  /// no installment history). Must follow the `FROM transactions` clause.
  /// [table] is the table name or alias for transactions (e.g., 't').
  static String join([String table = 'transactions']) => '''
    LEFT JOIN (
      SELECT transaction_id, SUM(amount) AS paid
      FROM transaction_payments
      GROUP BY transaction_id
    ) pay ON pay.transaction_id = $table.id
  ''';

  /// What a row still owes: its amount less everything received so far.
  /// [table] is the table name or alias for transactions (e.g., 't').
  static String outstanding([String table = 'transactions']) =>
      'MAX($table.amount - IFNULL(pay.paid, 0), 0)';

  /// What a row has actually brought into the budget.
  ///
  /// `is_settled` still wins as a safety net for a row whose history was
  /// removed out from under it, but in normal operation it is redundant: a
  /// settled row is by definition paid in full, so `MIN(paid, amount)` gives
  /// the same number. Everything short of that contributes only its paid part.
  /// [table] is the table name or alias for transactions (e.g., 't').
  static String settledValue([String table = 'transactions']) => '''
    CASE WHEN $table.is_settled = 1 THEN $table.amount
         ELSE MIN(IFNULL(pay.paid, 0), $table.amount)
  END
  ''';
}
