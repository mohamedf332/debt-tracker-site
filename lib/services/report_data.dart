import 'package:pdf/pdf.dart';

import '../models/transaction.dart';
import '../theme/app_colors.dart';

/// The four states a report line can be in.
///
/// TODO(4-state enum): the app still stores the direction as [TransactionType]
/// plus a separate `isSettled` flag. When those two merge into a single
/// 4-value enum, only [ReportTxnState.of] and the two helpers below need to
/// change — nothing in the builder or the renderer knows about the old shape.
enum ReportTxnState {
  theyOweMeUnsettled('they_owe_me', false),
  theyOweMeSettled('they_owe_me', true),
  iOweThemUnsettled('i_owe_them', false),
  iOweThemSettled('i_owe_them', true);

  const ReportTxnState(this.typeValue, this.isSettled);

  final String typeValue;
  final bool isSettled;

  static ReportTxnState of(Transaction transaction) {
    final settled = transaction.isSettled;
    return switch (transaction.type) {
      TransactionType.theyOweMe =>
        settled ? ReportTxnState.theyOweMeSettled : ReportTxnState.theyOweMeUnsettled,
      TransactionType.iOweThem =>
        settled ? ReportTxnState.iOweThemSettled : ReportTxnState.iOweThemUnsettled,
    };
  }

  /// True for `they_owe_me` in either settlement state.
  bool get isCredit => typeValue == 'they_owe_me';
}

/// The single place a [ReportTxnState] turns into an Arabic label.
String typeLabelAr(ReportTxnState state) => switch (state) {
  ReportTxnState.theyOweMeUnsettled => 'ليَّ عنده',
  ReportTxnState.theyOweMeSettled => 'مُحصَّل',
  ReportTxnState.iOweThemUnsettled => 'عليّا',
  ReportTxnState.iOweThemSettled => 'مُسدَّد',
};

/// The single place a [ReportTxnState] turns into a colour.
///
/// "Owed to me" is always green, "I owe" is always red, and the settled half
/// of each pair is lightened towards white so it reads as history rather than
/// as an open amount. Everything is derived from [AppColors] so the PDF can
/// never drift from the UI.
PdfColor typeColor(ReportTxnState state) {
  final base = state.isCredit ? AppColors.green : AppColors.red;
  return PdfColor.fromInt(
    state.isSettled ? softenTowardWhite(base.toARGB32(), 0.45) : base.toARGB32(),
  );
}

/// Mixes [argb] towards white by [amount] (`0` keeps it, `1` turns it white).
/// Lets the renderer derive lighter variants from [AppColors] instead of
/// inventing a second palette.
int softenTowardWhite(int argb, double amount) {
  final alpha = (argb >> 24) & 0xFF;
  int mix(int channel) => (channel + (255 - channel) * amount).round();
  final red = mix((argb >> 16) & 0xFF);
  final green = mix((argb >> 8) & 0xFF);
  final blue = mix(argb & 0xFF);
  return (alpha << 24) | (red << 16) | (green << 8) | blue;
}

/// Re-tints [argb] with a new alpha channel, keeping [AppColors]' RGB.
int withAlpha(int argb, int alpha) => (alpha << 24) | (argb & 0xFFFFFF);

/// One installment of a partially-paid transaction.
class ReportPayment {
  ReportPayment({required this.date, required this.amount});

  /// ISO-8601 local timestamp, exactly as stored by the app.
  final String date;

  final double amount;
}

/// One row of the transactions table.
class ReportTransaction {
  ReportTransaction({
    required this.id,
    required this.date,
    required this.amount,
    required this.state,
    required this.note,
    required this.imagePaths,
    this.paid = 0,
    this.payments = const [],
  });

  final int id;

  /// ISO-8601 local timestamp, exactly as stored by the app.
  final String date;

  final double amount;

  final ReportTxnState state;

  final String? note;

  /// Absolute paths, read lazily by the renderer while it builds the
  /// appendix — never loaded up-front for the whole report.
  final List<String> imagePaths;

  /// Installments received so far. `0` for a row with no history.
  final double paid;

  /// Chronological, oldest first — the order the appendix lists them in.
  final List<ReportPayment> payments;

  /// What is still outstanding, never negative.
  double get remaining => (amount - paid).clamp(0, amount);

  /// True when something has been paid but the row is not done yet.
  bool get isPartlyPaid => paid > 0 && paid < amount - 1e-9;
}

/// Everything the renderer needs to draw a report. Pure data: no database,
/// no Flutter, no file handles — safe to hand to a background isolate.
class ReportData {
  ReportData({
    required this.personName,
    required this.projectName,
    required this.from,
    required this.to,
    required this.generatedAt,
    required this.balance,
    required this.totalTheyOweMe,
    required this.totalIOweThem,
    required this.budget,
    required this.budgetRemaining,
    required this.unsettledReceivable,
    required this.unsettledPayable,
    required this.transactions,
  });

  final String personName;
  final String? projectName;

  /// `null` means "كل الفترة" (no custom range was picked).
  final DateTime? from;
  final DateTime? to;

  final DateTime generatedAt;

  /// Unsettled net position; equals `unsettledReceivable - unsettledPayable`
  /// and matches the balance card on screen.
  final double balance;

  /// Every `they_owe_me` in scope, settled or not.
  final double totalTheyOweMe;

  /// Every `i_owe_them` in scope, settled or not.
  final double totalIOweThem;

  final double? budget;
  final double? budgetRemaining;

  /// The subset of the totals that has not changed hands yet.
  final double unsettledReceivable;
  final double unsettledPayable;

  /// Sorted ascending by date, ascending by id within the same day.
  final List<ReportTransaction> transactions;

  bool get isEmpty => transactions.isEmpty;

  bool get hasBudget => budget != null && budgetRemaining != null;
}
