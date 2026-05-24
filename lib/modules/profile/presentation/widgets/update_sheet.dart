import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../app/settings/github_mirror.dart';
import '../../../../core/error/error_display.dart';
import '../../../../core/platform/app_installer_service.dart';
import '../../../../core/result/result.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../controllers/app_update_controller.dart';

/// 检查更新底部抽屉。
/// 之前耦合在 ProfilePage 1100 行文件里，这里抽出来独立维护。
class UpdateSheet extends ConsumerWidget {
  const UpdateSheet({super.key});

  static Future<void> show(BuildContext context, WidgetRef ref) {
    ref.invalidate(appUpdateStatusProvider);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const UpdateSheet(),
    );
  }

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
    final mirror = ref.watch(
      appPreferencesControllerProvider
          .select((p) => p.resolvedGithubMirrorBundle.selected),
    );

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
          mirror: mirror,
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
          mirror: mirror,
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
            _buildLoadedContent(context, ref, status, actionState, mirror),
      ),
    );
  }

  Widget _buildLoadedContent(
    BuildContext context,
    WidgetRef ref,
    AppUpdateStatus status,
    AppUpdateActionState actionState,
    GithubMirror mirror,
  ) {
    final theme = Theme.of(context);
    if (status.hasError && !status.hasRelease) {
      return _UpdateSheetScaffold(
        title: '版本更新',
        mirror: mirror,
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
      mirror: mirror,
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
  const _UpdateSheetScaffold({
    required this.title,
    required this.child,
    required this.mirror,
  });

  final String title;
  final Widget child;
  final GithubMirror mirror;

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
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            _MirrorChip(mirror: mirror),
          ],
        ),
        const SizedBox(height: 18),
        child,
      ],
    );
  }
}

class _MirrorChip extends StatelessWidget {
  const _MirrorChip({required this.mirror});

  final GithubMirror mirror;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDirect = mirror.id == GithubMirror.direct.id;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        Navigator.of(context).maybePop();
        // 等 sheet 关掉再 push，避免导航栈奇怪。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // ignore: use_build_context_synchronously
          GoRouter.of(context).push('/settings/github-mirror');
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDirect
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isDirect
                  ? Icons.cloud_outlined
                  : Icons.cloud_sync_rounded,
              size: 14,
              color: isDirect
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 4),
            Text(
              isDirect ? 'GitHub 直连' : mirror.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isDirect
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ProfilePage 入口列表里那个右侧 trailing。
/// 显示当前已安装版本号，或当前的更新状态简要标签。
class UpdateTileTrailing extends ConsumerWidget {
  const UpdateTileTrailing({super.key});

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

    final highlighted =
        updateAsync is AsyncData<AppUpdateStatus> && updateAsync.value.hasUpdate;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          size: 20,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }
}
