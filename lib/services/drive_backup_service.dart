import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/export_service.dart';
import '../services/import_service.dart';
import '../services/google_auth_service.dart';
import '../services/settings_service.dart';

/// Google Drive backup.
///
/// Every public method returns `null` on success or a user-facing Arabic error
/// message on failure. Failures are always logged - never swallowed.
class DriveBackupService {
  DriveBackupService._();

  static final DriveBackupService instance = DriveBackupService._();

  final ExportService _exportService = ExportService.instance;
  final ImportService _importService = ImportService.instance;
  final GoogleAuthService _googleAuth = GoogleAuthService.instance;
  final SettingsService _settings = SettingsService.instance;

  static const _driveApiBase = 'https://www.googleapis.com/drive/v3';
  // Uploads (files.create / files.update with uploadType) MUST use the
  // /upload/ host. Without it Drive treats the body as a plain JSON metadata
  // object and fails with "Invalid JSON payload ... Unable to parse number".
  static const _driveUploadBase = 'https://www.googleapis.com/upload/drive/v3';
  static const _backupFileName = 'debt_tracker_backup.json';

  Timer? _debounce;

  // ---------------------------------------------------------------- backup

  /// Returns `null` on success, otherwise an Arabic error message.
  Future<String?> backupNow() async {
    if (_googleAuth.currentUser == null) {
      debugPrint('[DriveBackup] backup aborted: no signed-in account');
      return 'يجب تسجيل الدخول بجوجل أولاً';
    }

    try {
      final accessToken = await _requireAccessToken();
      if (accessToken == null) {
        return 'تعذر الحصول على صلاحية الوصول إلى Google Drive';
      }

      final exportData = await _exportService.buildFullExportData();
      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      debugPrint('[DriveBackup] payload ready: ${jsonString.length} bytes');

      // 1. Update the file we recorded last time, if any.
      var fileId = await _settings.driveBackupFileId;
      if (fileId != null) {
        final res = await _patchFile(fileId, accessToken, jsonString);
        if (res.statusCode == 200) {
          debugPrint('[DriveBackup] updated existing file $fileId');
          return await _markSuccess();
        }
        debugPrint('[DriveBackup] PATCH $fileId -> ${res.statusCode} ${res.body}');
        // Stored id no longer usable (deleted / other account) - recreate.
        if (res.statusCode == 404 || res.statusCode == 403) {
          await _settings.setDriveBackupFileId(null);
          fileId = null;
        } else {
          return _describeHttp('النسخ الاحتياطي', res);
        }
      }

      // 2. Recover an existing backup we may have lost the id for.
      final found = await _findExistingFile(accessToken);
      if (found != null) {
        final res = await _patchFile(found, accessToken, jsonString);
        if (res.statusCode == 200) {
          await _settings.setDriveBackupFileId(found);
          debugPrint('[DriveBackup] adopted existing file $found');
          return await _markSuccess();
        }
        debugPrint('[DriveBackup] PATCH(recovered) $found -> ${res.statusCode}');
      }

      // 3. Create a brand new backup file.
      final res = await _createFile(accessToken, jsonString);
      if (res.statusCode != 200) {
        debugPrint('[DriveBackup] CREATE -> ${res.statusCode} ${res.body}');
        return _describeHttp('النسخ الاحتياطي', res);
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final newId = data['id'] as String?;
      if (newId == null) {
        debugPrint('[DriveBackup] CREATE returned no id: ${res.body}');
        return 'فشل النسخ الاحتياطي: استجابة غير متوقعة من Google Drive';
      }
      await _settings.setDriveBackupFileId(newId);
      debugPrint('[DriveBackup] created file $newId');
      return await _markSuccess();
    } catch (e, st) {
      debugPrint('[DriveBackup] backup FAILED: $e\n$st');
      return 'خطأ في النسخ الاحتياطي: ${_clean(e)}';
    }
  }

  String _clean(Object e) =>
      e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  Future<String?> _markSuccess() async {
    await _settings.setLastBackupAt(DateTime.now());
    debugPrint('[DriveBackup] success, lastBackupAt updated');
    return null;
  }

  // --------------------------------------------------------------- restore

  /// Returns `null` on success, otherwise an Arabic error message.
  Future<String?> restoreFromBackup() async {
    if (_googleAuth.currentUser == null) {
      debugPrint('[DriveBackup] restore aborted: no signed-in account');
      return 'يجب تسجيل الدخول بجوجل أولاً';
    }

    try {
      final accessToken = await _requireAccessToken();
      if (accessToken == null) {
        return 'تعذر الحصول على صلاحية الوصول إلى Google Drive';
      }

      var fileId = await _settings.driveBackupFileId;
      if (fileId == null) {
        fileId = await _findExistingFile(accessToken);
        if (fileId == null) {
          debugPrint('[DriveBackup] restore: no backup file found in Drive');
          return 'لا توجد نسخة احتياطية في Google Drive';
        }
        await _settings.setDriveBackupFileId(fileId);
        debugPrint('[DriveBackup] restore: recovered file id $fileId');
      }

      final res = await http.get(
        Uri.parse('$_driveApiBase/files/$fileId?alt=media'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (res.statusCode == 404 || res.statusCode == 403) {
        debugPrint('[DriveBackup] restore GET $fileId -> ${res.statusCode}');
        await _settings.setDriveBackupFileId(null);
        return 'النسخة الاحتياطية غير موجودة في Google Drive (ربما حُذفت)';
      }
      if (res.statusCode != 200) {
        debugPrint('[DriveBackup] restore GET -> ${res.statusCode} ${res.body}');
        return _describeHttp('الاسترجاع', res);
      }

      final jsonString = res.body;
      if (jsonString.isEmpty) {
        debugPrint('[DriveBackup] restore: empty body');
        return 'النسخة الاحتياطية في Google Drive فارغة';
      }

      // Import directly from the string - the previous temp-file round trip
      // only added a failure point (and an unused read/write).
      await _importService.importFromJsonString(jsonString);
      debugPrint('[DriveBackup] restore success (${jsonString.length} bytes)');
      return null;
    } catch (e, st) {
      debugPrint('[DriveBackup] restore FAILED: $e\n$st');
      return 'خطأ في الاسترجاع: ${_clean(e)}';
    }
  }

  // ----------------------------------------------------------- auto backup

  Future<void> checkAndRunAutoBackup() async {
    final backupMode = await _settings.backupMode;
    if (backupMode != 2) return; // Daily mode only

    final lastBackup = await _settings.lastBackupAt;
    if (lastBackup != null &&
        DateTime.now().difference(lastBackup).inHours < 24) {
      return;
    }
    if (!_googleAuth.isSignedIn) {
      debugPrint('[DriveBackup] auto-backup skipped: not signed in');
      return;
    }
    debugPrint('[DriveBackup] running daily auto-backup');
    await backupNow();
  }

  /// Debounced backup for "after every change" mode (mode 1).
  ///
  /// Safe to call after every mutation: the previous pending timer is
  /// cancelled, so a burst of edits produces a single upload ~30s later.
  void triggerBackupAfterChange() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 30), () async {
      try {
        final mode = await _settings.backupMode;
        if (mode != 1) return;
        if (!_googleAuth.isSignedIn) return;
        debugPrint('[DriveBackup] debounced change-backup firing');
        await backupNow();
      } catch (e, st) {
        debugPrint('[DriveBackup] debounced backup FAILED: $e\n$st');
      }
    });
  }

  // --------------------------------------------------------------- helpers

  /// Returns a usable access token, re-authenticating silently if needed.
  Future<String?> _requireAccessToken() async {
    var token = await _googleAuth.getAccessToken();
    if (token != null) return token;

    debugPrint('[DriveBackup] no access token, attempting silent re-auth');
    final account = await _googleAuth.signInSilently();
    if (account == null) {
      debugPrint('[DriveBackup] silent re-auth returned no account');
      return null;
    }
    token = await _googleAuth.getAccessToken();
    if (token == null) {
      debugPrint('[DriveBackup] still no access token after re-auth');
    }
    return token;
  }

  /// Finds a backup file previously created by this app.
  ///
  /// Works with the `drive.file` scope, which only exposes files the app
  /// created - exactly the set we care about.
  Future<String?> _findExistingFile(String accessToken) async {
    final query = Uri.encodeQueryComponent(
        "name = '$_backupFileName' and trashed = false");
    final uri = Uri.parse(
        '$_driveApiBase/files?q=$query&fields=files(id,modifiedTime)&pageSize=5');
    try {
      final res = await http
          .get(uri, headers: {'Authorization': 'Bearer $accessToken'});
      if (res.statusCode != 200) {
        debugPrint('[DriveBackup] search -> ${res.statusCode} ${res.body}');
        return null;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final files = (data['files'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (files.isEmpty) {
        debugPrint('[DriveBackup] search: no existing backup file');
        return null;
      }
      // Prefer the most recently modified backup.
      files.sort((a, b) => (b['modifiedTime'] ?? '').compareTo(a['modifiedTime'] ?? ''));
      final id = files.first['id'] as String?;
      debugPrint('[DriveBackup] search: found existing file $id');
      return id;
    } catch (e) {
      debugPrint('[DriveBackup] search failed: $e');
      return null;
    }
  }

  Future<http.Response> _patchFile(
      String fileId, String accessToken, String jsonString) {
    return http.patch(
      Uri.parse('$_driveUploadBase/files/$fileId?uploadType=media'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonString,
    );
  }

  Future<http.Response> _createFile(String accessToken, String jsonString) {
    return http.post(
      Uri.parse('$_driveUploadBase/files?uploadType=multipart'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'multipart/related; boundary=boundary',
      },
      body: _createMultipartBody(jsonString),
    );
  }

  String _createMultipartBody(String jsonString) {
    const boundary = 'boundary';
    final buffer = StringBuffer();
    buffer.write('--$boundary\r\n');
    buffer.write('Content-Type: application/json; charset=UTF-8\r\n\r\n');
    buffer.write('{"name": "$_backupFileName", "mimeType": "application/json"}\r\n');
    buffer.write('--$boundary\r\n');
    buffer.write('Content-Type: application/json\r\n\r\n');
    buffer.write(jsonString);
    buffer.write('\r\n--$boundary--\r\n');
    return buffer.toString();
  }

  String _describeHttp(String action, http.Response res) {
    String reason;
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final err = body['error'] as Map<String, dynamic>?;
      reason = err?['message']?.toString() ?? res.body;
    } catch (_) {
      reason = res.body;
    }
    if (reason.length > 200) reason = '${reason.substring(0, 200)}...';

    switch (res.statusCode) {
      case 401:
        return '$action: انتهت صلاحية الجلسة (401). سجّل الخروج ثم الدخول من جديد. $reason';
      case 403:
        return '$action: مرفوض (403) - تأكد أن Google Drive API مفعّل وأن الحساب مضاف كـ test user. $reason';
      case 404:
        return '$action: الملف غير موجود (404). $reason';
      case 429:
        return '$action: تم تجاوز الحد المسموح (429). حاول لاحقاً. $reason';
      default:
        return '$action فشل (${res.statusCode}): $reason';
    }
  }
}
