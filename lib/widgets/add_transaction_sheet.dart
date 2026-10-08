import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../models/transaction.dart';
import '../../models/project.dart';
import '../../models/transaction_attachment.dart';
import '../../providers/person_detail_provider.dart';
import '../../widgets/segmented_toggle.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/date_formatter.dart';
import '../../services/image_storage_service.dart';
import '../../db/attachment_dao.dart';
import '../../db/payment_dao.dart';
import '../../models/transaction_payment.dart';

class AddTransactionSheet extends ConsumerStatefulWidget {
  final int personId;
  final int? initialProjectId;
  final List<Project> projects;
  final Transaction? transaction;

  const AddTransactionSheet({
    super.key,
    required this.personId,
    required this.initialProjectId,
    required this.projects,
    this.transaction,
  });

  @override
  ConsumerState<AddTransactionSheet> createState() =>
      _AddTransactionSheetState();
}

class _AddTransactionSheetState extends ConsumerState<AddTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  TransactionType _selectedType = TransactionType.theyOweMe;
  int? _selectedProjectId;
  DateTime _selectedDate = DateTime.now();
  // Rule 1: the 4th state, selectable at creation time.
  bool _settled = false;
  DateTime _settledAt = DateTime.now();

  bool _isLoading = false;
  bool _saved = false;

  // Images already stored in DB (edit mode only).
  List<TransactionAttachment> _existingAttachments = [];
  // Existing attachments the user removed; deleted only when saving.
  final List<TransactionAttachment> _removedExisting = [];
  // Newly picked images (already copied to permanent storage, not yet in DB).
  final List<String> _newImagePaths = [];

  late final ImageStorageService _imageStorage;
  late final AttachmentDao _attachmentDao;
  late final PaymentDao _paymentDao;

  @override
  void initState() {
    super.initState();
    _imageStorage = ref.read(imageStorageProvider);
    _attachmentDao = ref.read(attachmentDaoProvider);
    _paymentDao = ref.read(paymentDaoProvider);
    _selectedProjectId = widget.initialProjectId;

    final txn = widget.transaction;
    if (txn != null) {
      _amountController.text = txn.amount.toString();
      _selectedType = txn.type;
      _noteController.text = txn.note ?? '';
      _selectedProjectId = txn.projectId;
      _selectedDate = DateFormatter.parseDateTime(txn.date);
      _settled = txn.isSettled;
      _settledAt = txn.settledAt ?? DateTime.now();
      _loadExistingImages(txn.id!);
      _loadPayments(txn.id!);
    }
  }

  @override
  void dispose() {
    // If the sheet is closed without saving, remove files picked in this session.
    if (!_saved) {
      for (final path in _newImagePaths) {
        _imageStorage.deleteFile(path);
      }
    }
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingImages(int transactionId) async {
    final list = await _attachmentDao.getAttachmentsForTransaction(
      transactionId,
    );
    if (!mounted) return;
    setState(() => _existingAttachments = list);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.transaction != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isEditing ? 'تعديل المعاملة' : 'معاملة جديدة',
                        style: AppTextStyles.headlineSmall,
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Amount
                  TextFormField(
                    controller: _amountController,
                    decoration: InputDecoration(
                      labelText: 'المبلغ *',
                      hintText: '500',
                      prefixIcon: const Icon(Icons.attach_money),
                      helperText: _paidSoFar > 0
                          ? 'مدفوع حتى الآن: ${CurrencyFormatter.format(_paidSoFar)}'
                          : null,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'المبلغ مطلوب';
                      }
                      final parsed = double.tryParse(value.trim());
                      if (parsed == null || parsed <= 0) {
                        return 'أدخل مبلغ أكبر من صفر';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Type
                  Text('النوع', style: AppTextStyles.labelLarge),
                  const SizedBox(height: 8),
                  SegmentedToggle<TransactionType>(
                    selectedValue: _selectedType,
                    options: [
                      SegmentedToggleOption(
                        value: TransactionType.theyOweMe,
                        label: 'ليا عنده',
                        icon: Icons.arrow_downward,
                      ),
                      SegmentedToggleOption(
                        value: TransactionType.iOweThem,
                        label: 'عليّا',
                        icon: Icons.arrow_upward,
                      ),
                    ],
                    onChanged: (value) => setState(() => _selectedType = value),
                    selectedColor: AppColors.primary,
                  ),
                  const SizedBox(height: 16),

                  // Project dropdown
                  Text('المشروع', style: AppTextStyles.labelLarge),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppColors.lightGrayBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: _selectedProjectId,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('بدون مشروع'),
                          ),
                          ...widget.projects.map(
                            (p) => DropdownMenuItem<int?>(
                              value: p.id,
                              child: Text(p.name),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedProjectId = value;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Note
                  TextFormField(
                    controller: _noteController,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظة',
                      hintText: 'دفعة أولى',
                      prefixIcon: Icon(Icons.note),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Date
                  _DateField(
                    label: 'التاريخ',
                    value: DateFormatter.formatDisplayDate(_selectedDate),
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 16),

                  // Status (rule 1: the 4th state). Once the row has a payment
                  // history the flag is derived, so the form only reports it.
                  if (_hasPaymentHistory) ...[
                    Text('الحالة', style: AppTextStyles.labelLarge),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _settled ? AppColors.green : AppColors.border,
                        ),
                        color: _settled
                            ? AppColors.green.withValues(alpha: 0.08)
                            : Colors.transparent,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _settled
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 22,
                            color: _settled ? AppColors.green : AppColors.gray,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _settled
                                  ? '${_selectedType == TransactionType.theyOweMe ? 'مستلمة' : 'مدفوعة'} في ${DateFormatter.formatDisplayDate(_settledAt)}'
                                  : 'غير مسدَّدة',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: _settled
                                    ? AppColors.green
                                    : AppColors.gray,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'الحالة محسوبة من سجل الدفعات، فغيّرها من تفاصيل المعاملة.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.gray,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    Text('الحالة', style: AppTextStyles.labelLarge),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => setState(() => _settled = !_settled),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _settled
                                ? AppColors.green
                                : AppColors.border,
                          ),
                          color: _settled
                              ? AppColors.green.withValues(alpha: 0.08)
                              : Colors.transparent,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _settled
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 22,
                              color: _settled
                                  ? AppColors.green
                                  : AppColors.gray,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _settled
                                    ? '${_selectedType == TransactionType.theyOweMe ? 'مستلمة' : 'مدفوعة'} في ${DateFormatter.formatDisplayDate(_settledAt)}'
                                    : 'غير مسدَّدة',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: _settled
                                      ? AppColors.green
                                      : AppColors.gray,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_settled) ...[
                      const SizedBox(height: 8),
                      _DateField(
                        label: 'تاريخ التسديد',
                        value: DateFormatter.formatDisplayDate(_settledAt),
                        onTap: _pickSettledDate,
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],

                  // Attachments
                  _AttachmentPickerRow(
                    existingPaths: _existingAttachments
                        .map((a) => a.filePath)
                        .toList(),
                    newPaths: _newImagePaths,
                    onPickCamera: () => _addImage(fromCamera: true),
                    onPickGallery: () => _addImage(fromCamera: false),
                    onRemoveExisting: _removeExisting,
                    onRemoveNew: _removeNew,
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _saveTransaction,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(isEditing ? 'حفظ التعديلات' : 'إضافة'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    ),);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar'),
      builder: (context, child) => Theme(
        data: Theme.of(
          context,
        ).copyWith(colorScheme: ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null) {
      // Keep the original time-of-day (date picker only returns the date).
      setState(() {
        _selectedDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _selectedDate.hour,
          _selectedDate.minute,
          _selectedDate.second,
        );
      });
    }
  }

  Future<void> _pickSettledDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _settledAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar'),
      builder: (context, child) => Theme(
        data: Theme.of(
          context,
        ).copyWith(colorScheme: ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _settledAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _settledAt.hour,
          _settledAt.minute,
          _settledAt.second,
        );
      });
    }
  }

  Future<void> _addImage({required bool fromCamera}) async {
    final File? file = fromCamera
        ? await _imageStorage.pickImageFromCamera()
        : await _imageStorage.pickImageFromGallery();
    if (file != null && mounted) {
      setState(() => _newImagePaths.add(file.path));
    }
  }

  Future<void> _removeExisting(int index) async {
    final ok = await _confirmDelete();
    if (ok != true) return;
    setState(() {
      // Deferred: DB row + file are deleted only when the user taps save.
      _removedExisting.add(_existingAttachments.removeAt(index));
    });
  }

  Future<void> _removeNew(int index) async {
    final ok = await _confirmDelete();
    if (ok != true) return;
    final path = _newImagePaths[index];
    setState(() => _newImagePaths.removeAt(index));
    await _imageStorage.deleteFile(
      path,
    ); // never saved to DB, safe to delete now
  }

  Future<bool?> _confirmDelete() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الصورة؟'),
        content: const Text('سيتم حذف الصورة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  /// What has already been paid on the transaction being edited.
  double get _paidSoFar => totalPaid(_payments);

  /// Once money has moved the status belongs to the payment book, and the
  /// form only reports it.
  bool get _hasPaymentHistory => (_payments ?? const []).isNotEmpty;

  /// What the form is about to persist. With a history the stored values are
  /// echoed back untouched; otherwise the toggle still decides.
  bool get _savedSettled =>
      _hasPaymentHistory ? widget.transaction!.isSettled : _settled;

  DateTime get _savedSettledAt => _hasPaymentHistory
      ? (widget.transaction!.settledAt ?? _settledAt)
      : _settledAt;

  List<TransactionPayment>? _payments;

  Future<void> _loadPayments(int transactionId) async {
    final list = await _paymentDao.getPaymentsForTransaction(transactionId);
    if (!mounted) return;
    setState(() => _payments = list);
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final amount = double.parse(_amountController.text.trim());

      var transaction = Transaction(
        personId: widget.personId,
        projectId: _selectedProjectId,
        amount: amount,
        type: _selectedType,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        date: _selectedDate.toIso8601String(),
        createdAt:
            widget.transaction?.createdAt ?? DateTime.now().toIso8601String(),
        // Rule 2: settled_at only exists while is_settled = 1. With a payment
        // history the flag is derived, so the stored values are echoed back
        // and the DAO re-derives them from the payments.
        isSettled: _savedSettled,
        settledAt: _savedSettled ? _savedSettledAt : null,
      );

      final notifier = ref.read(personDetailProvider(widget.personId).notifier);

      final int transactionId;
      if (widget.transaction != null) {
        transactionId = widget.transaction!.id!;

        await notifier.updateTransaction(widget.transaction!, transaction);
      } else {
        // The creator writes the row and, when it is born settled, the one
        // payment that makes it so — in the same database transaction, so a
        // bare flag the payment book would then disagree with cannot exist.
        transactionId = await notifier.addTransaction(transaction);
      }

      // Delete attachments the user removed (DB row + real file).
      for (final a in _removedExisting) {
        if (a.id != null) await _attachmentDao.deleteAttachment(a.id!);
      }

      // Insert ONLY the newly picked images (existing ones are already in DB).
      for (final path in _newImagePaths) {
        await _attachmentDao.insertAttachment(
          TransactionAttachment(
            transactionId: transactionId,
            filePath: path,
            createdAt: DateTime.now().toIso8601String(),
          ),
        );
      }

      _saved = true;
      if (mounted) Navigator.pop(context);
    } on PaymentValidationException catch (e) {
      // Validation text is already Arabic and user-facing.
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(value, style: AppTextStyles.bodyMedium),
      ),
    );
  }
}

class _AttachmentPickerRow extends StatelessWidget {
  final List<String> existingPaths;
  final List<String> newPaths;
  final VoidCallback onPickCamera;
  final VoidCallback onPickGallery;
  final void Function(int) onRemoveExisting;
  final void Function(int) onRemoveNew;

  const _AttachmentPickerRow({
    required this.existingPaths,
    required this.newPaths,
    required this.onPickCamera,
    required this.onPickGallery,
    required this.onRemoveExisting,
    required this.onRemoveNew,
  });

  @override
  Widget build(BuildContext context) {
    final total = existingPaths.length + newPaths.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPickGallery,
                icon: const Icon(Icons.photo_library),
                label: const Text('🖼️ من الصور'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPickCamera,
                icon: const Icon(Icons.camera_alt),
                label: const Text('📷 الكاميرا'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        if (total > 0) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: total,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final isExisting = index < existingPaths.length;
                final path = isExisting
                    ? existingPaths[index]
                    : newPaths[index - existingPaths.length];
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(path),
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 80,
                          height: 80,
                          color: AppColors.lightGrayBg,
                          child: const Icon(Icons.broken_image),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => isExisting
                            ? onRemoveExisting(index)
                            : onRemoveNew(index - existingPaths.length),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
