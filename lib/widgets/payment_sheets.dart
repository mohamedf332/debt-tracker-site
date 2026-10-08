import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/payment_dao.dart';
import '../models/transaction.dart';
import '../models/transaction_payment.dart';
import '../providers/persons_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/currency_formatter.dart';
import '../utils/date_formatter.dart';

/// The verb the settlement sheet uses, chosen by direction.
///
/// "owed to me" is money landing in my hand, "I owe" is money leaving it —
/// the same three shortcuts read wrong if they all say "سدّد".
String _settleVerb(Transaction txn) =>
    txn.type == TransactionType.theyOweMe ? 'استلمت' : 'دفعت';

/// The settle action on a transaction: three shortcuts into the payment book.
///
/// Option 1 ("the whole amount") only exists while nothing has been paid and
/// option 3 ("the rest") only exists once something has — so the sheet never
/// shows two ways of doing the same thing. Fixed-amount options save directly;
/// the partial-payment option opens [showPaymentDialog] for an entered amount.
Future<void> showSettlementSheet({
  required BuildContext context,
  required Transaction txn,
  required double paid,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: _SettlementSheet(txn: txn, paid: paid),
      ),
    ),
  );
}

/// One payment: amount, date, optional note, plus delete when editing.
///
/// [amountEditable] is false for the two shortcuts, where the amount is the
/// whole point of the button that opened this — only the date and note are
/// the user's to change.
Future<void> showPaymentDialog({
  required BuildContext context,
  required Transaction txn,
  required double paidTotal,
  required double initialAmount,
  required String title,
  bool amountEditable = true,
  TransactionPayment? payment,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: PaymentDialog(
          txn: txn,
          payment: payment,
          paidTotal: paidTotal,
          initialAmount: initialAmount,
          title: title,
          amountEditable: amountEditable,
        ),
      ),
    ),
  );
}

class _SettlementSheet extends ConsumerWidget {
  const _SettlementSheet({required this.txn, required this.paid});

  final Transaction txn;
  final double paid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verb = _settleVerb(txn);
    final remaining = outstandingOf(txn, paid);
    final nothingPaid = paid <= 0;
    final stillOwed = remaining > 0;

    final options = <_SettleOption>[
      if (nothingPaid)
        _SettleOption(
          icon: txn.type == TransactionType.theyOweMe
              ? Icons.download_done
              : Icons.paid_outlined,
          label: '$verb المبلغ كله',
          subtitle: CurrencyFormatter.format(txn.amount),
          amount: txn.amount,
          amountEditable: false,
        ),
      _SettleOption(
        icon: Icons.add_card_outlined,
        label: '$verb دفعة',
        subtitle: 'أي مبلغ حتى ${CurrencyFormatter.format(remaining)}',
        amount: 0,
        amountEditable: true,
      ),
      if (!nothingPaid && stillOwed)
        _SettleOption(
          icon: Icons.done_all_outlined,
          label: '$verb المتبقي',
          subtitle: CurrencyFormatter.format(remaining),
          amount: remaining,
          amountEditable: false,
        ),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('تسوية المبلغ', style: AppTextStyles.headlineSmall),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'الإجمالي ${CurrencyFormatter.format(txn.amount)} — '
                    'المدفوع ${CurrencyFormatter.format(paid)} — '
                    'المتبقي ${CurrencyFormatter.format(remaining)}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.gray,
                    ),
                  ),
                ),
                for (var i = 0; i < options.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(options[i].icon, color: AppColors.primary),
                    title: Text(
                      options[i].label,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      options[i].subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.gray,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_left,
                      color: AppColors.gray,
                    ),
                    onTap: () => _open(context, ref, options[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    _SettleOption option,
  ) async {
    if (!option.amountEditable) {
      try {
        await ref
            .read(transactionActionsProvider)
            .addPayment(
              transactionId: txn.id!,
              amount: option.amount,
              date: DateTime.now().toIso8601String(),
            );
        if (context.mounted) Navigator.pop(context);
      } on PaymentValidationException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('تعذّر حفظ الدفعة')));
        }
      }
      return;
    }
    Navigator.pop(context);
    showPaymentDialog(
      context: context,
      txn: txn,
      paidTotal: paid,
      initialAmount: option.amount,
      amountEditable: option.amountEditable,
      title: option.label,
    );
  }
}

class _SettleOption {
  const _SettleOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.amount,
    required this.amountEditable,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final double amount;
  final bool amountEditable;
}

/// Add / edit dialog for one payment.
class PaymentDialog extends ConsumerStatefulWidget {
  const PaymentDialog({
    super.key,
    required this.txn,
    required this.payment,
    required this.paidTotal,
    required this.initialAmount,
    required this.title,
    required this.amountEditable,
  });

  final Transaction txn;
  final TransactionPayment? payment;

  /// Everything already recorded on the transaction, used to cap the field.
  final double paidTotal;
  final double initialAmount;
  final String title;
  final bool amountEditable;

  @override
  ConsumerState<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<PaymentDialog> {
  late final TextEditingController _amountController;
  final TextEditingController _noteController = TextEditingController();
  late DateTime _date;
  String? _error;

  bool get _isEditing => widget.payment != null;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.initialAmount <= 0 ? '' : _plainNumber(widget.initialAmount),
    );
    _noteController.text = widget.payment?.note ?? '';
    _date = widget.payment == null
        ? DateTime.now()
        : DateFormatter.parseDateTime(widget.payment!.date);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Ceiling for the field: everything still outstanding, plus this row's own
  /// amount when editing it.
  double get _maxAllowed {
    final own = widget.payment?.amount ?? 0;
    return widget.txn.amount - (widget.paidTotal - own);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: AppTextStyles.headlineSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _amountController,
                  enabled: widget.amountEditable,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'المبلغ *',
                    prefixIcon: const Icon(Icons.attach_money),
                    errorText: _error,
                  ),
                ),
                if (widget.amountEditable && !_isEditing) ...[
                  const SizedBox(height: 6),
                  Text(
                    'المتبقي من إجمالي المبلغ: '
                    '${CurrencyFormatter.format(_maxAllowed)}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.gray,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _DateField(
                  label: 'التاريخ',
                  value: DateFormatter.formatDisplayDate(_date),
                  onTap: _pickDate,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختياري)',
                    prefixIcon: Icon(Icons.note),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (_isEditing)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _confirmDelete,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.red,
                            side: const BorderSide(color: AppColors.red),
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('حذف'),
                        ),
                      ),
                    if (_isEditing) const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _save,
                        child: const Text('حفظ'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
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
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'مبلغ الدفعة يجب أن يكون أكبر من صفر');
      return;
    }
    final maxAllowed = _maxAllowed;
    if (amount > maxAllowed + 1e-9) {
      setState(
        () => _error =
            'المتبقي هو ${CurrencyFormatter.format(maxAllowed < 0 ? 0 : maxAllowed)} فقط',
      );
      return;
    }

    final actions = ref.read(transactionActionsProvider);
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();

    try {
      final payment = widget.payment;
      if (payment == null) {
        await actions.addPayment(
          transactionId: widget.txn.id!,
          amount: amount,
          date: _date.toIso8601String(),
          note: note,
        );
      } else {
        await actions.updatePayment(
          payment,
          amount: amount,
          date: _date.toIso8601String(),
          note: note,
        );
      }
      if (mounted) Navigator.pop(context);
    } on PaymentValidationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تعذّر حفظ الدفعة')));
      }
    }
  }

  Future<void> _confirmDelete() async {
    final payment = widget.payment;
    if (payment?.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الدفعة؟'),
        content: const Text('سيتم حذف هذه الدفعة وإعادة حساب حالة المعاملة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      await ref.read(transactionActionsProvider).deletePayment(payment!.id!);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تعذّر حذف الدفعة')));
      }
    }
  }
}

/// Asks for confirmation, then wipes the payment history.
///
/// Split out because the tile and the details sheet both offer un-settling
/// and must ask exactly the same question.
Future<bool> confirmUnsettle(BuildContext context, Transaction txn) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('إلغاء التسجيل؟'),
      content: Text(
        'سيتم حذف سجل الدفعات (${CurrencyFormatter.format(txn.amount)}) '
        'ويرتعد هذا المبلغ إلى "غير مسدَّد".',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          child: const Text('نعم، حذف السجل'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Plain Western digits with no trailing `.0`, so the field reads as a
/// number the user can retype rather than a float literal.
String _plainNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

/// Buzzes before opening a payment's editor, matching the details sheet.
Future<void> openPaymentEditor(
  BuildContext context, {
  required Transaction txn,
  required double paid,
  required TransactionPayment payment,
}) async {
  await HapticFeedback.vibrate();
  await showPaymentDialog(
    context: context,
    txn: txn,
    paidTotal: paid,
    payment: payment,
    initialAmount: payment.amount,
    amountEditable: true,
    title: 'تعديل الدفعة',
  );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

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
