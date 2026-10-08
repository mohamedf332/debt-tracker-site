import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';
import '../services/settings_service.dart';
import '../services/google_auth_service.dart';
import '../services/drive_backup_service.dart';
import '../services/export_service.dart';
import '../services/import_service.dart';
import 'persons_provider.dart' as persons_provider;

const dailyBackupTask = 'dailyBackupTask';

class SettingsState {
  final bool isGoogleSignedIn;
  final String? googleAccountEmail;
  final DateTime? lastBackupAt;
  final bool autoBackupEnabled;
  final bool isLoading;
  final String? error;
  // Backup settings (Issue 3)
  final int backupMode; // 0 = Off, 1 = After every change, 2 = Daily
  final String? backupDailyTime; // HH:mm format

  const SettingsState({
    this.isGoogleSignedIn = false,
    this.googleAccountEmail,
    this.lastBackupAt,
    this.autoBackupEnabled = true,
    this.isLoading = false,
    this.error,
    this.backupMode = 0,
    this.backupDailyTime,
  });

  SettingsState copyWith({
    bool? isGoogleSignedIn,
    Object? googleAccountEmail = _unset,
    Object? lastBackupAt = _unset,
    bool? autoBackupEnabled,
    bool? isLoading,
    Object? error = _unset,
    int? backupMode,
    Object? backupDailyTime = _unset,
  }) {
    return SettingsState(
      isGoogleSignedIn: isGoogleSignedIn ?? this.isGoogleSignedIn,
      googleAccountEmail: googleAccountEmail == _unset
          ? this.googleAccountEmail
          : googleAccountEmail as String?,
      lastBackupAt: lastBackupAt == _unset
          ? this.lastBackupAt
          : lastBackupAt as DateTime?,
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      isLoading: isLoading ?? this.isLoading,
      error: error == _unset ? this.error : error as String?,
      backupMode: backupMode ?? this.backupMode,
      backupDailyTime: backupDailyTime == _unset
          ? this.backupDailyTime
          : backupDailyTime as String?,
    );
  }
}

/// Sentinel so `copyWith(error: null)` actually clears the error instead of
/// being swallowed by `error ?? this.error`.
const Object _unset = Object();

class SettingsNotifier extends StateNotifier<SettingsState> {
  final SettingsService _settingsService;
  final GoogleAuthService _googleAuth;
  final DriveBackupService _driveBackup;
  final Ref _ref;

  SettingsNotifier(
    this._settingsService,
    this._googleAuth,
    this._driveBackup,
    this._ref,
  ) : super(const SettingsState()) {
    _init();
  }

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);
    try {
      final email = await _settingsService.googleAccountEmail;
      final lastBackup = await _settingsService.lastBackupAt;
      final autoBackup = await _settingsService.autoBackupEnabled;
      final backupMode = await _settingsService.backupMode;
      final backupDailyTime = await _settingsService.backupDailyTime;

      state = state.copyWith(
        isGoogleSignedIn: email != null,
        googleAccountEmail: email,
        lastBackupAt: lastBackup,
        autoBackupEnabled: autoBackup,
        backupMode: backupMode,
        backupDailyTime: backupDailyTime,
        isLoading: false,
      );

      // Listen to auth state changes
      _googleAuth.onAuthStateChanged.listen((account) {
        if (account != null) {
          state = state.copyWith(
            isGoogleSignedIn: true,
            googleAccountEmail: account.email,
          );
          _settingsService.setGoogleAccountEmail(account.email);
          _settingsService.setGoogleAccountId(account.id);
          debugPrint('[Settings] auth listener -> saved ${account.email}/${account.id}');
        } else {
          state = state.copyWith(
            isGoogleSignedIn: false,
            googleAccountEmail: null,
          );
        }
      });

      // Try silent sign in
      await _googleAuth.signInSilently();

      // Schedule daily backup if mode is Daily and user is signed in
      if (backupMode == 2 && email != null) {
        await _scheduleDailyBackup(backupDailyTime);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> _scheduleDailyBackup(String? timeParam) async {
    final isSignedIn = _googleAuth.isSignedIn;
    if (!isSignedIn) return;

    final time = timeParam ?? '03:00';
    await Workmanager().cancelByUniqueName(dailyBackupTask);
    await Workmanager().registerPeriodicTask(
      'dailyBackupTask',
      dailyBackupTask,
      frequency: const Duration(hours: 24),
      initialDelay: _calculateInitialDelay(time),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresCharging: false,
        requiresBatteryNotLow: true,
      ),
    );
    // Refresh the providers after scheduling
    _ref.read(persons_provider.dataVersionProvider.notifier).state++;
  }

  Future<void> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final account = await _googleAuth.signIn();
      if (account != null) {
        // Persist immediately so the session survives an app restart.
        await _settingsService.setGoogleAccountEmail(account.email);
        await _settingsService.setGoogleAccountId(account.id);
        final savedEmail = await _settingsService.googleAccountEmail;
        final savedId = await _settingsService.googleAccountId;
        debugPrint(
            '[Settings] Google account persisted. email=$savedEmail id=$savedId');
        // Update UI state straight away.
        state = state.copyWith(
          isGoogleSignedIn: true,
          googleAccountEmail: account.email,
          isLoading: false,
          error: null,
        );
      } else {
        // User dismissed the dialog - not an error.
        debugPrint('[Settings] Google sign-in cancelled by user');
        state = state.copyWith(isLoading: false, error: null);
      }
    } catch (e, st) {
      debugPrint('[Settings] signInWithGoogle FAILED: $e\n$st');
      state = state.copyWith(
        isLoading: false,
        error: GoogleAuthService.describeError(e),
      );
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _googleAuth.signOut();
      await _settingsService.clearGoogleAccount();
      state = state.copyWith(
        isGoogleSignedIn: false,
        googleAccountEmail: null,
        isLoading: false,
        error: null,
      );
      debugPrint('[Settings] Signed out, account cleared from settings');
    } catch (e, st) {
      debugPrint('[Settings] signOut FAILED: $e\n$st');
      state = state.copyWith(isLoading: false, error: 'فشل تسجيل الخروج: $e');
    }
  }

  Future<void> switchAccount() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _googleAuth.signOut();
      final account = await _googleAuth.signIn();
      if (account != null) {
        await _settingsService.setGoogleAccountEmail(account.email);
        await _settingsService.setGoogleAccountId(account.id);
        state = state.copyWith(
          isGoogleSignedIn: true,
          googleAccountEmail: account.email,
          isLoading: false,
          error: null,
        );
        debugPrint('[Settings] Switched to ${account.email}');
      } else {
        await _settingsService.clearGoogleAccount();
        state = state.copyWith(
          isGoogleSignedIn: false,
          googleAccountEmail: null,
          isLoading: false,
          error: null,
        );
        debugPrint('[Settings] Account switch cancelled by user');
      }
    } catch (e, st) {
      debugPrint('[Settings] switchAccount FAILED: $e\n$st');
      state = state.copyWith(
        isLoading: false,
        error: GoogleAuthService.describeError(e),
      );
    }
  }

  Future<void> toggleAutoBackup(bool enabled) async {
    try {
      await _settingsService.setAutoBackupEnabled(enabled);
      state = state.copyWith(autoBackupEnabled: enabled);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> setBackupMode(int mode) async {
    try {
      await _settingsService.setBackupMode(mode);
      state = state.copyWith(backupMode: mode);
      
      // Schedule or cancel daily backup task
      if (mode == 2) {
        // Daily mode - schedule daily backup
        await Workmanager().registerPeriodicTask(
          'dailyBackupTask',
          dailyBackupTask,
          frequency: const Duration(hours: 24),
          initialDelay: _calculateInitialDelay(),
          constraints: Constraints(
            networkType: NetworkType.connected,
            requiresCharging: false,
            requiresBatteryNotLow: true,
          ),
        );
      } else {
        // Cancel daily backup task
        await Workmanager().cancelByUniqueName(dailyBackupTask);
      }
      // Refresh providers after mode change
      _ref.read(persons_provider.dataVersionProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> setBackupDailyTime(String? time) async {
    try {
      await _settingsService.setBackupDailyTime(time);
      state = state.copyWith(backupDailyTime: time);
      
      // Reschedule daily backup with new time if in daily mode
      if (state.backupMode == 2 && time != null) {
        await Workmanager().cancelByUniqueName(dailyBackupTask);
        await Workmanager().registerPeriodicTask(
          'dailyBackupTask',
          dailyBackupTask,
          frequency: const Duration(hours: 24),
          initialDelay: _calculateInitialDelay(time),
          constraints: Constraints(
            networkType: NetworkType.connected,
            requiresCharging: false,
            requiresBatteryNotLow: true,
          ),
        );
      }
      // Refresh providers after time change
      _ref.read(persons_provider.dataVersionProvider.notifier).state++;
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Duration _calculateInitialDelay([String? time]) {
    final now = DateTime.now();
    final targetTime = time ?? state.backupDailyTime ?? '03:00';
    final parts = targetTime.split(':');
    final targetHour = int.parse(parts[0]);
    final targetMinute = int.parse(parts[1]);
    
    var targetDateTime = DateTime(now.year, now.month, now.day, targetHour, targetMinute);
    if (targetDateTime.isBefore(now)) {
      targetDateTime = targetDateTime.add(const Duration(days: 1));
    }
    
    return targetDateTime.difference(now);
  }

  Future<void> backupNow() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final error = await _driveBackup.backupNow();
      if (error == null) {
        final lastBackup = await _settingsService.lastBackupAt;
        state = state.copyWith(lastBackupAt: lastBackup, isLoading: false);
        debugPrint('[Settings] backup OK at $lastBackup');
      } else {
        debugPrint('[Settings] backup failed: $error');
        state = state.copyWith(isLoading: false, error: error);
      }
    } catch (e, st) {
      debugPrint('[Settings] backupNow threw: $e\n$st');
      state = state.copyWith(isLoading: false, error: 'فشل النسخ الاحتياطي: $e');
    }
  }

  Future<void> restoreFromBackup() async {
    state = state.copyWith(isLoading: true, error: null);
    String? error;
    try {
      error = await _driveBackup.restoreFromBackup();
      if (error == null) debugPrint('[Settings] restore OK');
      else debugPrint('[Settings] restore failed: $error');
    } catch (e, st) {
      debugPrint('[Settings] restoreFromBackup threw: $e\n$st');
      error = 'فشل الاسترجاع: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}';
    } finally {
      // ALWAYS refresh. The import writes rows as it goes, so if it failed
      // partway the DB has changed and the UI must not wait for a restart.
      _ref.read(persons_provider.dataVersionProvider.notifier).state++;
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<void> refresh() async {
    final lastBackup = await _settingsService.lastBackupAt;
    state = state.copyWith(lastBackupAt: lastBackup);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  final settingsService = ref.watch(settingsServiceProvider);
  final googleAuth = ref.watch(googleAuthProvider);
  final driveBackup = ref.watch(driveBackupProvider);

  return SettingsNotifier(settingsService, googleAuth, driveBackup, ref);
});

final settingsServiceProvider = Provider((ref) => SettingsService.instance);
final googleAuthProvider = Provider((ref) => GoogleAuthService.instance);
final driveBackupProvider = Provider((ref) => DriveBackupService.instance);
final exportServiceProvider = Provider((ref) => ExportService.instance);
final importServiceProvider = Provider((ref) => ImportService.instance);