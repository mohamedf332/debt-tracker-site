import '../utils/date_formatter.dart';

class TransactionAttachment {
  final int? id;
  final int transactionId;
  final String filePath;
  final String createdAt;

  TransactionAttachment({
    this.id,
    required this.transactionId,
    required this.filePath,
    required this.createdAt,
  });

  factory TransactionAttachment.fromMap(Map<String, dynamic> map) {
    return TransactionAttachment(
      id: map['id'] as int?,
      transactionId: map['transaction_id'] as int,
      filePath: map['file_path'] as String,
      createdAt: map['created_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'transaction_id': transactionId,
      'file_path': filePath,
      'created_at': createdAt,
    };
  }

  Map<String, dynamic> toMapForInsert() {
    final now = DateFormatter.toIsoString(DateTime.now());
    return {
      'transaction_id': transactionId,
      'file_path': filePath,
      'created_at': now,
    };
  }

  TransactionAttachment copyWith({
    int? id,
    int? transactionId,
    String? filePath,
    String? createdAt,
  }) {
    return TransactionAttachment(
      id: id ?? this.id,
      transactionId: transactionId ?? this.transactionId,
      filePath: filePath ?? this.filePath,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionAttachment &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          transactionId == other.transactionId &&
          filePath == other.filePath &&
          createdAt == other.createdAt;

  @override
  int get hashCode =>
      id.hashCode ^ transactionId.hashCode ^ filePath.hashCode ^ createdAt.hashCode;

  @override
  String toString() {
    return 'TransactionAttachment(id: $id, transactionId: $transactionId, filePath: $filePath, createdAt: $createdAt)';
  }
}