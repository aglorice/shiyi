import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../shared/widgets/app_snackbar.dart';

class SettingsLogsPage extends ConsumerStatefulWidget {
  const SettingsLogsPage({super.key});

  @override
  ConsumerState<SettingsLogsPage> createState() => _SettingsLogsPageState();
}

class _SettingsLogsPageState extends ConsumerState<SettingsLogsPage> {
  AppLogLevel? _selectedLevel;
  StreamSubscription<AppLogEntry>? _subscription;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _subscription = appLogBuffer.onAppend.listen((_) {
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
    final allEntries = appLogBuffer.entries;
    final entries = allEntries.where((entry) {
      if (_selectedLevel != null && entry.level != _selectedLevel) {
        return false;
      }
      if (_query.isEmpty) return true;
      final lower = _query.toLowerCase();
      return entry.message.toLowerCase().contains(lower) ||
          (entry.title?.toLowerCase().contains(lower) ?? false) ||
          (entry.body?.toLowerCase().contains(lower) ?? false);
    }).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Scaffold(
      appBar: AppBar(
        title: const Text('请求日志'),
        actions: [
          IconButton(
            tooltip: '复制全部',
            onPressed:
                entries.isEmpty ? null : () => _copyAll(context, entries),
            icon: const Icon(Icons.copy_all_rounded),
          ),
          IconButton(
            tooltip: '分享',
            onPressed:
                entries.isEmpty ? null : () => _share(context, entries),
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            tooltip: '清空',
            onPressed: allEntries.isEmpty
                ? null
                : () {
                    appLogBuffer.clear();
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
                    hintText: '搜索关键词',
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
                      _filterChip(label: '全部', level: null),
                      for (final level in AppLogLevel.values)
                        _filterChip(label: level.label, level: level),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${entries.length} / ${allEntries.length} 条',
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
                    allEntries.isEmpty
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
                      .withValues(alpha: 0.55),
                ),
                itemBuilder: (context, index) =>
                    _LogRow(entry: entries[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip({required String label, required AppLogLevel? level}) {
    final selected = _selectedLevel == level;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _selectedLevel = level),
      ),
    );
  }

  Future<void> _copyAll(
    BuildContext context,
    List<AppLogEntry> entries,
  ) async {
    final text = entries.map(_formatPlainText).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      AppSnackBar.show(
        context,
        message: '已复制 ${entries.length} 条日志',
        tone: AppSnackBarTone.success,
      );
    }
  }

  Future<void> _share(BuildContext context, List<AppLogEntry> entries) async {
    final text = entries.map(_formatPlainText).join('\n');
    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'uni_yi 日志（${entries.length} 条）'),
    );
  }

  String _formatPlainText(AppLogEntry entry) {
    final ts = DateFormat('HH:mm:ss').format(entry.timestamp.toLocal());
    final buffer = StringBuffer()
      ..writeln('[$ts][${entry.level.label}] ${entry.message}');
    if (entry.body != null && entry.body!.isNotEmpty) {
      buffer
        ..writeln('--- ${entry.title ?? entry.message} BEGIN ---')
        ..writeln(entry.body)
        ..writeln('--- END ---');
    }
    if (entry.cause != null) {
      buffer.writeln('cause: ${entry.cause}');
    }
    return buffer.toString();
  }
}

class _LogRow extends StatefulWidget {
  const _LogRow({required this.entry});

  final AppLogEntry entry;

  @override
  State<_LogRow> createState() => _LogRowState();
}

class _LogRowState extends State<_LogRow> {
  bool _expanded = false;

  Color _toneFor(AppLogLevel level, ThemeData theme) {
    return switch (level) {
      AppLogLevel.debug => theme.colorScheme.onSurfaceVariant,
      AppLogLevel.info => theme.colorScheme.primary,
      AppLogLevel.warn => const Color(0xFFE8A838),
      AppLogLevel.error => theme.colorScheme.error,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = widget.entry;
    final tone = _toneFor(entry.level, theme);
    final timestamp =
        DateFormat('HH:mm:ss.SSS').format(entry.timestamp.toLocal());
    final hasBody = entry.body != null && entry.body!.isNotEmpty;

    return InkWell(
      onTap: hasBody ? () => setState(() => _expanded = !_expanded) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.pageH,
          vertical: 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: tone,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  entry.level.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  timestamp,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                if (hasBody)
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              entry.message,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            if (entry.cause != null) ...[
              const SizedBox(height: 4),
              Text(
                'cause: ${entry.cause}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (hasBody && _expanded) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm + 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Stack(
                  children: [
                    SelectableText(
                      entry.body!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                    ),
                    Positioned(
                      top: -4,
                      right: -4,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _copy(context, entry),
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        tooltip: '复制',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context, AppLogEntry entry) async {
    final text = entry.body == null || entry.body!.isEmpty
        ? entry.message
        : '${entry.title ?? entry.message}\n${entry.body}';
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      AppSnackBar.show(
        context,
        message: '已复制',
        tone: AppSnackBarTone.success,
      );
    }
  }
}
