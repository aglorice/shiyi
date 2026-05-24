import 'package:flutter/material.dart';

/// 日志条目里的"小灰字一行"：图标 + 主文字 + 可选的小灰字次级文字。
///
/// 替代之前到处用的胶囊 chip，让信息更紧凑、更接近系统设置 / 微信详情那种
/// "图标 + 文字 + 副标题"的纯文字行。
class LogMetaRow extends StatelessWidget {
  const LogMetaRow({
    super.key,
    required this.icon,
    required this.text,
    this.secondary,
    this.dense = true,
  });

  final IconData icon;
  final String text;
  final String? secondary;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 2 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (secondary != null && secondary!.isNotEmpty) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                secondary!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
