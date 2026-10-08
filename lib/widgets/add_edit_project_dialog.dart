import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../models/project.dart';
import '../../providers/person_detail_provider.dart';

class AddEditProjectDialog extends ConsumerStatefulWidget {
  final int personId;
  final Project? project;

  const AddEditProjectDialog({
    super.key,
    required this.personId,
    this.project,
  });

  @override
  ConsumerState<AddEditProjectDialog> createState() => _AddEditProjectDialogState();
}

class _AddEditProjectDialogState extends ConsumerState<AddEditProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _budgetController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.project != null) {
      _nameController.text = widget.project!.name;
      if (widget.project!.budget != null) {
        _budgetController.text = widget.project!.budget.toString();
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.project != null;

    return AlertDialog(
      title: Text(isEditing ? 'تعديل المشروع' : 'مشروع جديد'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'اسم المشروع *',
                hintText: 'مثال: شغل شهر 9',
                prefixIcon: const Icon(Icons.folder),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'اسم المشروع مطلوب';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _budgetController,
              decoration: InputDecoration(
                labelText: 'البادجت (اختياري)',
                hintText: '1000 أو -500',
                prefixIcon: const Icon(Icons.account_balance_wallet),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              validator: (value) {
                if (value != null && value.trim().isNotEmpty) {
                  final parsed = double.tryParse(value.trim());
                  if (parsed == null) {
                    return 'أدخل رقم صحيح';
                  }
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _saveProject,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(isEditing ? 'حفظ التعديلات' : 'إضافة'),
        ),
      ],
    );
  }

  Future<void> _saveProject() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final project = Project(
        personId: widget.personId,
        name: _nameController.text.trim(),
        budget: _budgetController.text.trim().isEmpty
            ? null
            : double.parse(_budgetController.text.trim()),
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      );

      if (widget.project != null) {
        final updatedProject = project.copyWith(
          id: widget.project!.id,
          createdAt: widget.project!.createdAt,
        );
        await ref.read(personDetailProvider(widget.personId).notifier).updateProject(updatedProject);
      } else {
        await ref.read(personDetailProvider(widget.personId).notifier).addProject(project);
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}