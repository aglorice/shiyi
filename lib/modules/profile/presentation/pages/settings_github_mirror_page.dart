import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/app_providers.dart';
import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../app/settings/github_mirror.dart';
import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../../../shared/widgets/page_section.dart';

/// 「设置 → GitHub 镜像」页：列出全部镜像 + 测速 + 选中 + 自定义。
class SettingsGithubMirrorPage extends ConsumerStatefulWidget {
  const SettingsGithubMirrorPage({super.key});

  @override
  ConsumerState<SettingsGithubMirrorPage> createState() =>
      _SettingsGithubMirrorPageState();
}

class _SettingsGithubMirrorPageState
    extends ConsumerState<SettingsGithubMirrorPage> {
  /// id → 测得延迟 ms；null 表示失败；缺省表示还没测过。
  final Map<String, int?> _latencies = {};
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    // 进页后台默默跑一次测速，不阻塞 UI；用户不用专门点右上角才能看到延迟。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bundle = ref
          .read(appPreferencesControllerProvider)
          .resolvedGithubMirrorBundle;
      _testAll(bundle.mirrors);
    });
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(appPreferencesControllerProvider);
    final bundle = preferences.resolvedGithubMirrorBundle;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GitHub 镜像'),
        actions: [
          IconButton(
            tooltip: _testing ? '测速中…' : '测速',
            onPressed: _testing ? null : () => _testAll(bundle.mirrors),
            icon: _testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.speed_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.pageBottomGap),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageH,
              AppSpacing.lg,
              AppSpacing.pageH,
              AppSpacing.sm,
            ),
            child: Text(
              '版本更新下载安装包时优先走选中的镜像，失败时自动回落 GitHub。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          PageSection(
            title: '可用镜像',
            children: [
              for (final mirror in bundle.mirrors)
                _MirrorTile(
                  mirror: mirror,
                  selected: bundle.selectedId == mirror.id,
                  latency: _latencies[mirror.id],
                  testing: _testing,
                  onTap: () => _select(mirror),
                  onDelete: mirror.builtin
                      ? null
                      : () => _remove(mirror),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageH,
              AppSpacing.lg,
              AppSpacing.pageH,
              AppSpacing.lg,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _addMirror(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('添加自定义镜像'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _select(GithubMirror mirror) async {
    final preferences = ref.read(appPreferencesControllerProvider);
    final bundle = preferences.resolvedGithubMirrorBundle;
    if (bundle.selectedId == mirror.id) return;
    await ref
        .read(appPreferencesControllerProvider.notifier)
        .setGithubMirrorBundle(bundle.copyWith(selectedId: mirror.id));
    if (!mounted) return;
    AppSnackBar.show(
      context,
      message: '已切换到 ${mirror.label}',
      tone: AppSnackBarTone.success,
      icon: Icons.check_rounded,
    );
  }

  Future<void> _remove(GithubMirror mirror) async {
    final preferences = ref.read(appPreferencesControllerProvider);
    final bundle = preferences.resolvedGithubMirrorBundle;
    final newList =
        bundle.mirrors.where((m) => m.id != mirror.id).toList(growable: false);
    final newSelected = bundle.selectedId == mirror.id
        ? GithubMirror.builtins.first.id
        : bundle.selectedId;
    await ref
        .read(appPreferencesControllerProvider.notifier)
        .setGithubMirrorBundle(GithubMirrorBundle(
          mirrors: newList,
          selectedId: newSelected,
        ));
    setState(() {
      _latencies.remove(mirror.id);
    });
  }

  Future<void> _addMirror() async {
    final result = await showDialog<_AddMirrorResult>(
      context: context,
      builder: (_) => const _AddMirrorDialog(),
    );
    if (result == null) return;
    final preferences = ref.read(appPreferencesControllerProvider);
    final bundle = preferences.resolvedGithubMirrorBundle;
    final id = result.prefix.replaceAll(RegExp(r'[^A-Za-z0-9.]'), '_');
    if (bundle.mirrors.any((m) => m.id == id)) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: '该镜像已存在',
        tone: AppSnackBarTone.error,
      );
      return;
    }
    final next = GithubMirror(
      id: id,
      label: result.label.isEmpty ? id : result.label,
      prefix: result.prefix,
    );
    await ref
        .read(appPreferencesControllerProvider.notifier)
        .setGithubMirrorBundle(bundle.copyWith(
          mirrors: [...bundle.mirrors, next],
        ));
  }

  Future<void> _testAll(List<GithubMirror> mirrors) async {
    setState(() {
      _testing = true;
      _latencies.clear();
    });
    final api = ref.read(gitHubReleaseApiProvider);
    // 并发测，限制 4 个一组以免开太多连接。
    final results = await Future.wait(
      mirrors.map((m) async {
        final ms = await api.probeMirror(m);
        return MapEntry(m.id, ms);
      }),
    );
    if (!mounted) return;
    setState(() {
      for (final entry in results) {
        _latencies[entry.key] = entry.value;
      }
      _testing = false;
    });
  }
}

class _MirrorTile extends StatelessWidget {
  const _MirrorTile({
    required this.mirror,
    required this.selected,
    required this.latency,
    required this.testing,
    required this.onTap,
    this.onDelete,
  });

  final GithubMirror mirror;
  final bool selected;
  final int? latency;
  final bool testing;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tested = !testing && latency != null
        ? Text(
            '${latency}ms',
            style: theme.textTheme.labelSmall?.copyWith(
              color: _latencyColor(latency!, colorScheme),
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          )
        : (testing
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: colorScheme.outline,
                ),
              )
            : Text(
                '未测速',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline,
                ),
              ));

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? colorScheme.primary : colorScheme.outline,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          mirror.label,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      tested,
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mirror.prefix.isEmpty ? '直连 github.com' : mirror.prefix,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                tooltip: '删除',
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _latencyColor(int ms, ColorScheme cs) {
    if (ms < 600) return const Color(0xFF1C8C6E);
    if (ms < 1500) return const Color(0xFFC07A30);
    return cs.error;
  }
}

class _AddMirrorResult {
  const _AddMirrorResult({required this.label, required this.prefix});
  final String label;
  final String prefix;
}

class _AddMirrorDialog extends StatefulWidget {
  const _AddMirrorDialog();

  @override
  State<_AddMirrorDialog> createState() => _AddMirrorDialogState();
}

class _AddMirrorDialogState extends State<_AddMirrorDialog> {
  final _labelController = TextEditingController();
  final _prefixController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _labelController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加镜像'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(
              labelText: '名称（可选）',
              hintText: '例如 my-proxy.com',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _prefixController,
            decoration: const InputDecoration(
              labelText: '前缀',
              hintText: 'https://example.com/',
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '下载链接 = 前缀 + 完整 GitHub URL，例如\n'
            'https://example.com/https://github.com/owner/repo/releases/...',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            var prefix = _prefixController.text.trim();
            if (prefix.isEmpty) {
              setState(() => _error = '前缀不能为空');
              return;
            }
            if (!prefix.startsWith('http://') &&
                !prefix.startsWith('https://')) {
              setState(() => _error = '前缀必须以 http(s):// 开头');
              return;
            }
            if (!prefix.endsWith('/')) {
              prefix = '$prefix/';
            }
            Navigator.of(context).pop(_AddMirrorResult(
              label: _labelController.text.trim(),
              prefix: prefix,
            ));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
