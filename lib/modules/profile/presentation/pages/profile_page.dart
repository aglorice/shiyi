import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../app/settings/app_preferences.dart';
import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../core/error/error_display.dart';
import '../../../../core/platform/app_installer_service.dart';
import '../../../../core/result/result.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/schedule_background.dart';
import '../../../../shared/widgets/surface_card.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../controllers/app_update_controller.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider).value;
    final preferences = ref.watch(appPreferencesControllerProvider);
    final controller = ref.read(appPreferencesControllerProvider.notifier);
    final session = authState?.session;
    final rawDisplayName = session?.displayName.trim() ?? '';
    final displayName = rawDisplayName.isEmpty ? '未登录' : rawDisplayName;
    final initial = displayName.isNotEmpty ? displayName.substring(0, 1) : '?';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 112),
      children: [
        const SizedBox(height: 16),
        SurfaceCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  initial,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${session?.userId ?? '-'} · ${session?.profile?.deptName ?? '暂未同步院系'}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: '界面外观',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingSwitchTile(
                icon: Icons.dark_mode_outlined,
                title: '深色主题',
                subtitle: '晚上或低亮度环境更耐看',
                value: preferences.darkMode,
                onChanged: controller.setDarkMode,
              ),
              const SizedBox(height: 8),
              _SettingSwitchTile(
                icon: Icons.contrast_outlined,
                title: '增强对比',
                subtitle: '让文字和边界更清楚',
                value: preferences.highContrast,
                onChanged: controller.setHighContrast,
              ),
              const SizedBox(height: 8),
              _SettingSwitchTile(
                icon: Icons.view_compact_alt_outlined,
                title: '紧凑布局',
                subtitle: '让页面更利落，信息密度更高',
                value: preferences.compactMode,
                onChanged: controller.setCompactMode,
              ),
              const SizedBox(height: 20),
              Text(
                '主题色',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              for (final preset in AppThemePreset.values) ...[
                _ThemePresetTile(
                  preset: preset,
                  selected: preferences.themePreset == preset,
                  onTap: () => controller.setThemePreset(preset),
                ),
                if (preset != AppThemePreset.values.last)
                  const SizedBox(height: 10),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    '字体大小',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    preferences.fontScaleLabel,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              Slider(
                value: preferences.fontScale,
                min: 0.9,
                max: 1.2,
                divisions: 6,
                label: preferences.fontScaleLabel,
                onChanged: controller.setFontScale,
              ),
              Text(
                '字体风格',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              SegmentedButton<AppFontPreset>(
                multiSelectionEnabled: false,
                showSelectedIcon: false,
                segments: AppFontPreset.values
                    .map(
                      (preset) => ButtonSegment<AppFontPreset>(
                        value: preset,
                        label: Text(preset.label),
                      ),
                    )
                    .toList(),
                selected: {preferences.fontPreset},
                onSelectionChanged: (selection) {
                  controller.setFontPreset(selection.first);
                },
              ),
              const SizedBox(height: 10),
              Text(
                preferences.fontPreset.description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: '课表个性化',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingSwitchTile(
                icon: Icons.view_week_outlined,
                title: '显示周六周天',
                subtitle: '关闭后整周课表只显示周一到周五',
                value: preferences.showWeekends,
                onChanged: controller.setShowWeekends,
              ),
              const SizedBox(height: 20),
              Text(
                '背景样式',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              _ScheduleBackgroundPresetGrid(
                selected: preferences.scheduleBackgroundStyle,
                opacity: preferences.scheduleBackgroundOpacity,
                onSelected: controller.setScheduleBackgroundStyle,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    '背景强度',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(preferences.scheduleBackgroundOpacity * 100).round()}%',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              Slider(
                value: preferences.scheduleBackgroundOpacity,
                min: 0,
                max: 1,
                divisions: 10,
                label:
                    '${(preferences.scheduleBackgroundOpacity * 100).round()}%',
                onChanged: controller.setScheduleBackgroundOpacity,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: '应用操作',
          child: Column(
            children: [
              _ActionTile(
                icon: Icons.refresh_outlined,
                title: '重置外观偏好',
                subtitle: '恢复默认主题、字号和布局设置',
                onTap: () async {
                  await controller.resetAppearance();
                  if (context.mounted) {
                    AppSnackBar.show(
                      context,
                      message: '外观偏好已恢复默认',
                      tone: AppSnackBarTone.success,
                    );
                  }
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Divider(height: 1),
              ),
              _ActionTile(
                icon: Icons.delete_outline_rounded,
                title: '清除业务缓存',
                subtitle: '删除课表、成绩、考试等本地缓存',
                onTap: () => _clearBusinessCache(context, ref),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Divider(height: 1),
              ),
              _ActionTile(
                icon: Icons.system_update_alt_rounded,
                title: '版本更新',
                subtitle: '检查新版本并安装',
                onTap: () => _showUpdateSheet(context, ref),
                trailing: const _UpdateTileTrailing(),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Divider(height: 1),
              ),
              _ActionTile(
                icon: Icons.info_outline_rounded,
                title: '关于应用',
                subtitle: '查看版本信息与 GitHub 仓库',
                onTap: () => context.push('/about'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              side: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.error.withValues(alpha: 0.28),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('退出登录'),
          ),
        ),
      ],
    );
  }

  void _showUpdateSheet(BuildContext context, WidgetRef ref) {
    ref.invalidate(appUpdateStatusProvider);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _UpdateSheet(),
    );
  }

  Future<void> _clearBusinessCache(BuildContext context, WidgetRef ref) async {
    final preferences = ref.read(sharedPreferencesProvider);
    final prefixes = [
      'schedule.snapshot.',
      'grades.snapshot.',
      'exams.snapshot.',
      'electricity.dashboard.',
      'gym.overview.',
    ];
    final keysToDelete = preferences
        .getKeys()
        .where((key) => prefixes.any((prefix) => key.startsWith(prefix)))
        .toList();

    for (final key in keysToDelete) {
      await preferences.remove(key);
    }

    if (context.mounted) {
      AppSnackBar.show(
        context,
        message: keysToDelete.isEmpty ? '当前没有可清除的业务缓存' : '业务缓存已清除',
        tone: AppSnackBarTone.success,
        icon: Icons.delete_sweep_rounded,
      );
    }
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ThemePresetTile extends StatelessWidget {
  const _ThemePresetTile({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final AppThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.75)
          : colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: preset.seedColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preset.description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleBackgroundPresetGrid extends StatelessWidget {
  const _ScheduleBackgroundPresetGrid({
    required this.selected,
    required this.opacity,
    required this.onSelected,
  });

  final ScheduleBackgroundStyle selected;
  final double opacity;
  final ValueChanged<ScheduleBackgroundStyle> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 360;
        final itemWidth = useTwoColumns
            ? (constraints.maxWidth - 10) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final style in ScheduleBackgroundStyle.values)
              SizedBox(
                width: itemWidth,
                child: _ScheduleBackgroundPresetTile(
                  style: style,
                  selected: selected == style,
                  opacity: opacity,
                  onTap: () => onSelected(style),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ScheduleBackgroundPresetTile extends StatelessWidget {
  const _ScheduleBackgroundPresetTile({
    required this.style,
    required this.selected,
    required this.opacity,
    required this.onTap,
  });

  final ScheduleBackgroundStyle style;
  final bool selected;
  final double opacity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.72)
          : colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 46,
                height: 46,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colorScheme.outlineVariant),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: ScheduleBackground(
                        style: style,
                        opacity: style == ScheduleBackgroundStyle.clean
                            ? 0
                            : opacity.clamp(0.22, 0.42).toDouble(),
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    Center(
                      child: Icon(
                        style.icon,
                        color: style.accentColor,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      style.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      style.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.32,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.68),
                size: 19,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingSwitchTile extends StatelessWidget {
  const _SettingSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ],
        ),
      ),
    );
  }
}

class _UpdateTileTrailing extends ConsumerWidget {
  const _UpdateTileTrailing();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final installed = ref.watch(
      installedAppInfoProvider.select(
        (value) => value.maybeWhen(data: (data) => data, orElse: () => null),
      ),
    );
    final updateAsync = ref.watch(appUpdateStatusProvider);

    final label = switch (updateAsync) {
      AsyncData<AppUpdateStatus>(:final value)
          when value.hasUpdate && value.latestVersionLabel != null =>
        'v${value.latestVersionLabel}',
      AsyncData<AppUpdateStatus>() => '已最新',
      AsyncError<AppUpdateStatus>() => '重试',
      _ when installed != null => 'v${installed.version}',
      _ => '检查中',
    };

    final highlighted = updateAsync.maybeWhen(
      data: (value) => value.hasUpdate,
      orElse: () => false,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: highlighted
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: highlighted
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Icon(
          Icons.chevron_right_rounded,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _UpdateSheet extends ConsumerWidget {
  const _UpdateSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statusAsync = ref.watch(appUpdateStatusProvider);
    final installed = ref.watch(
      installedAppInfoProvider.select(
        (value) => value.maybeWhen(data: (data) => data, orElse: () => null),
      ),
    );
    final actionState = ref.watch(appUpdateActionStateProvider);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: statusAsync.when(
        loading: () => _UpdateSheetScaffold(
          title: '版本更新',
          child: SizedBox(
            height: 180,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(strokeWidth: 2),
                  const SizedBox(height: 14),
                  Text(
                    installed == null
                        ? '正在检查最新版本'
                        : '当前 v${installed.versionLabel} · 正在检查',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        error: (error, _) => _UpdateSheetScaffold(
          title: '版本更新',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                installed == null
                    ? '版本信息读取失败'
                    : '当前版本 v${installed.versionLabel}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '检查更新失败',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => ref.invalidate(appUpdateStatusProvider),
                      child: const Text('重试'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        data: (status) =>
            _buildLoadedContent(context, ref, status, actionState),
      ),
    );
  }

  Widget _buildLoadedContent(
    BuildContext context,
    WidgetRef ref,
    AppUpdateStatus status,
    AppUpdateActionState actionState,
  ) {
    final theme = Theme.of(context);
    if (status.hasError && !status.hasRelease) {
      return _UpdateSheetScaffold(
        title: '版本更新',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前版本 v${status.currentVersionLabel}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              status.failure!.message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => ref.invalidate(appUpdateStatusProvider),
                    child: const Text('重试'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final release = status.release;
    final publishedAt = release?.publishedAt;
    final releaseLines = _releaseLines(release?.notes ?? '');

    final buttonLabel = switch ((actionState.busy, actionState.progress)) {
      (true, final progress?) =>
        '下载中 ${(progress * 100).clamp(0, 100).round()}%',
      (true, _) => '处理中...',
      _
          when status.hasUpdate &&
              actionState.downloadedVersion == status.latestVersionLabel =>
        '继续安装',
      _ when status.hasUpdate => '下载并安装',
      _ => '已是最新版本',
    };

    return _UpdateSheetScaffold(
      title: '版本更新',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status.hasUpdate
                ? 'v${status.latestVersionLabel}'
                : 'v${status.currentVersionLabel}',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            status.hasUpdate
                ? '当前 v${status.currentVersionLabel}'
                : '当前已经是最新版本',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (publishedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              DateFormat('yyyy-MM-dd HH:mm').format(publishedAt.toLocal()),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (status.hasError) ...[
            const SizedBox(height: 12),
            Text(
              status.failure!.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (status.hasUpdate) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '更新内容',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final line in releaseLines) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            line,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (line != releaseLines.last) const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: actionState.busy
                      ? null
                      : () => Navigator.pop(context),
                  child: Text(status.hasUpdate ? '稍后' : '关闭'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: !status.hasUpdate || actionState.busy
                      ? null
                      : () => _handleUpdate(context, ref, status),
                  child: Text(buttonLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleUpdate(
    BuildContext context,
    WidgetRef ref,
    AppUpdateStatus status,
  ) async {
    final result = await ref
        .read(appUpdateControllerProvider)
        .downloadOrInstall(status);

    if (!context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    switch (result) {
      case Success<AppUpdateActionOutcome>(data: final outcome):
        final installResult = outcome.installResult;
        switch (installResult.status) {
          case ApkInstallStatus.started:
            AppSnackBar.show(
              context,
              message: installResult.message ?? '已打开系统安装器',
              tone: AppSnackBarTone.success,
              icon: Icons.download_done_rounded,
              clearCurrent: false,
            );
            Navigator.pop(context);
          case ApkInstallStatus.permissionRequired:
            AppSnackBar.show(
              context,
              message: installResult.message ?? '请先允许安装未知来源应用，然后再点一次安装。',
              tone: AppSnackBarTone.info,
              icon: Icons.shield_outlined,
              clearCurrent: false,
            );
        }
      case FailureResult<AppUpdateActionOutcome>(failure: final failure):
        AppSnackBar.show(
          context,
          message: formatError(failure).message,
          tone: AppSnackBarTone.error,
          clearCurrent: false,
        );
    }
  }

  List<String> _releaseLines(String raw) {
    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .map((line) => line.replaceFirst(RegExp(r'^[-*]\s+'), ''))
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .take(5)
        .toList();

    return lines.isEmpty ? const ['包含若干改进与修复'] : lines;
  }
}

class _UpdateSheetScaffold extends StatelessWidget {
  const _UpdateSheetScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 18),
        child,
      ],
    );
  }
}
