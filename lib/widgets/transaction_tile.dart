import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/date_formatter.dart';
import '../../models/transaction.dart';
import '../../models/transaction_attachment.dart';
import '../../models/transaction_payment.dart';
import '../../providers/persons_provider.dart';
import 'image_full_screen_viewer.dart';
import 'payment_sheets.dart';

/// Rough height of one [TransactionTile] row. Used as the unit for "the list
/// must travel this far before the filter tabs come back" on the person detail
/// screen; an estimate is enough because it only decides how much upward
/// scrolling is needed, never what is drawn.
const double kTransactionRowHeightEstimate = 112;

class TransactionTile extends ConsumerWidget {
  final Transaction transaction;
  final List<TransactionAttachment> attachments;
  final String? projectName;

  /// Installments already collected/paid. Zero for a row with no history.
  final double paidAmount;

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const TransactionTile({
    super.key,
    required this.transaction,
    required this.attachments,
    this.projectName,
    this.paidAmount = 0.0,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTheyOweMe = transaction.type == TransactionType.theyOweMe;
    final settled = transaction.isSettled;
    final baseColor = isTheyOweMe ? AppColors.green : AppColors.red;
    // Rule 4: settled tiles are rendered muted so outstanding rows stand out.
    final amountColor = settled ? baseColor.withValues(alpha: 0.45) : baseColor;
    final typeLabel = transaction.type.arabicLabel;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: AppColors.white,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 40,
                        decoration: BoxDecoration(
                          color: amountColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  transaction.formattedAmountWithSign,
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    color: amountColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: amountColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    typeLabel,
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: amountColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (isPartlyPaid(
                                  transaction.amount,
                                  paidAmount,
                                )) ...[
                                  _StatusChip(
                                    label: partialStatusLabel(
                                      transaction.amount,
                                      paidAmount,
                                    ),
                                    color: baseColor,
                                  ),
                                ] else if (settled) ...[
                                  _StatusChip(
                                    label: isTheyOweMe
                                        ? 'مستلمة ✓'
                                        : 'مدفوعة ✓',
                                    color: AppColors.green,
                                    outlined: true,
                                  ),
                                ],
                              ],
                            ),
                            if (transaction.note != null &&
                                transaction.note!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                transaction.note!,
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.gray,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if (isPartlyPaid(
                              transaction.amount,
                              paidAmount,
                            )) ...[
                              const SizedBox(height: 6),
                              _PartialProgress(
                                amount: transaction.amount,
                                paid: paidAmount,
                                color: baseColor,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 96),
                            child: Text(
                              DateFormatter.formatDisplayDate(
                                DateFormatter.parseDateTime(transaction.date),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.gray,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormatter.formatTime(
                              DateFormatter.parseDateTime(transaction.date),
                            ),
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.gray,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _SettleToggle(
                            transaction: transaction,
                            paid: paidAmount,
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (projectName != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.lightGrayBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        projectName!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.gray,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 12),
              _AttachmentStrip(attachments: attachments),
            ],
            const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ),
      ),
    );
  }
}

/// Small pill used for both the settled and the installment status.
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    this.outlined = false,
  });

  final String label;
  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: outlined
            ? Border.all(color: color.withValues(alpha: 0.35))
            : null,
      ),
      child: Text(
        label,
        style: AppTextStyles.bodySmall.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// "مدفوع X من Y" plus a hairline progress bar for installment rows.
class _PartialProgress extends StatelessWidget {
  const _PartialProgress({
    required this.amount,
    required this.paid,
    required this.color,
  });

  final double amount;
  final double paid;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final clamped = amount <= 0 ? 0.0 : (paid / amount).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'مدفوع ${CurrencyFormatter.format(paid)} من ${CurrencyFormatter.format(amount)}',
          style: AppTextStyles.bodySmall.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: clamped,
            minHeight: 4,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

/// The settle action: opens the settlement options sheet while money is
/// still outstanding, and asks before wiping the history once it is not.
///
/// Status is derived from the payment book, so there is no flag to flip here.
/// Works from any list: it writes through [transactionActionsProvider], which
/// bumps [dataVersionProvider] so every open screen refreshes.
class _SettleToggle extends ConsumerWidget {
  const _SettleToggle({required this.transaction, required this.paid});

  final Transaction transaction;
  final double paid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settled = transaction.isSettled;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleTap(context, ref),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            settled ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 22,
            color: settled ? AppColors.green : AppColors.gray,
          ),
        ),
      ),
    );
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    if (!transaction.isSettled) {
      await showSettlementSheet(context: context, txn: transaction, paid: paid);
      return;
    }

    final confirmed = await confirmUnsettle(context, transaction);
    if (!context.mounted || !confirmed) return;

    try {
      await ref.read(transactionActionsProvider).clearPayments(transaction.id!);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر تحديث حالة العملية')),
        );
      }
    }
  }
}

class _AttachmentStrip extends StatelessWidget {
  final List<TransactionAttachment> attachments;

  const _AttachmentStrip({required this.attachments});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final attachment = attachments[index];
          return GestureDetector(
            onTap: () => _openFullScreenViewer(context, index),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(attachment.filePath),
                width: 70,
                height: 70,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 70,
                  height: 70,
                  color: AppColors.lightGrayBg,
                  child: const Icon(Icons.broken_image, color: AppColors.gray),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openFullScreenViewer(BuildContext context, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageFullScreenViewer(
          attachments: attachments,
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}
