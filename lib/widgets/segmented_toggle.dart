import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

class SegmentedToggle<T> extends StatelessWidget {
  final T selectedValue;
  final List<SegmentedToggleOption<T>> options;
  final ValueChanged<T> onChanged;
  final Color? selectedColor;
  final Color? unselectedColor;

  const SegmentedToggle({
    super.key,
    required this.selectedValue,
    required this.options,
    required this.onChanged,
    this.selectedColor,
    this.unselectedColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: unselectedColor ?? AppColors.lightGrayBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: options.map((option) {
          final isSelected = option.value == selectedValue;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(option.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? (selectedColor ?? AppColors.primary) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (option.icon != null) ...[
                      Icon(
                        option.icon,
                        size: 18,
                        color: isSelected ? AppColors.white : AppColors.gray,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      option.label,
                      style: AppTextStyles.labelLarge.copyWith(
                        color: isSelected ? AppColors.white : AppColors.gray,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class SegmentedToggleOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  const SegmentedToggleOption({
    required this.value,
    required this.label,
    this.icon,
  });
}