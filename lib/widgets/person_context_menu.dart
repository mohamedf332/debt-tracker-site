import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../models/person.dart';

class PersonContextMenu extends StatelessWidget {
  final Person person;
  final bool isPinned;
  final VoidCallback onPinToggle;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  const PersonContextMenu({
    super.key,
    required this.person,
    required this.isPinned,
    required this.onPinToggle,
    required this.onEdit,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.lightCyan,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Text(
                    person.name.isNotEmpty ? person.name[0] : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    person.name,
                    style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          // Menu items
          _MenuItem(
            icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin,
            label: isPinned ? 'إلغاء التثبيت' : 'تثبيت',
            color: AppColors.primary,
            onTap: onPinToggle,
          ),
          _MenuItem(
            icon: Icons.edit_outlined,
            label: 'تعديل',
            color: AppColors.primary,
            onTap: onEdit,
          ),
          _MenuItem(
            icon: Icons.archive_outlined,
            label: 'أرشفة',
            color: AppColors.orange,
            onTap: onArchive,
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: AppTextStyles.bodyLarge),
      textColor: color,
      // No Navigator.pop: this menu is an overlay inside the screen's Stack,
      // not a route. Popping here would pop the screen itself. The owner
      // hides the menu through its own callback.
      onTap: onTap,
    );
  }
}