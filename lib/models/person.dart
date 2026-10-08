import '../utils/date_formatter.dart';

class Person {
  final int? id;
  final String name;
  final int isPinned;
  final int? pinOrder;
  final int isArchived;
  final String createdAt;
  final String updatedAt;

  Person({
    this.id,
    required this.name,
    this.isPinned = 0,
    this.pinOrder,
    this.isArchived = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Person.fromMap(Map<String, dynamic> map) {
    return Person(
      id: map['id'] as int?,
      name: map['name'] as String,
      isPinned: map['is_pinned'] as int? ?? 0,
      pinOrder: map['pin_order'] as int?,
      isArchived: map['is_archived'] as int? ?? 0,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'is_pinned': isPinned,
      'pin_order': pinOrder,
      'is_archived': isArchived,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  Map<String, dynamic> toMapForInsert() {
    final now = DateFormatter.toIsoString(DateTime.now());
    return {
      'name': name,
      'is_pinned': isPinned,
      'pin_order': pinOrder,
      'is_archived': isArchived,
      'created_at': now,
      'updated_at': now,
    };
  }

  Map<String, dynamic> toMapForUpdate() {
    return {
      'name': name,
      'is_pinned': isPinned,
      'pin_order': pinOrder,
      'is_archived': isArchived,
      'updated_at': DateFormatter.toIsoString(DateTime.now()),
    };
  }

  Person copyWith({
    int? id,
    String? name,
    int? isPinned,
    int? pinOrder,
    int? isArchived,
    String? createdAt,
    String? updatedAt,
  }) {
    return Person(
      id: id ?? this.id,
      name: name ?? this.name,
      isPinned: isPinned ?? this.isPinned,
      pinOrder: pinOrder ?? this.pinOrder,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isPinnedBool => isPinned == 1;
  bool get isArchivedBool => isArchived == 1;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Person &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          isPinned == other.isPinned &&
          pinOrder == other.pinOrder &&
          isArchived == other.isArchived &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      isPinned.hashCode ^
      pinOrder.hashCode ^
      isArchived.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode;

  @override
  String toString() {
    return 'Person(id: $id, name: $name, isPinned: $isPinned, pinOrder: $pinOrder, isArchived: $isArchived, createdAt: $createdAt, updatedAt: $updatedAt)';
  }
}