import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transaction.dart';
import '../models/transaction_attachment.dart';
import '../models/transaction_payment.dart';
import '../providers/person_detail_provider.dart';
import '../providers/persons_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/currency_formatter.dart';
import '../utils/date_formatter.dart';
import 'image_full_screen_viewer.dart';
import 'payment_sheets.dart';

/// Full-screen-height bottom sheet with everything known about one
/// transaction: the facts, the attachments and — when the row is on
/// installments — its payment history with add / edit / delete.
///
/// Everything reads from [personDetailProvider], so a payment written from
/// inside the sheet bumps `dataVersionProvider`, reloads that state and the
/// sheet repaints with the new totals, status, budget and tile.
class TransactionDetailsSheet extends ConsumerStatefulWidget {
  const TransactionDetailsSheet({
    super.key,
    required this.personId,
    required this.transaction,
    required this.attachments,
    this.projectName,
  });

  final int personId;

  /// Last known snapshot; refreshed from the provider while it is open.
  final Transaction transaction;
  final List<TransactionAttachment> attachments;
  final String? projectName;

  @override
  ConsumerState<TransactionDetailsSheet> createState() =>
      _TransactionDetailsSheetState();
}

class _TransactionDetailsSheetState
    extends ConsumerState<TransactionDetailsSheet> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(personDetailProvider(widget.personId));
    final fresh = state.transactions
        .where((txn) => txn.id == widget.transaction.id)
        .firstOrNull;
    final txn = fresh ?? widget.transaction;
    final attachments = state.attachmentsMap[txn.id] ?? widget.attachments;
    final payments = state.paymentsMap[txn.id] ?? const <TransactionPayment>[];
    final paid = totalPaid(payments);
    final remaining = outstandingOf(txn, paid);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                title: 'تفاصيل المعاملة',
                onClose: () => Navigator.pop(context),
              ),
              const SizedBox(height: 8),
              _Facts(
                txn: txn,
                projectName: widget.projectName,
                attachments: attachments,
                paid: paid,
              ),
              const SizedBox(height: 16),
              _SettleAction(txn: txn, paid: paid),
              const SizedBox(height: 16),
              _PaymentHistory(
                txn: txn,
                payments: payments,
                paid: paid,
                remaining: remaining,
              ),
            ],
          ),
        ),
      ),
    ),);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: AppTextStyles.headlineSmall),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

/// Amount, direction, status, project, note, date and attachment thumbnails.
class _Facts extends StatelessWidget {
  const _Facts({
    required this.txn,
    required this.projectName,
    required this.attachments,
    required this.paid,
  });

  final Transaction txn;
  final String? projectName;
  final List<TransactionAttachment> attachments;
  final double paid;

  @override
  Widget build(BuildContext context) {
    final isTheyOweMe = txn.type == TransactionType.theyOweMe;
    final baseColor = isTheyOweMe ? AppColors.green : AppColors.red;
    final statusLabel = txn.isSettled
        ? (isTheyOweMe ? 'مستلمة' : 'مدفوعة')
        : (isPartlyPaid(txn.amount, paid)
              ? partialStatusLabel(txn.amount, paid)
              : 'غير مسدَّدة');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              txn.formattedAmountWithSign,
              style: AppTextStyles.headlineMedium.copyWith(
                color: baseColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: baseColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${txn.type.arabicLabel} • $statusLabel',
                style: AppTextStyles.bodySmall.copyWith(
                  color: baseColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _FactRow(label: 'التاريخ', value: txn.formattedDateTime),
        if (projectName != null && projectName!.isNotEmpty)
          _FactRow(label: 'المشروع', value: projectName!),
        if (txn.note != null && txn.note!.isNotEmpty)
          _FactRow(label: 'ملاحظة', value: txn.note!),
        if (attachments.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: attachments.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => _openViewer(context, index),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(attachments[index].filePath),
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 72,
                      height: 72,
                      color: AppColors.lightGrayBg,
                      child: const Icon(Icons.broken_image, color: AppColors.gray),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _openViewer(BuildContext context, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageFullScreenViewer(
          attachments: attachments,
          initialIndex: index,
        ),
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.gray),
            ),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Installment history, newest first, with the running total underneath and
/// the "add payment" entry point.
class _PaymentHistory extends ConsumerWidget {
  const _PaymentHistory({
    required this.txn,
    required this.payments,
    required this.paid,
    required this.remaining,
  });

  final Transaction txn;
  final List<TransactionPayment> payments;
  final double paid;
  final double remaining;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTheyOweMe = txn.type == TransactionType.theyOweMe;
    final accent = isTheyOweMe ? AppColors.green : AppColors.red;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('سجل الدفعات', style: AppTextStyles.labelLarge),
            Text(
              '${payments.length} دفعة',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (payments.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.lightGrayBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'لا توجد دفعات بعد',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.gray),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < payments.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 12, endIndent: 12),
                  _PaymentRow(
                    payment: payments[i],
                    accent: accent,
                    onTap: () => openPaymentEditor(
                      context,
                      txn: txn,
                      paid: paid,
                      payment: payments[i],
                    ),
                    onLongPress: () => openPaymentEditor(
                      context,
                      txn: txn,
                      paid: paid,
                      payment: payments[i],
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 10),
        _TotalRow(
          label: 'إجمالي المدفوع',
          value: CurrencyFormatter.format(paid),
          color: accent,
        ),
        _TotalRow(
          label: 'المتبقي',
          value: CurrencyFormatter.format(remaining),
          color: remaining > 0 ? AppColors.red : AppColors.green,
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () =>
                showSettlementSheet(context: context, txn: txn, paid: paid),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('إضافة دفعة'),
          ),
        ),
        if (remaining <= 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'تم سداد المبلغ بالكامل',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.green),
            ),
          ),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.payment,
    required this.accent,
    required this.onTap,
    required this.onLongPress,
  });

  final TransactionPayment payment;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 32,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    CurrencyFormatter.format(payment.amount),
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (payment.note != null && payment.note!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      payment.note!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.gray,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Text(
              DateFormatter.formatDisplayDate(
                DateFormatter.parseDateTime(payment.date),
              ),
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_left, size: 20, color: AppColors.gray),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.gray),
          ),
          Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// The settle entry point for one transaction.
///
/// An open row starts the settlement options sheet; a settled one asks first
/// and then wipes the payment history, because status is derived and there is
/// no flag left to flip.
class _SettleAction extends ConsumerWidget {
  const _SettleAction({required this.txn, required this.paid});

  final Transaction txn;
  final double paid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settled = txn.isSettled;
    final isTheyOweMe = txn.type == TransactionType.theyOweMe;
    final remaining = outstandingOf(txn, paid);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: settled ? AppColors.green : AppColors.border),
        color: settled
            ? AppColors.green.withValues(alpha: 0.08)
            : Colors.transparent,
      ),
      child: Row(
        children: [
          Icon(
            settled ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 22,
            color: settled ? AppColors.green : AppColors.gray,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              settled
                  ? '${isTheyOweMe ? 'مستلمة' : 'مدفوعة'} في '
                        '${DateFormatter.formatDisplayDate(txn.settledAt ?? DateFormatter.parseDateTime(txn.date))}'
                  : 'غير مسدَّدة — المتبقي ${CurrencyFormatter.format(remaining)}',
              style: AppTextStyles.bodyMedium.copyWith(
                color: settled ? AppColors.green : AppColors.gray,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _handle(context, ref),
            child: Text(settled ? 'إلغاء التسجيل' : 'تسوية المبلغ'),
          ),
        ],
      ),
    );
  }

  Future<void> _handle(BuildContext context, WidgetRef ref) async {
    if (!txn.isSettled) {
      await showSettlementSheet(context: context, txn: txn, paid: paid);
      return;
    }
    final confirmed = await confirmUnsettle(context, txn);
    if (!confirmed || !context.mounted) return;
    try {
      await ref
          .read(transactionActionsProvider)
          .clearPayments(txn.id!);
      if (context.mounted) Navigator.pop(context);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر تحديث حالة العملية')),
        );
      }
    }
  }
}
