import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/date_formatter.dart';
import '../../providers/settings_provider.dart';
import '../../providers/persons_provider.dart' hide imageStorageProvider;
import '../../services/export_service.dart';
import '../../services/import_service.dart';
import '../../services/image_storage_service.dart';
import '../../db/db_helper.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    // Surface any sign-in / backup failure as a SnackBar (no silent failures).
    ref.listen<SettingsState>(settingsProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(next.error!),
              backgroundColor: AppColors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    });

    final settingsState = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Account Section
          Text('الحساب', style: AppTextStyles.titleMedium),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                if (!settingsState.isGoogleSignedIn) ...[
                  ListTile(
                    leading: const Icon(Icons.login, color: AppColors.primary),
                    title: Text('تسجيل الدخول بجوجل', style: AppTextStyles.bodyLarge),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: settingsState.isLoading ? null : () => ref.read(settingsProvider.notifier).signInWithGoogle(),
                  ),
                ] else ...[
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.primary,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    title: Text(settingsState.googleAccountEmail ?? '', style: AppTextStyles.bodyLarge),
                    subtitle: Text('مسجل الدخول', style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.swap_horiz, color: AppColors.primary),
                    title: Text('تغيير الحساب', style: AppTextStyles.bodyLarge),
                    onTap: settingsState.isLoading ? null : () => ref.read(settingsProvider.notifier).switchAccount(),
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout, color: AppColors.red),
                    title: Text('تسجيل الخروج', style: AppTextStyles.bodyLarge.copyWith(color: AppColors.red)),
                    onTap: settingsState.isLoading ? null : () => ref.read(settingsProvider.notifier).signOut(),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Backup Section
          Text('النسخ الاحتياطي', style: AppTextStyles.titleMedium),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    settingsState.isGoogleSignedIn ? Icons.cloud_done : Icons.cloud_off,
                    color: settingsState.isGoogleSignedIn ? AppColors.green : AppColors.gray,
                  ),
                  title: Text('Google Drive', style: AppTextStyles.bodyLarge),
                  subtitle: Text(
                    settingsState.isGoogleSignedIn
                        ? 'متصل: ${settingsState.googleAccountEmail}'
                        : 'غير متصل - سجل الدخول لتمكين النسخ الاحتياطي',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray),
                  ),
                ),
                const Divider(height: 1),
                if (settingsState.isGoogleSignedIn) ...[
                  ListTile(
                    leading: const Icon(Icons.access_time, color: AppColors.primary),
                    title: Text('آخر نسخة احتياطية', style: AppTextStyles.bodyLarge),
                    trailing: Text(
                      settingsState.lastBackupAt != null
                          ? DateFormatter.formatDisplayDateTime(settingsState.lastBackupAt!)
                          : 'لم يتم النسخ بعد',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray),
                    ),
                  ),
                  const Divider(height: 1),
                  // Backup Mode Selector
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('وضع النسخ الاحتياطي', style: AppTextStyles.bodyLarge),
                        const SizedBox(height: 8),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment<int>(
                              value: 0,
                              label: Text('إيقاف'),
                              icon: Icon(Icons.backup_outlined),
                            ),
                            ButtonSegment<int>(
                              value: 1,
                              label: Text('بعد كل تغيير'),
                              icon: Icon(Icons.sync),
                            ),
                            ButtonSegment<int>(
                              value: 2,
                              label: Text('يومي'),
                              icon: Icon(Icons.calendar_today),
                            ),
                          ],
                          selected: {settingsState.backupMode},
                          onSelectionChanged: settingsState.isLoading
                              ? null
                              : (newSelection) {
                                  ref.read(settingsProvider.notifier).setBackupMode(newSelection.first);
                                },
                        ),
                        if (settingsState.backupMode == 2) ...[
                          const SizedBox(height: 16),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.access_time, color: AppColors.primary),
                            title: Text('وقت النسخ اليومي', style: AppTextStyles.bodyLarge),
                            trailing: Text(
                              settingsState.backupDailyTime ?? '03:00',
                              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary),
                            ),
                            onTap: settingsState.isLoading
                                ? null
                                : () async {
                                    final TimeOfDay? picked = await showTimePicker(
                                      context: context,
                                      initialTime: TimeOfDay.fromDateTime(
                                        DateTime.parse('2000-01-01 ${settingsState.backupDailyTime ?? '03:00'}'),
                                      ),
                                    );
                                    if (picked != null && mounted) {
                                      final timeStr = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                      ref.read(settingsProvider.notifier).setBackupDailyTime(timeStr);
                                    }
                                  },
                          ),
                        ],
                ]),
                    ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cloud_upload, color: AppColors.primary),
                    title: Text('نسخ احتياطي الآن', style: AppTextStyles.bodyLarge),
                    onTap: settingsState.isLoading ? null : () => ref.read(settingsProvider.notifier).backupNow(),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.cloud_download, color: AppColors.primary),
                    title: Text('استرجاع من Google Drive', style: AppTextStyles.bodyLarge),
                    onTap: settingsState.isLoading ? null : () => ref.read(settingsProvider.notifier).restoreFromBackup(),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'ملاحظة: قد يتأخر Android في تنفيذ المهام المجدولة ببضع دقائق.',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Local Import/Export
          Text('النسخ المحلي (Import/Export)', style: AppTextStyles.titleMedium),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.file_download, color: AppColors.primary),
                  title: Text('تصدير كل البيانات', style: AppTextStyles.bodyLarge),
                  subtitle: Text('حفظ ملف JSON بكل البيانات في مجلد Downloads', style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray)),
                  onTap: _exportAllData,
                  trailing: IconButton(
                    icon: const Icon(Icons.share, color: AppColors.primary),
                    tooltip: 'مشاركة',
                    onPressed: _shareAllData,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.file_upload, color: AppColors.primary),
                  title: Text('استيراد من ملف', style: AppTextStyles.bodyLarge),
                  subtitle: Text('استيراد بيانات من ملف JSON محفوظ', style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray)),
                  onTap: _importFromFile,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // App Info
          Text('معلومات التطبيق', style: AppTextStyles.titleMedium),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline, color: AppColors.gray),
                  title: Text('دفتر المعاملات', style: AppTextStyles.bodyLarge),
                  subtitle: Text('الإصدار 1.0.0', style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray)),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppColors.red),
                  title: Text('مسح جميع البيانات', style: AppTextStyles.bodyLarge.copyWith(color: AppColors.red)),
                  onTap: _showClearAllDataDialog,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportAllData() async {
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
      final exportData = await ref.read(exportServiceProvider).buildFullExportData();
      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      final saved = await ref.read(exportServiceProvider).saveExportToDevice(jsonString);

      if (mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
        if (saved) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('تم حفظ الملف في مجلد Downloads')),
          );
        } else {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('تم الإلغاء')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('فشل الحفظ: $e')),
        );
      }
    }
  }

  Future<void> _shareAllData() async {
    final exportData = await ref.read(exportServiceProvider).buildFullExportData();
    await ref.read(exportServiceProvider).shareExportFile(context, 'debt-tracker', exportData);
  }

  Future<void> _importFromFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.isNotEmpty) {
        final file = File(result.single.path!);
        await ref.read(importServiceProvider).importFromFile(file);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم استيراد البيانات بنجاح')),
          );
          // Bump the version so *every* derived provider (balances, totals,
          // budget) recomputes - invalidate(personsProvider) alone only
          // refreshed the person list.
          ref.read(dataVersionProvider.notifier).state++;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ في الاستيراد: '
              '${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}',
            ),
          ),
        );
      }
    }
  }

  void _showClearAllDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('مسح جميع البيانات؟', style: AppTextStyles.titleMedium.copyWith(color: AppColors.red)),
        content: const Text('تحذير: سيؤدي هذا إلى مسح جميع الأشخاص والمشاريع والمعاملات والصور نهائياً. لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              // Clear database
              await ref.read(databaseHelperProvider).deleteDatabaseFile();
              // Clear attachments folder
              await ref.read(imageStorageProvider).clearAllAttachments();
              // Clear settings (shared_preferences)
              await ref.read(settingsServiceProvider).clearAll();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم مسح جميع البيانات')),
                );
                ref.read(dataVersionProvider.notifier).state++;
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('مسح الكل'),
          ),
        ],
      ),
    );
  }
}
