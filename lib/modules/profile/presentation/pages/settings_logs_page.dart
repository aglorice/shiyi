import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../core/logging/api_log_buffer.dart';
import '../../../../shared/widgets/app_snackbar.dart';

/// 「请求日志」入口页：每条接口往返显示成一行
/// `[POST 200 320ms] /modules/.../checkCanApply.do`
/// 点击后跳到详情页，可看完整 URL / 请求体 / 响应体。
class SettingsLogsPage extends ConsumerStatefulWidget {
  const SettingsLogsPage({super.key});

  @override
  ConsumerState<SettingsLogsPage> createState() => _SettingsLogsPageState();
}

class _SettingsLogsPageState extends ConsumerState<SettingsLogsPage> {
  StreamSubscription<ApiLogEntry>? _subscription;
  String _query = '';
  _StatusFilter _filter = _StatusFilter.all;

  @override
  void initState() {
    super.initState();
    _subscription = apiLogBuffer.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = apiLogBuffer.entries;
    final entries = all.where(_match).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    return Scaffold(
      appBar: AppBar(
        title: const Text('请求日志'),
        actions: [
          IconButton(
            tooltip: '分享',
            onPressed: entries.isEmpty ? null : () => _share(entries),
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            tooltip: '清空',
            onPressed: all.isEmpty
                ? null
                : () {
                    apiLogBuffer.clear();
                    setState(() {});
                  },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageH,
              AppSpacing.sm,
              AppSpacing.pageH,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: '搜索 URL 或参数',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                  onChanged: (value) =>
                      setState(() => _query = value.trim()),
                ),
                const SizedBox(height: AppSpacing.sm),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final filter in _StatusFilter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(filter.label),
                            selected: _filter == filter,
                            onSelected: (_) =>
                                setState(() => _filter = filter),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${entries.length} / ${all.length} 条',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (entries.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Text(
                    all.isEmpty
                        ? '当前还没有日志，先去预约或浏览课表试试。'
                        : '没有匹配当前筛选的日志。',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(
                  top: 4,
                  bottom: AppSpacing.pageBottomGap,
                ),
                itemCount: entries.length,
                separatorBuilder: (_, _) => Divider(
                  height: 0.6,
                  thickness: 0.6,
                  indent: AppSpacing.pageH,
                  endIndent: AppSpacing.pageH,
                  color: theme.colorScheme.outlineVariant
                      .withValues(alpha: 0.45),
                ),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return _ApiLogTile(
                    entry: entry,
                    onTap: () => _openDetail(entry),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  bool _match(ApiLogEntry entry) {
    switch (_filter) {
      case _StatusFilter.all:
        break;
      case _StatusFilter.inFlight:
        if (!entry.inFlight) return false;
      case _StatusFilter.success:
        if (entry.inFlight || !entry.isSuccess) return false;
      case _StatusFilter.failed:
        if (entry.inFlight || entry.isSuccess) return false;
    }
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return entry.url.toLowerCase().contains(q) ||
        (entry.label?.toLowerCase().contains(q) ?? false) ||
        _stringify(entry.requestBody).toLowerCase().contains(q) ||
        _stringify(entry.responseBody).toLowerCase().contains(q);
  }

  void _openDetail(ApiLogEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ApiLogDetailPage(entryId: entry.id),
      ),
    );
  }

  Future<void> _share(List<ApiLogEntry> entries) async {
    final text = entries.map(_formatPlainText).join('\n');
    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'uni_yi 请求日志（${entries.length} 条）'),
    );
  }

  static String _stringify(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    try {
      return const JsonEncoder().convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  String _formatPlainText(ApiLogEntry entry) {
    final ts = DateFormat('HH:mm:ss').format(entry.startedAt.toLocal());
    final status = entry.statusCode == null ? '-' : '${entry.statusCode}';
    final dur = entry.duration?.inMilliseconds.toString() ?? '-';
    return '[$ts][${entry.method} $status ${dur}ms] ${entry.url}';
  }
}

enum _StatusFilter { all, inFlight, success, failed }

extension on _StatusFilter {
  String get label => switch (this) {
        _StatusFilter.all => '全部',
        _StatusFilter.inFlight => '进行中',
        _StatusFilter.success => '成功',
        _StatusFilter.failed => '失败',
      };
}

class _ApiLogTile extends StatelessWidget {
  const _ApiLogTile({required this.entry, required this.onTap});

  final ApiLogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _statusTone(entry, theme);
    final time = DateFormat('HH:mm:ss').format(entry.startedAt.toLocal());
    final statusLabel = entry.inFlight
        ? '...'
        : entry.statusCode?.toString() ?? '—';
    final durationLabel = entry.duration == null
        ? '—'
        : '${entry.duration!.inMilliseconds}ms';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageH,
          vertical: 12,
        ),
        child: Row(
          children: [
            // 状态色点
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: tone,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        entry.method,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        statusLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        durationLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        time,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _shortPath(entry.url),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  if (entry.label != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (entry.failureMessage != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.failureMessage!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  String _shortPath(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    return uri.path.isEmpty ? url : uri.path;
  }

  Color _statusTone(ApiLogEntry entry, ThemeData theme) {
    if (entry.inFlight) return theme.colorScheme.onSurfaceVariant;
    if (entry.failureMessage != null) return theme.colorScheme.error;
    if (entry.isSuccess) return const Color(0xFF2F8C72);
    return theme.colorScheme.error;
  }
}

/// 详情页：完整 URL / 请求体 / 响应体。
class _ApiLogDetailPage extends StatefulWidget {
  const _ApiLogDetailPage({required this.entryId});

  final int entryId;

  @override
  State<_ApiLogDetailPage> createState() => _ApiLogDetailPageState();
}

class _ApiLogDetailPageState extends State<_ApiLogDetailPage> {
  StreamSubscription<ApiLogEntry>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = apiLogBuffer.onChanged.listen((entry) {
      if (entry.id == widget.entryId && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  ApiLogEntry? get _entry =>
      apiLogBuffer.entries.where((e) => e.id == widget.entryId).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = _entry;
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('日志详情')),
        body: const Center(child: Text('日志已被清理')),
      );
    }

    final time = DateFormat('yyyy-MM-dd HH:mm:ss')
        .format(entry.startedAt.toLocal());

    return Scaffold(
      appBar: AppBar(
        title: const Text('日志详情'),
        actions: [
          IconButton(
            tooltip: '分享',
            onPressed: () => _shareEntry(entry),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageH,
          vertical: AppSpacing.md,
        ),
        children: [
          _StatusHero(entry: entry, time: time),
          const SizedBox(height: AppSpacing.lg),
          _DetailSection(
            title: '请求 URL',
            copyText: entry.url,
            child: SelectableText(
              entry.url,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
          if (entry.requestHeaders != null &&
              entry.requestHeaders!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _DetailSection(
              title: '请求头',
              copyText: _stringify(entry.requestHeaders),
              child: _KeyValueTable(map: entry.requestHeaders!),
            ),
          ],
          if (entry.requestBody != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _BodySection(
              title: '请求体',
              body: entry.requestBody,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _BodySection(
            title: '响应体',
            body: entry.responseBody,
            placeholder: entry.inFlight ? '请求进行中…' : '无响应内容',
          ),
          if (entry.failureMessage != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _DetailSection(
              title: '失败信息',
              copyText: entry.failureMessage!,
              child: Text(
                entry.failureMessage!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _shareEntry(ApiLogEntry entry) async {
    final buffer = StringBuffer()
      ..writeln('${entry.method} ${entry.url}')
      ..writeln('time: ${entry.startedAt.toIso8601String()}')
      ..writeln('status: ${entry.statusCode ?? "-"} '
          '(${entry.duration?.inMilliseconds ?? "-"} ms)');
    if (entry.requestBody != null) {
      buffer
        ..writeln('--- request body ---')
        ..writeln(_stringify(entry.requestBody));
    }
    if (entry.responseBody != null) {
      buffer
        ..writeln('--- response body ---')
        ..writeln(_stringify(entry.responseBody));
    }
    if (entry.failureMessage != null) {
      buffer.writeln('failure: ${entry.failureMessage}');
    }
    await SharePlus.instance.share(
      ShareParams(text: buffer.toString(), subject: '请求日志'),
    );
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.entry, required this.time});

  final ApiLogEntry entry;
  final String time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = entry.inFlight
        ? theme.colorScheme.onSurfaceVariant
        : entry.isSuccess
            ? const Color(0xFF2F8C72)
            : theme.colorScheme.error;
    final statusLabel = entry.inFlight
        ? '进行中'
        : entry.statusCode?.toString() ?? '—';
    final durationLabel = entry.duration == null
        ? '—'
        : '${entry.duration!.inMilliseconds} ms';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                entry.method,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              statusLabel,
              style: theme.textTheme.titleLarge?.copyWith(
                color: tone,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              durationLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          entry.label ?? Uri.tryParse(entry.url)?.path ?? entry.url,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          time,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.child,
    this.copyText,
  });

  final String title;
  final Widget child;
  final String? copyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            if (copyText != null && copyText!.isNotEmpty)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '复制',
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: copyText!),
                  );
                  if (context.mounted) {
                    AppSnackBar.show(
                      context,
                      message: '已复制',
                      tone: AppSnackBarTone.success,
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.sm + 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _BodySection extends StatelessWidget {
  const _BodySection({
    required this.title,
    required this.body,
    this.placeholder = '无',
  });

  final String title;
  final Object? body;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = body;
    if (value == null) {
      return _DetailSection(
        title: title,
        copyText: null,
        child: Text(
          placeholder,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    if (value is Map<String, dynamic> &&
        value.length <= 30 &&
        !value.values.any((v) => v is Map || v is List)) {
      // 浅层 form / json：表格更直观
      return _DetailSection(
        title: title,
        copyText: _stringify(value),
        child: _KeyValueTable(
          map: value.map((k, v) => MapEntry(k, '${v ?? ''}')),
        ),
      );
    }
    final pretty = _stringify(value, indent: true);
    return _DetailSection(
      title: title,
      copyText: pretty,
      child: SelectableText(
        pretty,
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          height: 1.4,
        ),
      ),
    );
  }
}

class _KeyValueTable extends StatelessWidget {
  const _KeyValueTable({required this.map});

  final Map<String, String> map;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = map.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  entries[i].key,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  entries[i].value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          if (i < entries.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }
}

String _stringify(Object? value, {bool indent = false}) {
  if (value == null) return '';
  if (value is String) return value;
  try {
    final encoder =
        indent ? const JsonEncoder.withIndent('  ') : const JsonEncoder();
    return encoder.convert(value);
  } catch (_) {
    return value.toString();
  }
}
