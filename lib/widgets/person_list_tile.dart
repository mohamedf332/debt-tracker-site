import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../models/person.dart';
import 'hold_gesture_detector.dart';

class PersonListTile extends ConsumerWidget {
  final Person person;
  final double balance;
  final VoidCallback onTap;

  /// Fired on release when the tile was held for at least kLongPressTimeout
  /// without moving more than 8px. Carries the global release position so the
  /// caller can place the context menu next to the tile.
  final ValueChanged<Offset> onLongPress;

  const PersonListTile({
    super.key,
    required this.person,
    required this.balance,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPositive = balance > 0;
    final isNegative = balance < 0;
    final balanceColor = isPositive ? AppColors.green : isNegative ? AppColors.red : AppColors.gray;
    final balanceLabel = isPositive ? 'ليّ عنده' : isNegative ? 'عليّا له' : 'متساوي';

    return HoldGestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: person.isPinnedBool ? AppColors.lightCyan : AppColors.white,
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: person.isPinnedBool
                  ? const Icon(Icons.push_pin, color: AppColors.primary, size: 24)
                  : null,
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      person.name,
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: balanceColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        balanceLabel,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: balanceColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      balance >= 0 ? '+${balance.toStringAsFixed(0)}' : balance.toStringAsFixed(0),
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: balanceColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(' ج.م', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              trailing: const Icon(Icons.chevron_left, color: AppColors.gray),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ),
      ),
    );
  }
}
