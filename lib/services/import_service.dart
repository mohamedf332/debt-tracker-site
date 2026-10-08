import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/person.dart';
import '../models/project.dart';
import '../models/transaction.dart';
import '../models/transaction_attachment.dart';
import '../db/person_dao.dart';
import '../db/project_dao.dart';
import '../db/transaction_dao.dart';
import '../db/attachment_dao.dart';
import '../db/payment_dao.dart';
import '../models/transaction_payment.dart';
import 'image_storage_service.dart';

class ImportService {
  ImportService._();

  static final ImportService instance = ImportService._();

  final PersonDao _personDao = PersonDao();
  final ProjectDao _projectDao = ProjectDao();
  final TransactionDao _transactionDao = TransactionDao();
  final AttachmentDao _attachmentDao = AttachmentDao();
  final PaymentDao _paymentDao = PaymentDao();
  final ImageStorageService _imageStorage = ImageStorageService.instance;

  Future<void> importFromFile(File file) async {
    final jsonString = await file.readAsString();
    await importFromJsonString(jsonString);
  }

  /// Imports a backup payload. Throws with an Arabic message when the file is
  /// malformed, so callers can surface it instead of a raw cast error.
  Future<void> importFromJsonString(String jsonString) async {
    final data = _decode(jsonString);

    final exportVersion = (data['export_version'] as num?)?.toInt() ?? 1;
    if (exportVersion > 2) {
      throw Exception('إصدار التصدير غير مدعوم: $exportVersion');
    }

    final personsData = data['persons'];
    if (personsData is! List) {
      throw Exception('ملف النسخة الاحتياطية غير صالح: لا يوجد حقل "persons"');
    }

    // Load existing rows ONCE. Re-querying inside every loop made a restore of
    // a few hundred transactions take thousands of queries.
    final existingPersons = await _personDao.getAllPersons(includeArchived: true);
    final personsByName = <String, Person>{for (final p in existingPersons) p.name: p};

    var personsCreated = 0, personsUpdated = 0, projectsAdded = 0;
    var txnsCreated = 0, txnsSkipped = 0, attachmentsSaved = 0, attachmentsFailed = 0;
    var paymentsCreated = 0, paymentsSkipped = 0;

    for (final personData in personsData) {
      if (personData is! Map<String, dynamic>) {
        throw Exception('ملف النسخة الاحتياطية غير صالح: بيانات شخص غير صحيحة');
      }
      final result = await _importPerson(personData, personsByName);
      personsCreated += result.personsCreated;
      personsUpdated += result.personsUpdated;
      projectsAdded += result.projectsAdded;
      txnsCreated += result.txnsCreated;
      txnsSkipped += result.txnsSkipped;
      attachmentsSaved += result.attachmentsSaved;
      attachmentsFailed += result.attachmentsFailed;
      paymentsCreated += result.paymentsCreated;
      paymentsSkipped += result.paymentsSkipped;
    }

    debugPrint('[Import] done: persons +$personsCreated ~$personsUpdated, '
        'projects +$projectsAdded, txns +$txnsCreated (skipped $txnsSkipped), '
        'payments +$paymentsCreated (skipped $paymentsSkipped), '
        'attachments saved=$attachmentsSaved failed=$attachmentsFailed');
  }

  Map<String, dynamic> _decode(String jsonString) {
    Object? decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException {
      throw Exception('ملف النسخة الاحتياطية غير صالح: JSON غير صحيح');
    }
    if (decoded is! Map<String, dynamic>) {
      throw Exception('ملف النسخة الاحتياطية غير صالح: البنية غير متوقعة');
    }
    return decoded;
  }

  Future<_ImportStats> _importPerson(
    Map<String, dynamic> personData,
    Map<String, Person> personsByName,
  ) async {
    final stats = _ImportStats();

    final name = personData['name'];
    if (name is! String || name.isEmpty) {
      throw Exception('ملف النسخة الاحتياطية غير صالح: اسم شخص مفقود');
    }
    final isPinned = (personData['is_pinned'] as num?)?.toInt() ?? 0;
    final pinOrder = (personData['pin_order'] as num?)?.toInt();
    final isArchived = (personData['is_archived'] as num?)?.toInt() ?? 0;

    final existing = personsByName[name];
    Person person;
    if (existing != null && existing.id != null) {
      // Rebuild explicitly: Person.copyWith cannot clear a field from a value
      // that is legitimately 0/null, and restore must honour the backup.
      person = Person(
        id: existing.id,
        name: existing.name,
        isPinned: isPinned,
        pinOrder: pinOrder,
        isArchived: isArchived,
        createdAt: existing.createdAt,
        updatedAt: DateTime.now().toIso8601String(),
      );
      await _personDao.updatePerson(person);
      stats.personsUpdated++;
    } else {
      person = Person(
        name: name,
        isPinned: isPinned,
        pinOrder: pinOrder,
        isArchived: isArchived,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      );
      final personId = await _personDao.insertPerson(person);
      person = person.copyWith(id: personId);
      personsByName[name] = person;
      stats.personsCreated++;
    }

    // Projects: fetch the existing set once for this person.
    final existingProjects =
        await _projectDao.getProjectsForPerson(person.id!, includeArchived: true);
    final projectsByName = <String, Project>{for (final p in existingProjects) p.name: p};

    final projectsData = personData['projects'];
    if (projectsData is List) {
      for (final projectData in projectsData) {
        if (projectData is! Map<String, dynamic>) {
          throw Exception('ملف النسخة الاحتياطية غير صالح: بيانات مشروع غير صحيحة ($name)');
        }
        final project = await _importProject(person.id!, projectData, projectsByName);
        stats.projectsAdded++;
        // Transactions for this project, de-duplicated against the DB once.
        final txnsData = projectData['transactions'];
        if (txnsData is List) {
          await _importTransactions(person.id!, project.id!, txnsData, stats);
        }
      }
    }

    final txnsNoProject = personData['transactions_without_project'];
    if (txnsNoProject is List) {
      await _importTransactions(person.id!, null, txnsNoProject, stats);
    }

    return stats;
  }

  Future<Project> _importProject(
    int personId,
    Map<String, dynamic> projectData,
    Map<String, Project> projectsByName,
  ) async {
    final name = projectData['name'];
    if (name is! String || name.isEmpty) {
      throw Exception('ملف النسخة الاحتياطية غير صالح: اسم مشروع مفقود');
    }
    final budget = (projectData['budget'] as num?)?.toDouble();
    final isArchived = (projectData['is_archived'] as num?)?.toInt() ?? 0;

    final existing = projectsByName[name];
    Project project;
    if (existing != null && existing.id != null) {
      project = Project(
        id: existing.id,
        personId: existing.personId,
        name: existing.name,
        budget: budget, // explicit: a null budget in the backup must clear it
        isArchived: isArchived,
        createdAt: existing.createdAt,
        updatedAt: DateTime.now().toIso8601String(),
      );
      await _projectDao.updateProject(project);
    } else {
      project = Project(
        personId: personId,
        name: name,
        budget: budget,
        isArchived: isArchived,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      );
      final projectId = await _projectDao.insertProject(project);
      project = project.copyWith(id: projectId);
      projectsByName[name] = project;
    }
    return project;
  }

  /// Imports one scope's transactions with a single lookup of existing rows.
  ///
  /// The map doubles as the dedup set: keys already present (in the DB or from
  /// earlier in this backup) are skipped, values let a match be updated.
  Future<void> _importTransactions(
    int personId,
    int? projectId,
    List<dynamic> txnsData,
    _ImportStats stats,
  ) async {
    final existing = projectId != null
        ? await _transactionDao.getTransactionsForProject(projectId)
        : await _transactionDao.getTransactionsWithoutProject(personId);

    final existingByKey = <String, Transaction>{
      for (final txn in existing) _txnKey(txn): txn,
    };

    for (final raw in txnsData) {
      if (raw is! Map<String, dynamic>) {
        throw Exception('ملف النسخة الاحتياطية غير صالح: بيانات معاملة غير صحيحة');
      }
      await _importTransaction(personId, projectId, raw, existingByKey, stats);
    }
  }

  /// Identity key for dedup. Deliberately does NOT include the settlement
  /// state: the same date+amount+type+note is the same row, so treating a
  /// settled/unsettled difference as a new row would double-count money.
  String _txnKey(Transaction txn) =>
      '${txn.date}|${txn.amount}|${txn.type.value}|${txn.note}';

  /// Payment dedup identity: a row of the same size on the same day with the
  /// same label is the same installment, so re-importing is idempotent.
  String _paymentKey(TransactionPayment payment) =>
      paymentDedupeKey(payment.amount, payment.date, payment.note);

  /// Adds the backup's installments for one transaction, skipping any this
  /// device already has.
  ///
  /// A file written before the payment book existed carries no usable
  /// `payments` key; a settled row then becomes one payment for its whole
  /// amount dated with the transaction, which is exactly what the migration
  /// did to existing data. The parent must already be written, and each row is
  /// capped at what is still outstanding, so a corrupt file cannot over-pay.
  /// Rejections are counted, not fatal: one bad row should not abort a
  /// whole restore.
  Future<void> _importPayments(
    int txnId,
    Map<String, dynamic> txnData, {
    required double amount,
    required String date,
    required bool isSettled,
    required _ImportStats stats,
  }) async {
    final raw = txnData['payments'];
    final rawEntries = <Map<String, dynamic>>[
      if (raw is List)
        for (final entry in raw)
          if (entry is Map<String, dynamic>) entry,
    ];
    // No book yet: a settled row becomes one payment for its whole amount,
    // dated with the transaction, exactly as the migration treated old data.
    final entries = rawEntries.isEmpty && isSettled
        ? <Map<String, dynamic>>[
            <String, dynamic>{'amount': amount, 'date': date, 'note': null},
          ]
        : rawEntries;
    if (entries.isEmpty) return;

    final seen = <String>{
      for (final payment
          in await _paymentDao.getPaymentsForTransaction(txnId))
        _paymentKey(payment),
    };

    for (final entry in entries) {
      final entryAmount = (entry['amount'] as num?)?.toDouble();
      final rawDate = entry['date'];
      if (entryAmount == null || entryAmount <= 0 || rawDate is! String) {
        continue;
      }
      final note = entry['note'] as String?;

      final paymentKey = paymentDedupeKey(entryAmount, rawDate, note);
      if (seen.contains(paymentKey)) {
        stats.paymentsSkipped++;
        continue;
      }
      try {
        await _paymentDao.addPayment(
          transactionId: txnId,
          amount: entryAmount,
          date: rawDate,
          note: note,
        );
        seen.add(paymentKey);
        stats.paymentsCreated++;
      } on PaymentValidationException catch (e) {
        stats.paymentsSkipped++;
        debugPrint('[Import] payment skipped: $e');
      }
    }
  }

  Future<void> _importTransaction(
    int personId,
    int? projectId,
    Map<String, dynamic> txnData,
    Map<String, Transaction> existingByKey,
    _ImportStats stats,
  ) async {
    final amount = (txnData['amount'] as num?)?.toDouble();
    if (amount == null) {
      throw Exception('ملف النسخة الاحتياطية غير صالح: مبلغ مفقود');
    }
    final typeRaw = txnData['type'];
    if (typeRaw is! String) {
      throw Exception('ملف النسخة الاحتياطية غير صالح: نوع معاملة مفقود');
    }
    final type = TransactionType.fromString(typeRaw);
    final note = txnData['note'] as String?;
    final date = txnData['date'];
    if (date is! String) {
      throw Exception('ملف النسخة الاحتياطية غير صالح: تاريخ معاملة مفقود');
    }

    // Settlement: absent in backups exported before the 4-state model.
    final isSettled = ((txnData['is_settled'] as num?) ?? 0) == 1;
    final settledAtRaw = txnData['settled_at'];
    final settledAt = settledAtRaw is String
        ? DateTime.tryParse(settledAtRaw)
        : null;
    // Defensive: a settled row without a timestamp falls back to its date.
    final effectiveSettledAt = isSettled
        ? (settledAt ?? DateTime.tryParse(date) ?? DateTime.now())
        : null;

    // Same rule as before: same date + amount + type + note within the scope.
    final key = '$date|$amount|${type.value}|$note';
    final match = existingByKey[key];
    if (match != null) {
      // The row already exists: adopt the backup's settlement state so a
      // restore fully reflects the file instead of half of it.
      if (match.isSettled != isSettled || match.settledAt != effectiveSettledAt) {
        await _transactionDao.updateTransaction(
          match,
          match.copyWith(isSettled: isSettled, settledAt: effectiveSettledAt),
        );
      }
      await _importPayments(
        match.id!,
        txnData,
        amount: amount,
        date: date,
        isSettled: isSettled,
        stats: stats,
      );
      // The payment book, not the backup's flag, decides the final status.
      await _paymentDao.syncStatus(match.id!);
      stats.txnsSkipped++;
      return;
    }

    final transaction = Transaction(
      personId: personId,
      projectId: projectId,
      amount: amount,
      type: type,
      note: note,
      date: date,
      createdAt: DateTime.now().toIso8601String(),
      isSettled: isSettled,
      settledAt: effectiveSettledAt,
    );

    final txnId = await _transactionDao.insertTransaction(transaction);
    stats.txnsCreated++;
    // Register it so a repeated row later in the same backup is skipped.
    existingByKey[key] = transaction.copyWith(id: txnId);

    await _importPayments(
      txnId,
      txnData,
      amount: amount,
      date: date,
      isSettled: isSettled,
      stats: stats,
    );
    await _paymentDao.syncStatus(txnId);

    final attachmentsBase64 = txnData['attachments_base64'];
    if (attachmentsBase64 is! List) return;

    for (final base64String in attachmentsBase64) {
      try {
        if (base64String is! String) {
          throw const FormatException('attachment is not a string');
        }
        final bytes = base64Decode(base64String);
        final savedFile = await _imageStorage.saveBytesToAttachments(bytes);
        final attachment = TransactionAttachment(
          transactionId: txnId,
          filePath: savedFile.path,
          createdAt: DateTime.now().toIso8601String(),
        );
        await _attachmentDao.insertAttachment(attachment);
        stats.attachmentsSaved++;
      } catch (e) {
        // Previously swallowed silently - a lost receipt would go unnoticed.
        stats.attachmentsFailed++;
        debugPrint('[Import] attachment skipped: $e');
      }
    }
  }
}

class _ImportStats {
  int personsCreated = 0;
  int personsUpdated = 0;
  int projectsAdded = 0;
  int txnsCreated = 0;
  int txnsSkipped = 0;
  int attachmentsSaved = 0;
  int attachmentsFailed = 0;
  int paymentsCreated = 0;
  int paymentsSkipped = 0;
}
