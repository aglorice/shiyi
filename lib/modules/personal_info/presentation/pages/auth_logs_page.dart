import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../shared/widgets/app_snackbar.dart';
import '../../domain/entities/user_log_entry.dart';
import '../controllers/user_logs_controller.dart';
import '../widgets/log_list_view.dart';
import '../widgets/log_meta_row.dart';

/// 登录记录详情页：成功/失败 + 时间 + 设备 + IP + 错误原因。
class AuthLogsPage extends ConsumerWidget {
  const AuthLogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authLogsControllerProvider);
    final notifier = ref.read(authLogsControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('登录记录')),
      body: LogListView(
        state: state,
        onRefresh: notifier.refresh,
        onLoadMore: notifier.loadMore,
        emptyHint: '暂无登录记录',
        itemBuilder: (context, entry) => _AuthLogTile(entry: entry),
      ),
    );
  }
}

class _AuthLogTile extends StatelessWidget {
  const _AuthLogTile({required this.entry});

  final UserLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = entry.success
        ? const Color(0xFF1C8C6E)
        : theme.colorScheme.error;

    return InkWell(
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: entry.ip));
        if (!context.mounted) return;
        AppSnackBar.show(
          context,
          message: '已复制 ${entry.ip}',
          tone: AppSnackBarTone.success,
          icon: Icons.copy_rounded,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              entry.success
                  ? Icons.check_circle_rounded
                  : Icons.cancel_rounded,
              color: tone,
              size: 22,
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
                          entry.success ? '登录成功' : '登录失败',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        _shortTime(entry.timeLabel),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  if (entry.errorMessage != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  if (entry.userAgent != null && entry.userAgent!.isNotEmpty)
                    LogMetaRow(
                      icon: _osIcon(entry.userAgent!),
                      text: _formatUa(entry.userAgent!),
                    ),
                  LogMetaRow(
                    icon: Icons.public_rounded,
                    text: entry.ip,
                    secondary: entry.location,
                  ),
                  if (entry.logoutTimeLabel != null &&
                      entry.logoutTimeLabel!.isNotEmpty)
                    LogMetaRow(
                      icon: Icons.logout_rounded,
                      text: _shortTime(entry.logoutTimeLabel!),
                      secondary: '已退出',
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _shortTime(String full) {
  // "2026-05-24 09:39:21" → "05-24 09:39"，相同年内更紧凑。
  if (full.length < 16) return full;
  return full.substring(5, 16);
}

IconData _osIcon(String ua) {
  final s = ua.toLowerCase();
  if (s.startsWith('mac')) return Icons.laptop_mac_rounded;
  if (s.startsWith('windows')) return Icons.desktop_windows_rounded;
  if (s.startsWith('android')) return Icons.phone_android_rounded;
  if (s.startsWith('iphone') || s.startsWith('ios') || s.startsWith('ipad')) {
    return Icons.phone_iphone_rounded;
  }
  if (s.startsWith('linux')) return Icons.terminal_rounded;
  return Icons.devices_other_rounded;
}

String _formatUa(String ua) {
  final segs = ua.split(' ');
  if (segs.isEmpty) return ua;
  final osRaw = segs.first.toLowerCase();
  String os;
  if (osRaw.startsWith('mac')) {
    os = 'macOS';
  } else if (osRaw.startsWith('windows')) {
    final parts = osRaw.replaceAll('_', ' ').split(' ');
    os = parts.length >= 2
        ? 'Windows ${parts.sublist(1).join(' ')}'
        : 'Windows';
  } else if (osRaw.startsWith('android')) {
    final cap = osRaw.replaceAll('_', ' ');
    os = '${cap[0].toUpperCase()}${cap.substring(1)}';
  } else if (osRaw.startsWith('iphone') ||
      osRaw.startsWith('ios') ||
      osRaw.startsWith('ipad')) {
    os = 'iOS';
  } else if (osRaw.startsWith('linux')) {
    os = 'Linux';
  } else {
    os = osRaw;
  }
  if (segs.length < 2) return os;
  final br = segs.sublist(1).join(' ');
  final m = RegExp(r'([a-zA-Z]+)\d*/(\d+)').firstMatch(br);
  if (m != null) {
    final name = m.group(1) ?? '';
    final ver = m.group(2) ?? '';
    if (name.isNotEmpty) {
      return '$os · ${name[0].toUpperCase()}${name.substring(1)} $ver';
    }
  }
  return '$os · $br';
}
