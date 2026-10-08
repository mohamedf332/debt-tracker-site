import '../utils/currency_formatter.dart';
import '../utils/date_formatter.dart';

/// Sentinel for [Transaction.copyWith] so `settledAt: null` actually clears
/// the value instead of being swallowed by `?? this.settledAt`.
const Object _unset = Object();

enum TransactionType {
  theyOweMe('they_owe_me', 'ليَّ عنده'),
  iOweThem('i_owe_them', 'عليّا');

  const TransactionType(this.value, this.arabicLabel);
  final String value;
  final String arabicLabel;

  static TransactionType fromString(String value) {
    return TransactionType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => TransactionType.theyOweMe,
    );
  }
}

/// Filter for the settlement column (rule 4).
enum SettlementFilter {
  all('الكل'),
  unsettled('غير مسدَّد'),
  settled('مسدَّد');

  const SettlementFilter(this.arabicLabel);
  final String arabicLabel;
}

class Transaction {
  final int? id;
  final int personId;
  final int? projectId;
  final double amount;
  final TransactionType type;
  final String? note;
  final String date;
  final String createdAt;
  final bool isSettled;
  final DateTime? settledAt;

  Transaction({
    this.id,
    required this.personId,
    this.projectId,
    required this.amount,
    required this.type,
    this.note,
    required this.date,
    required this.createdAt,
    this.isSettled = false,
    this.settledAt,
  });

  factory Transaction.fromMap(Map<String, dynamic> map) {
    final settledAtRaw = map['settled_at'];
    return Transaction(
      id: map['id'] as int?,
      personId: map['person_id'] as int,
      projectId: map['project_id'] as int?,
      amount: (map['amount'] as num).toDouble(),
      type: TransactionType.fromString(map['type'] as String),
      note: map['note'] as String?,
      date: map['date'] as String,
      createdAt: map['created_at'] as String,
      // Missing column (import from an old export) => unsettled.
      isSettled: ((map['is_settled'] as num?) ?? 0) == 1,
      settledAt: settledAtRaw is String ? DateTime.tryParse(settledAtRaw) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'person_id': personId,
      'project_id': projectId,
      'amount': amount,
      'type': type.value,
      'note': note,
      'date': date,
      'created_at': createdAt,
      'is_settled': isSettled ? 1 : 0,
      'settled_at': settledAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toMapForInsert() {
    final now = DateFormatter.toIsoString(DateTime.now());
    return {
      'person_id': personId,
      'project_id': projectId,
      'amount': amount,
      'type': type.value,
      'note': note,
      'date': date,
      'created_at': now,
      'is_settled': isSettled ? 1 : 0,
      'settled_at': settledAt?.toIso8601String(),
    };
  }

  Map<String, dynamic> toMapForUpdate() {
    return {
      'person_id': personId,
      'project_id': projectId,
      'amount': amount,
      'type': type.value,
      'note': note,
      'date': date,
      'is_settled': isSettled ? 1 : 0,
      'settled_at': settledAt?.toIso8601String(),
    };
  }

  Transaction copyWith({
    int? id,
    int? personId,
    int? projectId,
    double? amount,
    TransactionType? type,
    String? note,
    String? date,
    String? createdAt,
    bool? isSettled,
    Object? settledAt = _unset,
  }) {
    return Transaction(
      id: id ?? this.id,
      personId: personId ?? this.personId,
      projectId: projectId ?? this.projectId,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      note: note ?? this.note,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
      isSettled: isSettled ?? this.isSettled,
      settledAt: settledAt == _unset ? this.settledAt : settledAt as DateTime?,
    );
  }

  /// Returns a copy with the settlement flag flipped per [settled].
  ///
  /// Rule 2: settling stamps [settledAt] (defaults to now), un-settling clears it.
  Transaction withSettled(bool settled, {DateTime? at}) {
    if (settled) {
      final stamp = at ?? settledAt ?? DateTime.now();
      return copyWith(isSettled: true, settledAt: stamp);
    }
    return copyWith(isSettled: false, settledAt: null);
  }

  double get signedAmount {
    return type == TransactionType.theyOweMe ? amount : -amount;
  }

  /// Signed amount used only by settled totals (same sign convention).
  double get signedSettledAmount => isSettled ? signedAmount : 0.0;

  String get formattedAmount {
    return CurrencyFormatter.format(amount);
  }

  String get formattedAmountWithSign {
    return CurrencyFormatter.formatWithSign(signedAmount);
  }

  String get formattedDate {
    return DateFormatter.formatDisplayDate(DateFormatter.parseDateTime(date));
  }

  String get formattedDateTime {
    return DateFormatter.formatDisplayDateTime(
      DateFormatter.parseDateTime(date),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Transaction &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          personId == other.personId &&
          projectId == other.projectId &&
          amount == other.amount &&
          type == other.type &&
          note == other.note &&
          date == other.date &&
          createdAt == other.createdAt &&
          isSettled == other.isSettled &&
          settledAt == other.settledAt;

  @override
  int get hashCode =>
      id.hashCode ^
      personId.hashCode ^
      projectId.hashCode ^
      amount.hashCode ^
      type.hashCode ^
      note.hashCode ^
      date.hashCode ^
      createdAt.hashCode ^
      isSettled.hashCode ^
      settledAt.hashCode;

  @override
  String toString() {
    return 'Transaction(id: $id, personId: $personId, projectId: $projectId, amount: $amount, type: $type, note: $note, date: $date, createdAt: $createdAt, isSettled: $isSettled, settledAt: $settledAt)';
  }
}
