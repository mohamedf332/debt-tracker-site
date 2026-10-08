import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

class ProjectContextMenu extends StatelessWidget {
  final String projectName;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  const ProjectContextMenu({
    super.key,
    required this.projectName,
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
                const Icon(Icons.folder, color: AppColors.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    projectName,
                    style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          // Menu items
          _MenuItem(
            icon: Icons.edit_outlined,
            label: 'تعديل المشروع',
            color: AppColors.primary,
            onTap: onEdit,
          ),
          _MenuItem(
            icon: Icons.archive_outlined,
            label: 'أرشفة المشروع',
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
      // Overlay, not a route: popping here would pop the screen. The owner
      // hides the menu through its own callback.
      onTap: onTap,
    );
  }
}