import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../models/person.dart';
import '../models/project.dart';
import '../models/transaction.dart';
import '../models/transaction_attachment.dart';
import '../db/person_dao.dart';
import '../db/project_dao.dart';
import '../db/transaction_dao.dart';
import '../db/attachment_dao.dart';
import '../db/payment_dao.dart';

class ExportService {
  ExportService._();

  static final ExportService instance = ExportService._();

  final PersonDao _personDao = PersonDao();
  final ProjectDao _projectDao = ProjectDao();
  final TransactionDao _transactionDao = TransactionDao();
  final AttachmentDao _attachmentDao = AttachmentDao();
  final PaymentDao _paymentDao = PaymentDao();

  /// Export all data (all persons, including archived) - internal use without UI feedback
  Future<void> exportAllData() async {
    final persons = await _personDao.getAllPersons(includeArchived: true);
    final exportData = await buildExportData(persons);
    await _saveAndShareExport(exportData, 'debt-tracker');
  }

  /// Builds full export data including all persons (active + archived) with their projects, transactions, and attachments
  Future<Map<String, dynamic>> buildFullExportData() async {
    final persons = await _personDao.getAllPersons(includeArchived: true);
    return buildExportData(persons);
  }

  /// Export single person's data - internal use without UI feedback
  Future<void> exportPersonData(int personId) async {
    final person = await _personDao.getPerson(personId);
    if (person == null) return;

    final exportData = await buildExportData([person]);
    await _saveAndShareExport(exportData, 'debt-tracker-${person.name.replaceAll(' ', '_')}');
  }

  Future<Map<String, dynamic>> buildExportData(List<Person> persons) async {
    final personsData = <Map<String, dynamic>>[];

    for (final person in persons) {
      final projects = await _projectDao.getProjectsForPerson(person.id!, includeArchived: true);
      final transactionsWithoutProject = await _transactionDao.getTransactionsWithoutProject(person.id!);

      final projectsData = <Map<String, dynamic>>[];
      for (final project in projects) {
        final transactions = await _transactionDao.getTransactionsForProject(project.id!);
        final transactionsData = <Map<String, dynamic>>[];

        for (final txn in transactions) {
          transactionsData.add(await _transactionPayload(txn));
        }

        projectsData.add({
          'name': project.name,
          'budget': project.budget,
          'is_archived': project.isArchived,
          'transactions': transactionsData,
        });
      }

      final transactionsWithoutProjectData = <Map<String, dynamic>>[];
      for (final txn in transactionsWithoutProject) {
        transactionsWithoutProjectData.add(await _transactionPayload(txn));
      }

      personsData.add({
        'name': person.name,
        'is_pinned': person.isPinned,
        'pin_order': person.pinOrder,
        'is_archived': person.isArchived,
        'projects': projectsData,
        'transactions_without_project': transactionsWithoutProjectData,
      });
    }

    return {
      'export_version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'persons': personsData,
    };
  }

  /// One transaction as it appears in the backup file.
  ///
  /// `payments` is optional on import, so a file written before the payment
  /// book existed still restores: a settled row becomes one full payment, an
  /// unsettled one stays empty.
  Future<Map<String, dynamic>> _transactionPayload(Transaction txn) async {
    final attachments = await _attachmentDao.getAttachmentsForTransaction(txn.id!);
    final attachmentsBase64 = <String>[];
    for (final att in attachments) {
      final file = File(att.filePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        attachmentsBase64.add(base64Encode(bytes));
      }
    }

    final payments = await _paymentDao.getPaymentsForTransaction(txn.id!);

    return {
      'amount': txn.amount,
      'type': txn.type.value,
      'note': txn.note,
      'date': txn.date,
      // Optional on import: missing keys in an older backup => unsettled.
      'is_settled': txn.isSettled ? 1 : 0,
      'settled_at': txn.settledAt?.toIso8601String(),
      'payments': [
        for (final payment in payments)
          {
            'amount': payment.amount,
            'date': payment.date,
            'note': payment.note,
          },
      ],
      'attachments_base64': attachmentsBase64,
    };
  }

  /// Saves the export JSON using file_picker's saveFile dialog on all platforms.
  /// Returns true if saved, false if user cancelled, throws on error.
  Future<bool> saveExportToDevice(String jsonString) async {
    final stamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final fileName = 'debt-tracker-$stamp.json';
    final bytes = Uint8List.fromList(utf8.encode(jsonString));
    final uri = await FilePickerPlatform.instance.saveFile(
      dialogTitle: 'حفظ النسخة الاحتياطية',
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/json',
    );
    return uri != null; // false = user cancelled
  }

  /// Saves the export JSON using file_picker's saveFile dialog (Android/iOS/desktop).
  /// Falls back to share sheet if save fails or is cancelled.
  ///
  /// [data] - The export data to save
  /// [fileNamePrefix] - Prefix for the filename (e.g., 'debt-tracker' or 'debt-tracker-PersonName')
  /// [context] - Optional BuildContext for showing SnackBars (can be null for internal use)
  Future<void> _saveAndShareExport(
    Map<String, dynamic> data,
    String fileNamePrefix, {
    BuildContext? context,
  }) async {
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    final timestamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final fileName = '${fileNamePrefix}_$timestamp.json';

    try {
      final saved = await saveExportToDevice(jsonString);
      if (saved) {
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم حفظ الملف في مجلد Downloads')),
          );
        }
      } else {
        // User cancelled - fall back to share sheet
        await _fallbackToShare(jsonString, fileName, context);
      }
    } catch (e) {
      // On any error, fall back to share sheet
      await _fallbackToShare(jsonString, fileName, context);
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحفظ المباشر، تم فتح ورقة المشاركة: $e')),
        );
      }
    }
  }

  Future<void> _fallbackToShare(String jsonString, String fileName, BuildContext? context) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsString(jsonString);
      await Share.shareXFiles(
        [XFile(tempFile.path)],
        text: 'دفتر الديون - تصدير بيانات',
      );
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم فتح ورقة المشاركة')),
        );
      }
    } catch (shareError) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل التصدير: $shareError')),
        );
      }
    }
  }

  /// Export all data with UI feedback (loading indicator, SnackBar)
  Future<void> exportAllDataWithUI(BuildContext context) async {
    // Show loading indicator
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 16),
            Text('جاري التصدير...'),
          ],
        ),
        duration: Duration(days: 1), // Keep until dismissed
      ),
    );

    try {
      await exportAllData();
      if (context.mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('تم تصدير البيانات بنجاح')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('خطأ في التصدير: $e')),
        );
      }
    }
  }

  /// Export person data with UI feedback
  Future<void> exportPersonDataWithUI(BuildContext context, int personId) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 16),
            Text('جاري التصدير...'),
          ],
        ),
        duration: Duration(days: 1),
      ),
    );

    try {
      await exportPersonData(personId);
      if (context.mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('تم تصدير البيانات بنجاح')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('خطأ في التصدير: $e')),
        );
      }
    }
  }

  /// Share export file (for explicit share button)
  Future<void> shareExportFile(BuildContext context, String fileNamePrefix, Map<String, dynamic> data) async {
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    final timestamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final fileName = '${fileNamePrefix}_$timestamp.json';

    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsString(jsonString);

      await Share.shareXFiles(
        [XFile(tempFile.path)],
        text: 'دفتر الديون - تصدير بيانات',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل المشاركة: $e')),
        );
      }
    }
  }
}