import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../models/transaction.dart';
import '../../providers/person_detail_provider.dart';

class FilterTabs extends ConsumerWidget {
  final TransactionType? selectedType;
  final SettlementFilter settlementFilter;
  final DateTime? startDate;
  final DateTime? endDate;
  final ValueChanged<TransactionType?> onTypeChanged;
  final ValueChanged<SettlementFilter> onSettlementChanged;
  final ValueChanged<DateTime?> onStartDateChanged;
  final ValueChanged<DateTime?> onEndDateChanged;

  const FilterTabs({
    super.key,
    required this.selectedType,
    this.settlementFilter = SettlementFilter.all,
    required this.startDate,
    required this.endDate,
    required this.onTypeChanged,
    required this.onSettlementChanged,
    required this.onStartDateChanged,
    required this.onEndDateChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // Type filter
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _FilterChip(
                label: 'الكل',
                isSelected: selectedType == null,
                onTap: () => onTypeChanged(null),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: ' عندي ليَّ',
                icon: Icons.arrow_downward,
                isSelected: selectedType == TransactionType.theyOweMe,
                onTap: () => onTypeChanged(TransactionType.theyOweMe),
                color: AppColors.green,
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'عليّا',
                icon: Icons.arrow_upward,
                isSelected: selectedType == TransactionType.iOweThem,
                onTap: () => onTypeChanged(TransactionType.iOweThem),
                color: AppColors.red,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Settlement filter (rule 4)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final (index, filter) in SettlementFilter.values.indexed) ...[
                if (index > 0) const SizedBox(width: 8),
                _FilterChip(
                  label: filter.arabicLabel,
                  icon: switch (filter) {
                    SettlementFilter.all => Icons.list,
                    SettlementFilter.unsettled => Icons.radio_button_unchecked,
                    SettlementFilter.settled => Icons.check_circle,
                  },
                  isSelected: settlementFilter == filter,
                  onTap: () => onSettlementChanged(filter),
                  color: switch (filter) {
                    SettlementFilter.all => AppColors.primary,
                    SettlementFilter.unsettled => AppColors.red,
                    SettlementFilter.settled => AppColors.green,
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Date filter
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _DateFilterButton(
                  label: 'من',
                  date: startDate,
                  onTap: () => _pickDate(context, true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DateFilterButton(
                  label: 'إلى',
                  date: endDate,
                  onTap: () => _pickDate(context, false),
                ),
              ),
              if (startDate != null || endDate != null) ...[
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () {
                    onStartDateChanged(null);
                    onEndDateChanged(null);
                  },
                  icon: const Icon(Icons.clear, color: AppColors.gray),
                  tooltip: 'مسح الفلترة',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate(BuildContext context, bool isStart) async {
    final initialDate = isStart
        ? startDate ?? DateTime.now()
        : endDate ?? DateTime.now();
    final firstDate = DateTime(2020);
    final lastDate = DateTime.now().add(const Duration(days: 365));

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      locale: const Locale('ar'),
      builder: (context, child) => Theme(
        data: Theme.of(
          context,
        ).copyWith(colorScheme: ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );

    if (picked != null) {
      if (isStart) {
        onStartDateChanged(picked);
      } else {
        onEndDateChanged(picked);
      }
    }
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.primary;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : effectiveColor,
            ),
            const SizedBox(width: 4),
          ],
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: effectiveColor,
      backgroundColor: AppColors.lightGrayBg,
      labelStyle: AppTextStyles.labelLarge.copyWith(
        color: isSelected ? Colors.white : AppColors.gray,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isSelected ? effectiveColor : AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }
}

class _DateFilterButton extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  const _DateFilterButton({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasDate = date != null;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: BorderSide(color: hasDate ? AppColors.primary : AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            hasDate ? '${date!.day}/${date!.month}/${date!.year}' : label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: hasDate ? AppColors.primary : AppColors.gray,
            ),
          ),
        ],
      ),
    );
  }
}
