import 'transaction.dart';

/// One installment against a transaction.
///
/// Every transaction can be paid in pieces; the parent's settled flag is
/// re-derived from `SUM(amount)` after every change.
class TransactionPayment {
  final int? id;
  final int transactionId;
  final double amount;

  /// ISO-8601, user-editable (unlike `createdAt`).
  final String date;
  final String? note;
  final String createdAt;

  const TransactionPayment({
    this.id,
    required this.transactionId,
    required this.amount,
    required this.date,
    this.note,
    required this.createdAt,
  });

  factory TransactionPayment.fromMap(Map<String, dynamic> map) {
    return TransactionPayment(
      id: map['id'] as int?,
      transactionId: map['transaction_id'] as int,
      amount: (map['amount'] as num).toDouble(),
      date: map['date'] as String,
      note: map['note'] as String?,
      createdAt: map['created_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'transaction_id': transactionId,
      'amount': amount,
      'date': date,
      'note': note,
      'created_at': createdAt,
    };
  }

  Map<String, dynamic> toMapForInsert() {
    return {
      'transaction_id': transactionId,
      'amount': amount,
      'date': date,
      'note': note,
      'created_at': createdAt,
    };
  }

  Map<String, dynamic> toMapForUpdate() {
    return {'amount': amount, 'date': date, 'note': note};
  }

  TransactionPayment copyWith({
    int? id,
    int? transactionId,
    double? amount,
    String? date,
    String? note,
    String? createdAt,
  }) {
    return TransactionPayment(
      id: id ?? this.id,
      transactionId: transactionId ?? this.transactionId,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionPayment &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          transactionId == other.transactionId &&
          amount == other.amount &&
          date == other.date &&
          note == other.note &&
          createdAt == other.createdAt;

  @override
  int get hashCode =>
      id.hashCode ^
      transactionId.hashCode ^
      amount.hashCode ^
      date.hashCode ^
      note.hashCode ^
      createdAt.hashCode;

  @override
  String toString() {
    return 'TransactionPayment(id: $id, transactionId: $transactionId, amount: $amount, date: $date, note: $note, createdAt: $createdAt)';
  }
}

/// Sum of [payments], or 0 when the transaction has no history yet.
double totalPaid(List<TransactionPayment>? payments) {
  if (payments == null || payments.isEmpty) return 0.0;
  var sum = 0.0;
  for (final payment in payments) {
    sum += payment.amount;
  }
  return sum;
}

/// What is still outstanding on [txn] given [paid] already collected.
///
/// One rule for every row: the amount less everything received, never below
/// zero. A row with no history owes its full amount; a fully paid one owes
/// nothing.
double outstandingOf(Transaction txn, double paid) {
  final remaining = txn.amount - paid;
  return remaining < 0 ? 0 : remaining;
}

/// Dedup identity used when restoring a backup: same size, same day, same
/// label is the same installment.
String paymentDedupeKey(double amount, String date, String? note) =>
    '$amount|$date|$note';

/// The Arabic chip shown while a row is part-way to being settled.
///
/// Callers only show it for `0 < paid < amount`; a fully paid row is settled
/// and gets the ordinary settled chip instead.
String partialStatusLabel(double amount, double paid) {
  if (paid <= 0) return 'لسه';
  if (paid >= amount - 1e-9) return 'مسدَّدة';
  return 'مدفوعة جزئيًا';
}

/// True while some money has landed but the row is not done yet.
bool isPartlyPaid(double amount, double paid) =>
    paid > 0 && paid < amount - 1e-9;
