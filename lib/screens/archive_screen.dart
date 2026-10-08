import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../models/person.dart';
import '../../providers/persons_provider.dart';
import '../../providers/person_detail_provider.dart';
import '../../services/image_storage_service.dart' as img_storage;
import '../../db/project_dao.dart';

class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final archivedPersonsAsync = ref.watch(archivedPersonsProvider);
    final archivedProjectsAsync = ref.watch(archivedProjectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الأرشيف'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.gray,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'أشخاص مؤرشفة'),
            Tab(text: 'مشاريع مؤرشفة'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Archived Persons
          archivedPersonsAsync.when(
            data: (persons) => _buildArchivedPersonsList(persons),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('خطأ: $e')),
          ),
          // Archived Projects
          archivedProjectsAsync.when(
            data: (projects) => _buildArchivedProjectsList(projects),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('خطأ: $e')),
          ),
        ],
      ),
    );
  }

  Widget _buildArchivedPersonsList(List<Person> persons) {
    if (persons.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.archive_outlined, size: 80, color: AppColors.gray),
            SizedBox(height: 16),
            Text(
              'لا يوجد أشخاص مؤرشفة',
              style: TextStyle(fontSize: 18, color: AppColors.gray),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        80 + MediaQuery.of(context).padding.bottom,
      ),
      itemCount: persons.length,
      itemBuilder: (context, index) {
        final person = persons[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.lightCyan,
              child: Text(
                person.name.isNotEmpty ? person.name[0] : '?',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(person.name, style: AppTextStyles.bodyLarge),
            subtitle: Text(
              'مؤرشف',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.orange),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.restore, color: AppColors.green),
                  tooltip: 'استرجاع',
                  onPressed: () => _restorePerson(person),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_forever, color: AppColors.red),
                  tooltip: 'حذف نهائي',
                  onPressed: () => _permanentlyDeletePerson(person),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildArchivedProjectsList(List<Map<String, dynamic>> projects) {
    if (projects.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_off, size: 80, color: AppColors.gray),
            SizedBox(height: 16),
            Text(
              'لا يوجد مشاريع مؤرشفة',
              style: TextStyle(fontSize: 18, color: AppColors.gray),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        80 + MediaQuery.of(context).padding.bottom,
      ),
      itemCount: projects.length,
      itemBuilder: (context, index) {
        final project = projects[index];
        final projectName = project['name'] as String;
        final personName = project['person_name'] as String;
        final projectId = project['id'] as int;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.lightCyan,
              child: const Icon(Icons.folder, color: AppColors.primary),
            ),
            title: Text(projectName, style: AppTextStyles.bodyLarge),
            subtitle: Text(
              'شخص: $personName',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.restore, color: AppColors.green),
                  tooltip: 'استرجاع',
                  onPressed: () => _restoreProject(projectId),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_forever, color: AppColors.red),
                  tooltip: 'حذف نهائي',
                  onPressed: () => _permanentlyDeleteProject(projectId),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _restorePerson(Person person) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('استرجاع ${person.name}؟'),
        content: const Text(
          'سيتم استرجاع الشخص وجميع مشاريعه وظهورهم في القائمة الرئيسية مجدداً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('استرجاع'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirm == true) {
      try {
        await ref.read(personsProvider.notifier).unarchivePerson(person.id!);
        // Refresh archived lists and providers
        ref.invalidate(archivedPersonsProvider);
        ref.invalidate(archivedProjectsProvider);
        ref.read(personsProvider.notifier).loadPersons();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم استرجاع الشخص وجميع مشاريعه')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
        }
      }
    }
  }

  Future<void> _permanentlyDeletePerson(Person person) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'حذف ${person.name} نهائياً؟',
          style: AppTextStyles.titleMedium.copyWith(color: AppColors.red),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'تحذير: الحذف النهائي لا يمكن التراجع عنه، وسيمسح كل البيانات المرتبطة:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('• الشخص نفسه'),
            const Text('• جميع مشاريعه'),
            const Text('• جميع معاملاته'),
            const Text('• جميع الصور المرفقة'),
            const SizedBox(height: 12),
            Text(
              'متأكد من حذف ${person.name} نهائياً؟',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirm == true) {
      try {
        await ref
            .read(personsProvider.notifier)
            .permanentlyDeletePerson(
              person.id!,
              (path) =>
                  ref.read(img_storage.imageStorageProvider).deleteFile(path),
            );
        // Refresh archived lists and providers
        ref.invalidate(archivedPersonsProvider);
        ref.invalidate(archivedProjectsProvider);
        ref.read(personsProvider.notifier).loadPersons();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('تم حذف الشخص نهائياً')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
        }
      }
    }
  }

  Future<void> _restoreProject(int projectId) async {
    final isPersonArchived = await ProjectDao().isPersonArchived(projectId);
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استرجاع المشروع؟'),
        content: const Text(
          'سيتم استرجاع المشروع وظهوره في تابات الشخص مجدداً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('استرجاع'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirm == true) {
      try {
        final changed = await ProjectDao().unarchiveProject(projectId);
        if (!mounted) return;
        if (changed == 0) throw StateError('لم يتم العثور على المشروع');
        ref.read(personsProvider.notifier).refreshData();
        // Refresh archived lists and providers
        ref.invalidate(archivedPersonsProvider);
        ref.invalidate(archivedProjectsProvider);
        ref.read(personsProvider.notifier).loadPersons();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isPersonArchived
                    ? 'الشخص مؤرشف، استرجع الشخص الأول عشان يظهر'
                    : 'تم استرجاع المشروع',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
        }
      }
    }
  }

  Future<void> _permanentlyDeleteProject(int projectId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'حذف المشروع نهائياً؟',
          style: TextStyle(color: AppColors.red),
        ),
        content: const Text(
          'تحذير: هيتمسح المشروع وكل معاملاته وصورها نهائيًا ومينفعش التراجع. متأكد؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirm == true) {
      try {
        await ProjectDao().permanentlyDeleteProject(
          projectId,
          (path) => ref.read(img_storage.imageStorageProvider).deleteFile(path),
        );
        // Refresh archived lists and providers
        ref.invalidate(archivedPersonsProvider);
        ref.invalidate(archivedProjectsProvider);
        ref.read(personsProvider.notifier).refreshData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حذف المشروع وجميع معاملاته وصوره نهائياً'),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
        }
      }
    }
  }
}
