import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/currency_formatter.dart';

class BalanceCard extends ConsumerWidget {
  final double theyOweMe;
  final double iOweThem;

  /// Signed total of SETTLED rows (they_owe_me +, i_owe_them -), shown as a
  /// secondary line so users can still see the money that changed hands.
  final double settledTotal;

  const BalanceCard({
    super.key,
    required this.theyOweMe,
    required this.iOweThem,
    this.settledTotal = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final net = theyOweMe - iOweThem;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _BalanceItem(
                  label: 'ليّ عند الناس',
                  amount: theyOweMe,
                  color: AppColors.greenOnPrimary,
                  isPositive: true,
                ),
              ),
              Container(
                width: 1,
                height: 50,
                color: AppColors.white.withValues(alpha: 0.3),
              ),
              Expanded(
                child: _BalanceItem(
                  label: 'عليّا للناس',
                  amount: iOweThem,
                  color: AppColors.redOnPrimary,
                  isPositive: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white30, thickness: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'الصافي: ',
                style: AppTextStyles.bodyLarge.copyWith(color: AppColors.white.withValues(alpha: 0.9)),
              ),
              Text(
                CurrencyFormatter.formatWithSign(net),
                style: AppTextStyles.headlineMedium.copyWith(
                  color: net >= 0 ? AppColors.greenOnPrimary : AppColors.redOnPrimary,
                ),
              ),
              const Text(' ج.م', style: TextStyle(fontSize: 18, color: Colors.white)),
            ],
          ),
          if (settledTotal.abs() > 0.009) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'مسدَّد: ',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.white.withValues(alpha: 0.75),
                  ),
                ),
                Text(
                  CurrencyFormatter.formatWithSign(settledTotal),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  ' ج.م',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BalanceItem extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final bool isPositive;

  const _BalanceItem({
    required this.label,
    required this.amount,
    required this.color,
    required this.isPositive,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.white.withValues(alpha: 0.8)),
        ),
        const SizedBox(height: 4),
        Text(
          '${isPositive ? '+' : ''}${amount.toStringAsFixed(0)} ج.م',
          style: AppTextStyles.headlineSmall.copyWith(color: color),
        ),
      ],
    );
  }
}