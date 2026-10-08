import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workmanager/workmanager.dart';

import 'db/db_helper.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/drive_backup_service.dart';
import 'services/settings_service.dart';
import 'services/google_auth_service.dart';

const dailyBackupTask = 'dailyBackupTask';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == dailyBackupTask) {
      // Initialize services for background execution
      await DatabaseHelper.initialize();
      await initializeDateFormatting('ar_EG', null);

      final settings = SettingsService.instance;
      final googleAuth = GoogleAuthService.instance;
      final driveBackup = DriveBackupService.instance;

      // Check if backup mode is Daily
      final backupMode = await settings.backupMode;
      if (backupMode != 2) {
        debugPrint('[BG] dailyBackupTask: mode=$backupMode, skipping');
        return true;
      }

      // This isolate starts fresh, so there is no signed-in account yet.
      // Without this the backup would silently no-op every single time.
      var signedIn = googleAuth.isSignedIn;
      if (!signedIn) {
        debugPrint('[BG] dailyBackupTask: no session, trying silent sign-in');
        final account = await googleAuth.signInSilently();
        signedIn = account != null;
      }
      if (!signedIn) {
        debugPrint('[BG] dailyBackupTask: not signed in, skipping');
        return true;
      }

      // Run backup
      final error = await driveBackup.backupNow();
      debugPrint('[BG] dailyBackupTask finished: ${error ?? "OK"}');
    }
    return true;
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize database factory for desktop platforms
  await DatabaseHelper.initialize();

  // Initialize Arabic locale for date formatting
  await initializeDateFormatting('ar_EG', null);

  // Initialize Google Fonts
  await GoogleFonts.pendingFonts([GoogleFonts.cairo()]);

  // Initialize Workmanager
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'دفتر المعاملات',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      darkTheme: AppTheme.light,
      themeMode: ThemeMode.light,
      builder: (context, child) =>
          SafeArea(top: false, child: child ?? const SizedBox.shrink()),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: HomeScreen(),
      ),
    );
  }
}
