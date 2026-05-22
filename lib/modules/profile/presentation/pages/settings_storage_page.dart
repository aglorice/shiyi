import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/page_section.dart';
import '../widgets/settings_widgets.dart';

class SettingsStoragePage extends ConsumerWidget {
  const SettingsStoragePage({super.key});

  static const _businessCachePrefixes = [
    'schedule.snapshot.',
    'grades.snapshot.',
    'exams.snapshot.',
    'electricity.dashboard.',
    'gym.overview.',
    'gym.appointments',
    'gym.recommendations',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('存储与缓存')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.pageBottomGap),
        children: [
          PageSection(
            title: '清理',
            children: [
              SettingActionTile(
                icon: Icons.delete_sweep_outlined,
                title: '清除业务缓存',
                subtitle: '课表、成绩、考试、电费、场馆',
                onTap: () => _clearBusinessCache(context, ref),
              ),
              SettingActionTile(
                icon: Icons.refresh_rounded,
                title: '重置外观偏好',
                subtitle: '主题、字号、布局回到默认',
                onTap: () => _resetAppearance(context, ref),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageH,
              AppSpacing.lg,
              AppSpacing.pageH,
              0,
            ),
            child: Text(
              '清理只会移除本地缓存，不会影响学校系统里的真实数据。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearBusinessCache(BuildContext context, WidgetRef ref) async {
    final preferences = ref.read(sharedPreferencesProvider);
    final keysToDelete = preferences
        .getKeys()
        .where(
          (key) =>
              _businessCachePrefixes.any((prefix) => key.startsWith(prefix)),
        )
        .toList();

    for (final key in keysToDelete) {
      await preferences.remove(key);
    }

    if (context.mounted) {
      AppSnackBar.show(
        context,
        message: keysToDelete.isEmpty
            ? '当前没有可清除的业务缓存'
            : '已清除 ${keysToDelete.length} 项缓存',
        tone: AppSnackBarTone.success,
        icon: Icons.delete_sweep_rounded,
      );
    }
  }

  Future<void> _resetAppearance(BuildContext context, WidgetRef ref) async {
    await ref.read(appPreferencesControllerProvider.notifier).resetAppearance();
    if (context.mounted) {
      AppSnackBar.show(
        context,
        message: '外观偏好已恢复默认',
        tone: AppSnackBarTone.success,
      );
    }
  }
}
