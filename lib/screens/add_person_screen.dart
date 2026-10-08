import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../models/transaction.dart';
import '../../models/person.dart';
import '../../widgets/segmented_toggle.dart';
import '../../providers/persons_provider.dart';
import '../../db/payment_dao.dart';

class AddPersonScreen extends ConsumerStatefulWidget {
  const AddPersonScreen({super.key});

  @override
  ConsumerState<AddPersonScreen> createState() => _AddPersonScreenState();
}

class _AddPersonScreenState extends ConsumerState<AddPersonScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _initialAmountController = TextEditingController();
  final _initialNoteController = TextEditingController();
  TransactionType _initialType = TransactionType.theyOweMe;

  /// Default OFF: an initial transaction starts unsettled unless the user
  /// says otherwise.
  bool _initialSettled = false;
  bool _isLoading = false;

  /// The switch reads differently per direction: money coming in is
  /// "received", money going out is "paid".
  String get _settledQuestion => _initialType == TransactionType.theyOweMe
      ? 'تم الاستلام؟'
      : 'تم الدفع؟';

  @override
  void dispose() {
    _nameController.dispose();
    _initialAmountController.dispose();
    _initialNoteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة شخص جديد')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('بيانات الشخص', style: AppTextStyles.titleMedium),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'الاسم *',
                  hintText: 'أحمد محمد',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'الاسم مطلوب';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              Text('معاملة أولية (اختياري)', style: AppTextStyles.titleMedium),
              const SizedBox(height: 16),
              TextFormField(
                controller: _initialAmountController,
                decoration: const InputDecoration(
                  labelText: 'المبلغ',
                  hintText: '500',
                  prefixIcon: Icon(Icons.attach_money),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final parsed = double.tryParse(value.trim());
                    if (parsed == null || parsed <= 0) {
                      return 'أدخل مبلغ أكبر من صفر';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              SegmentedToggle<TransactionType>(
                selectedValue: _initialType,
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
                onChanged: (value) => setState(() => _initialType = value),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _initialSettled ? AppColors.green : AppColors.border,
                  ),
                  color: _initialSettled
                      ? AppColors.green.withValues(alpha: 0.08)
                      : Colors.transparent,
                ),
                child: Row(
                  children: [
                    Icon(
                      _initialSettled
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 22,
                      color: _initialSettled ? AppColors.green : AppColors.gray,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _settledQuestion,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: _initialSettled
                              ? AppColors.green
                              : AppColors.gray,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Switch(
                      value: _initialSettled,
                      activeThumbColor: AppColors.white,
                      activeTrackColor: AppColors.green,
                      onChanged: (value) =>
                          setState(() => _initialSettled = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _initialNoteController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة',
                  hintText: 'دفعة أولى',
                  prefixIcon: Icon(Icons.note),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : _savePerson,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('حفظ'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _savePerson() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final person = Person(
        name: _nameController.text.trim(),
        isPinned: 0,
        isArchived: 0,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      );

      // Empty amount: the whole section is skipped, as in the spec.
      final amountText = _initialAmountController.text.trim();
      Transaction Function(int personId)? initial;
      if (amountText.isNotEmpty) {
        final amount = double.tryParse(amountText);
        if (amount == null || amount <= 0) {
          throw PaymentValidationException('أدخل مبلغ أكبر من صفر');
        }
        initial = (personId) => _initialTransaction(personId, amount);
      }

      // Person + first transaction commit together: if the transaction fails
      // the person is rolled back with it, and the error is shown below.
      await ref
          .read(personsProvider.notifier)
          .addPerson(person, initialTransaction: initial);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم إضافة الشخص بنجاح')));
      }
    } on PaymentValidationException catch (e) {
      // Validation text is already Arabic and user-facing.
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذّر حفظ المعاملة، تم التراجع عن الحفظ بالكامل'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// The initial transaction, built once the person's real id is known.
  ///
  /// Same shape as a row from the Add Transaction sheet: no project (so it
  /// lands on the Person Detail "الكل" tab), today's date, and — when the
  /// switch is on — a settled row the payment book will back with a single
  /// full payment dated here.
  Transaction _initialTransaction(int personId, double amount) {
    final now = DateTime.now();
    final note = _initialNoteController.text.trim();
    return Transaction(
      personId: personId,
      projectId: null,
      amount: amount,
      type: _initialType,
      note: note.isEmpty ? null : note,
      date: now.toIso8601String(),
      createdAt: now.toIso8601String(),
      isSettled: _initialSettled,
      settledAt: _initialSettled ? now : null,
    );
  }
}
