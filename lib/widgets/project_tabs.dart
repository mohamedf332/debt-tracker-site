import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../models/project.dart';
import '../../providers/person_detail_provider.dart';
import 'hold_gesture_detector.dart';

class ProjectTabs extends ConsumerWidget {
  final int? activeProjectId;
  final List<Project> projects;
  final ValueChanged<int?> onTabChanged;
  final VoidCallback onAddProject;

  /// Long press on a project chip. Never fired for the "الكل" tab, which has no
  /// project of its own.
  final void Function(Project project, Offset position)? onProjectLongPress;
  final int? longPressedProjectId;

  const ProjectTabs({
    super.key,
    required this.activeProjectId,
    required this.projects,
    required this.onTabChanged,
    required this.onAddProject,
    this.onProjectLongPress,
    this.longPressedProjectId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // Tabs row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // "الكل" tab - not a real project, so no context menu and no hold
              // feedback. The swallowed long press still matters: without it a
              // long press would fall through to onTap and switch the tab.
              _ProjectTab(
                label: 'الكل',
                isSelected: activeProjectId == null,
                onTap: () => onTabChanged(null),
                swallowLongPress: true,
              ),
              const SizedBox(width: 8),
              // Project tabs
              ...projects.map((project) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _ProjectTab(
                      label: project.name,
                      isSelected: activeProjectId == project.id,
                      onTap: () => onTabChanged(project.id),
                      onLongPress: onProjectLongPress == null
                          ? null
                          : (position) => onProjectLongPress!(project, position),
                      isLongPressed: longPressedProjectId == project.id,
                    ),
                  )),
              // Add project button
              _AddProjectButton(onTap: onAddProject),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1),
      ],
    );
  }
}

class _ProjectTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  /// Global position of the long press, so the caller can anchor the menu.
  /// Non-null means this chip owns a context menu: it gets the full hold
  /// treatment (progress fill + vibration + menu on release).
  final ValueChanged<Offset>? onLongPress;

  /// Eats long presses with no feedback at all. Used by the "الكل" tab, which
  /// has no menu of its own.
  final bool swallowLongPress;
  final bool isLongPressed;

  const _ProjectTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
    this.swallowLongPress = false,
    this.isLongPressed = false,
  });

  @override
  Widget build(BuildContext context) {
    final Widget body = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary : AppColors.lightGrayBg,
        borderRadius: BorderRadius.circular(20),
        border: isLongPressed
            ? Border.all(color: AppColors.primary, width: 2)
            : Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.labelLarge.copyWith(
              color: isSelected ? AppColors.white : AppColors.dark,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (isLongPressed) ...[
            const SizedBox(width: 4),
            const Icon(Icons.more_vert, size: 16, color: AppColors.primary),
          ],
        ],
      ),
    );

    if (onLongPress != null) {
      // Dark fill: the chip is either near-white or already solid cyan, so the
      // primary colour would be invisible on the selected one.
      return HoldGestureDetector(
        onTap: onTap,
        onLongPress: onLongPress!,
        progressColor: AppColors.dark,
        progressClip: BorderRadius.circular(20),
        child: body,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: swallowLongPress ? () {} : null,
      child: body,
    );
  }
}

class _AddProjectButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddProjectButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.lightGrayBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, style: BorderStyle.solid),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 18, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(
              'مشروع جديد',
              style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}