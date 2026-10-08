import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsService {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  static const _keyGoogleAccountEmail = 'google_account_email';
  static const _keyGoogleAccountId = 'google_account_id';
  static const _keyLastBackupAt = 'last_backup_at';
  static const _keyAutoBackupEnabled = 'auto_backup_enabled';
  static const _keyDriveBackupFileId = 'drive_backup_file_id';
  // Backup settings (Issue 3)
  static const _keyBackupMode = 'backup_mode';
  static const _keyBackupDailyTime = 'backup_daily_time';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _sharedPrefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // Google Account
  Future<String?> get googleAccountEmail async {
    final prefs = await _sharedPrefs;
    return prefs.getString(_keyGoogleAccountEmail);
  }

  Future<void> setGoogleAccountEmail(String? email) async {
    final prefs = await _sharedPrefs;
    if (email == null) {
      await prefs.remove(_keyGoogleAccountEmail);
    } else {
      await prefs.setString(_keyGoogleAccountEmail, email);
    }
  }

  Future<String?> get googleAccountId async {
    final prefs = await _sharedPrefs;
    return prefs.getString(_keyGoogleAccountId);
  }

  Future<void> setGoogleAccountId(String? id) async {
    final prefs = await _sharedPrefs;
    if (id == null) {
      await prefs.remove(_keyGoogleAccountId);
    } else {
      await prefs.setString(_keyGoogleAccountId, id);
    }
  }

  Future<void> clearGoogleAccount() async {
    final prefs = await _sharedPrefs;
    await prefs.remove(_keyGoogleAccountEmail);
    await prefs.remove(_keyGoogleAccountId);
  }

  // Last Backup
  Future<DateTime?> get lastBackupAt async {
    final prefs = await _sharedPrefs;
    final str = prefs.getString(_keyLastBackupAt);
    if (str == null) return null;
    return DateTime.parse(str).toLocal();
  }

  Future<void> setLastBackupAt(DateTime dateTime) async {
    final prefs = await _sharedPrefs;
    await prefs.setString(_keyLastBackupAt, dateTime.toUtc().toIso8601String());
  }

  // Auto Backup (legacy - kept for compatibility)
  Future<bool> get autoBackupEnabled async {
    final prefs = await _sharedPrefs;
    return prefs.getBool(_keyAutoBackupEnabled) ?? true;
  }

  Future<void> setAutoBackupEnabled(bool enabled) async {
    final prefs = await _sharedPrefs;
    await prefs.setBool(_keyAutoBackupEnabled, enabled);
  }

  // Drive Backup File ID
  Future<String?> get driveBackupFileId async {
    final prefs = await _sharedPrefs;
    return prefs.getString(_keyDriveBackupFileId);
  }

  Future<void> setDriveBackupFileId(String? fileId) async {
    final prefs = await _sharedPrefs;
    if (fileId == null) {
      await prefs.remove(_keyDriveBackupFileId);
    } else {
      await prefs.setString(_keyDriveBackupFileId, fileId);
    }
  }

  // Backup Mode (Issue 3)
  // 0 = Off, 1 = After every change, 2 = Daily
  Future<int> get backupMode async {
    final prefs = await _sharedPrefs;
    return prefs.getInt(_keyBackupMode) ?? 0;
  }

  Future<void> setBackupMode(int mode) async {
    final prefs = await _sharedPrefs;
    await prefs.setInt(_keyBackupMode, mode);
  }

  // Daily backup time (HH:mm format)
  Future<String?> get backupDailyTime async {
    final prefs = await _sharedPrefs;
    return prefs.getString(_keyBackupDailyTime);
  }

  Future<void> setBackupDailyTime(String? time) async {
    final prefs = await _sharedPrefs;
    if (time == null) {
      await prefs.remove(_keyBackupDailyTime);
    } else {
      await prefs.setString(_keyBackupDailyTime, time);
    }
  }

  // Clear all
  Future<void> clearAll() async {
    final prefs = await _sharedPrefs;
    await prefs.clear();
  }
}