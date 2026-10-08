import '../db/attachment_dao.dart';
import '../db/payment_dao.dart';
import '../db/person_dao.dart';
import '../db/project_dao.dart';
import '../db/transaction_dao.dart';
import '../models/transaction.dart';
import '../models/transaction_payment.dart';
import 'report_data.dart';

/// Loads everything a report needs and freezes it into a [ReportData].
///
/// All balance / budget numbers come from the same DAO functions the app's
/// cards use, just with the optional date bounds attached, so the PDF can
/// never disagree with the UI. The only numbers derived here are the lifetime
/// directional totals and the table rows themselves — both read off the exact
/// same query that feeds the table, so the summary and the table always add
/// up to each other.
class ReportDataBuilder {
  final PersonDao _personDao = PersonDao();
  final ProjectDao _projectDao = ProjectDao();
  final TransactionDao _transactionDao = TransactionDao();
  final AttachmentDao _attachmentDao = AttachmentDao();
  final PaymentDao _paymentDao = PaymentDao();

  /// Person-wide report: every project plus the transactions without one.
  Future<ReportData?> buildPersonReport({
    required int personId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final person = await _personDao.getPerson(personId);
    if (person == null) return null;

    final start = _rangeStart(startDate);
    final end = _rangeEnd(endDate);

    final rows = await _transactionDao.getTransactionsForPerson(
      personId,
      startDate: start,
      endDate: end,
    );
    final balance = await _personDao.getPersonBalance(
      personId,
      startDate: start,
      endDate: end,
    );
    final unsettled = await _personDao.getPersonTotals(
      personId,
      startDate: start,
      endDate: end,
    );

    return ReportData(
      personName: person.name,
      projectName: null,
      from: startDate,
      to: endDate,
      generatedAt: DateTime.now(),
      balance: balance,
      totalTheyOweMe: _sumOfType(rows, TransactionType.theyOweMe),
      totalIOweThem: _sumOfType(rows, TransactionType.iOweThem),
      budget: null,
      budgetRemaining: null,
      unsettledReceivable: unsettled['they_owe_me'] ?? 0.0,
      unsettledPayable: unsettled['i_owe_them'] ?? 0.0,
      transactions: await _toReportTransactions(rows),
    );
  }

  /// Report for a single project, including its budget when it has one.
  Future<ReportData?> buildProjectReport({
    required int projectId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final project = await _projectDao.getProject(projectId);
    if (project == null) return null;
    final person = await _personDao.getPerson(project.personId);
    if (person == null) return null;

    final start = _rangeStart(startDate);
    final end = _rangeEnd(endDate);

    final rows = await _transactionDao.getTransactionsForProject(
      projectId,
      startDate: start,
      endDate: end,
    );
    final balance = await _projectDao.getProjectBalance(
      projectId,
      startDate: start,
      endDate: end,
    );
    final unsettled = await _projectDao.getProjectTotals(
      projectId,
      startDate: start,
      endDate: end,
    );
    final budget = project.budget;
    final budgetRemaining = budget == null
        ? null
        : await _projectDao.getBudgetRemaining(
            projectId,
            startDate: start,
            endDate: end,
          );

    return ReportData(
      personName: person.name,
      projectName: project.name,
      from: startDate,
      to: endDate,
      generatedAt: DateTime.now(),
      balance: balance,
      totalTheyOweMe: _sumOfType(rows, TransactionType.theyOweMe),
      totalIOweThem: _sumOfType(rows, TransactionType.iOweThem),
      budget: budget,
      budgetRemaining: budgetRemaining,
      unsettledReceivable: unsettled['they_owe_me'] ?? 0.0,
      unsettledPayable: unsettled['i_owe_them'] ?? 0.0,
      transactions: await _toReportTransactions(rows),
    );
  }

  // ------------------------------------------------------------------ util

  /// Inclusive lower bound. Midnight carries no fractional part, so it sorts
  /// before `...T00:00:00.000` rows as well as plain `...T00:00:00` rows.
  static String? _rangeStart(DateTime? date) => date == null
      ? null
      : DateTime(date.year, date.month, date.day).toIso8601String();

  /// Inclusive upper bound: the whole end day, not just its midnight.
  static String? _rangeEnd(DateTime? date) => date == null
      ? null
      : DateTime(date.year, date.month, date.day, 23, 59, 59, 999)
            .toIso8601String();

  static double _sumOfType(List<Transaction> rows, TransactionType type) {
    var sum = 0.0;
    for (final row in rows) {
      if (row.type == type) sum += row.amount;
    }
    return sum;
  }

  /// Oldest first so the table reads top-to-bottom chronologically; ids break
  /// same-second ties the same way the detail screen does, just reversed.
  Future<List<ReportTransaction>> _toReportTransactions(
    List<Transaction> rows,
  ) async {
    final sorted = [...rows]..sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      return (a.id ?? 0).compareTo(b.id ?? 0);
    });

    final ids = [for (final txn in sorted) if (txn.id != null) txn.id!];
    final paymentsById = await _paymentDao.getPaymentsForTransactions(ids);

    final report = <ReportTransaction>[];
    for (var i = 0; i < sorted.length; i++) {
      final txn = sorted[i];
      final id = txn.id;
      final imagePaths = <String>[];
      if (id != null) {
        final attachments =
            await _attachmentDao.getAttachmentsForTransaction(id);
        imagePaths.addAll(attachments.map((attachment) => attachment.filePath));
      }

      // The DAO returns newest first; the report reads oldest first.
      final payments = id == null
          ? const <TransactionPayment>[]
          : (paymentsById[id] ?? const <TransactionPayment>[])
                .reversed
                .toList(growable: false);

      report.add(
        ReportTransaction(
          id: id ?? -(i + 1),
          date: txn.date,
          amount: txn.amount,
          state: ReportTxnState.of(txn),
          note: txn.note,
          imagePaths: imagePaths,
          paid: totalPaid(payments),
          payments: [
            for (final payment in payments)
              ReportPayment(date: payment.date, amount: payment.amount),
          ],
        ),
      );
    }
    return report;
  }
}
