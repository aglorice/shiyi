import 'package:flutter/material.dart';

/// 把学校 authserver 给的精简 UA（如 "windows_10 chrome13/131.0.0.0"）
/// 显示为带图标的胶囊：「Windows · Chrome 131」。
class UserAgentChip extends StatelessWidget {
  const UserAgentChip({super.key, required this.userAgent});

  final String userAgent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = _decode(userAgent);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            parts.icon,
            size: 13,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            parts.label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  _UaInfo _decode(String ua) {
    if (ua.trim().isEmpty) {
      return const _UaInfo('未知设备', Icons.devices_other_rounded);
    }
    final segs = ua.split(' ');
    final osRaw = segs.first.toLowerCase();
    String os;
    IconData icon;
    if (osRaw.startsWith('mac')) {
      os = 'macOS';
      icon = Icons.laptop_mac_rounded;
    } else if (osRaw.startsWith('windows')) {
      final parts = osRaw.replaceAll('_', ' ').split(' ');
      os = parts.length >= 2
          ? 'Windows ${parts.sublist(1).join(' ')}'
          : 'Windows';
      icon = Icons.desktop_windows_rounded;
    } else if (osRaw.startsWith('android')) {
      os = osRaw.replaceAll('_', ' ');
      os = '${os[0].toUpperCase()}${os.substring(1)}';
      icon = Icons.phone_android_rounded;
    } else if (osRaw.startsWith('iphone') ||
        osRaw.startsWith('ios') ||
        osRaw.startsWith('ipad')) {
      os = 'iOS';
      icon = Icons.phone_iphone_rounded;
    } else if (osRaw.startsWith('linux')) {
      os = 'Linux';
      icon = Icons.terminal_rounded;
    } else {
      os = osRaw;
      icon = Icons.devices_other_rounded;
    }

    String? browser;
    if (segs.length >= 2) {
      final br = segs.sublist(1).join(' ');
      // chrome13/131.0.0.0 → ['chrome', '131']
      final match = RegExp(r'([a-zA-Z]+)\d*/(\d+)').firstMatch(br);
      if (match != null) {
        final name = match.group(1) ?? '';
        final ver = match.group(2) ?? '';
        if (name.isNotEmpty) {
          browser = '${name[0].toUpperCase()}${name.substring(1)} $ver';
        }
      }
    }

    return _UaInfo(
      browser == null ? os : '$os · $browser',
      icon,
    );
  }
}

class _UaInfo {
  const _UaInfo(this.label, this.icon);
  final String label;
  final IconData icon;
}
