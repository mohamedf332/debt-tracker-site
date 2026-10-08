import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/currency_formatter.dart';
import '../../models/project.dart';
import '../../providers/person_detail_provider.dart';

class BudgetCard extends ConsumerWidget {
  final Project project;
  final double budgetRemaining;

  const BudgetCard({
    super.key,
    required this.project,
    required this.budgetRemaining,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budget = project.budget!;
    final progress = budget > 0 ? (budgetRemaining / budget).clamp(0.0, 1.0) : 0.0;
    final isOverBudget = budgetRemaining < 0;
    final progressColor = isOverBudget ? AppColors.red : AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightCyan,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('البادجت', style: AppTextStyles.titleMedium),
              Text(
                CurrencyFormatter.formatWithSign(budget),
                style: AppTextStyles.titleMedium.copyWith(
                  color: budget >= 0 ? AppColors.green : AppColors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('المتبقي', style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray)),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyFormatter.formatWithSign(budgetRemaining),
                      style: AppTextStyles.headlineSmall.copyWith(
                        color: budgetRemaining >= 0 ? AppColors.green : AppColors.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (budget > 0) ...[
                const SizedBox(width: 16),
                SizedBox(
                  width: 80,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('الاستهلاك', style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray)),
                      const SizedBox(height: 4),
                      Stack(
                        children: [
                          Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: AppColors.border,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: progress,
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: progressColor,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Rule 3: the budget figure only counts settled transactions.
          Row(
            children: [
              const Icon(Icons.info_outline, size: 14, color: AppColors.gray),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'المتبقي محسوب على العمليات المسدَّدة فقط',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.gray),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
