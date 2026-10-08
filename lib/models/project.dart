import '../utils/currency_formatter.dart';
import '../utils/date_formatter.dart';

class Project {
  final int? id;
  final int personId;
  final String name;
  final double? budget;
  final int isArchived;
  final String createdAt;
  final String updatedAt;

  Project({
    this.id,
    required this.personId,
    required this.name,
    this.budget,
    this.isArchived = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Project.fromMap(Map<String, dynamic> map) {
    return Project(
      id: map['id'] as int?,
      personId: map['person_id'] as int,
      name: map['name'] as String,
      budget: (map['budget'] as num?)?.toDouble(),
      isArchived: map['is_archived'] as int? ?? 0,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'person_id': personId,
      'name': name,
      'budget': budget,
      'is_archived': isArchived,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  Map<String, dynamic> toMapForInsert() {
    final now = DateFormatter.toIsoString(DateTime.now());
    return {
      'person_id': personId,
      'name': name,
      'budget': budget,
      'is_archived': isArchived,
      'created_at': now,
      'updated_at': now,
    };
  }

  Map<String, dynamic> toMapForUpdate() {
    return {
      'name': name,
      'budget': budget,
      'is_archived': isArchived,
      'updated_at': DateFormatter.toIsoString(DateTime.now()),
    };
  }

  Project copyWith({
    int? id,
    int? personId,
    String? name,
    double? budget,
    int? isArchived,
    String? createdAt,
    String? updatedAt,
  }) {
    return Project(
      id: id ?? this.id,
      personId: personId ?? this.personId,
      name: name ?? this.name,
      budget: budget ?? this.budget,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isArchivedBool => isArchived == 1;
  bool get hasBudget => budget != null;

  String get formattedBudget => budget != null ? CurrencyFormatter.format(budget!) : '—';
  String get formattedBudgetWithSign => budget != null ? CurrencyFormatter.formatWithSign(budget!) : '—';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Project &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          personId == other.personId &&
          name == other.name &&
          budget == other.budget &&
          isArchived == other.isArchived &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      personId.hashCode ^
      name.hashCode ^
      budget.hashCode ^
      isArchived.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode;

  @override
  String toString() {
    return 'Project(id: $id, personId: $personId, name: $name, budget: $budget, isArchived: $isArchived, createdAt: $createdAt, updatedAt: $updatedAt)';
  }
}