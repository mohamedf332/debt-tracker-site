import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// The balance card shrunk down to one row so it can live in the app bar once
/// the real card has scrolled away. Same two fields as [BalanceCard], same
/// colours, just a lot shorter.
class CompactBalanceBar extends StatelessWidget {
  const CompactBalanceBar({
    super.key,
    required this.theyOweMe,
    required this.iOweThem,
  });

  final double theyOweMe;
  final double iOweThem;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CompactField(
            label: 'ليّ عنده',
            amount: theyOweMe,
            color: AppColors.greenOnPrimary,
          ),
          Container(
            width: 1,
            height: 26,
            color: AppColors.white.withValues(alpha: 0.35),
          ),
          const SizedBox(width: 10),
          _CompactField(
            label: 'عليّا له',
            amount: iOweThem,
            color: AppColors.redOnPrimary,
          ),
        ],
      ),
    );
  }
}

class _CompactField extends StatelessWidget {
  const _CompactField({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(
            fontSize: 9,
            color: AppColors.white.withValues(alpha: 0.8),
            height: 1.1,
          ),
        ),
        Text(
          '${amount >= 0 ? '+' : '-'}${amount.abs().toStringAsFixed(0)} ج.م',
          style: AppTextStyles.bodyMedium.copyWith(
            fontSize: 13,
            height: 1.2,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// App-bar title that swaps the normal title for the [CompactBalanceBar] once
/// `progress` says the header has scrolled away.
class CollapsingAppBarTitle extends StatelessWidget {
  const CollapsingAppBarTitle({
    super.key,
    required this.progress,
    required this.title,
    required this.theyOweMe,
    required this.iOweThem,
    this.threshold = 0.5,
  });

  /// 0 = header fully visible, 1 = header fully scrolled out.
  final ValueListenable<double> progress;
  final Widget title;
  final double theyOweMe;
  final double iOweThem;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, t, _) {
          final collapsed = t >= threshold;
          return AnimatedCrossFade(
            duration: const Duration(milliseconds: 240),
            sizeCurve: Curves.easeOutCubic,
            // Both states are centred so the normal title does not jump when
            // the bar is wider than it.
            alignment: Alignment.center,
            crossFadeState:
                collapsed ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: title,
            secondChild: FittedBox(
              fit: BoxFit.scaleDown,
              child: CompactBalanceBar(
                theyOweMe: theyOweMe,
                iOweThem: iOweThem,
              ),
            ),
          );
        },
      ),
    );
  }
}
