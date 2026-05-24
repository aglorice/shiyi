import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/widgets/app_snackbar.dart';
import '../controllers/user_logs_controller.dart';

/// 一颗 IP 胶囊：默认显示 IP；点击 → 异步查归属地，弹一个 tooltip-ish
/// 的小气泡显示结果；长按复制。
///
/// 服务端没回填 ipAddress（比如学校内网/VPN）时 chip 上只有 IP，
/// 点一下才会去 ip.cn 查一次。一旦查过会缓存到 ipLocationLookupProvider，
/// 同一 IP 再点不会重复请求。
class IpChip extends ConsumerStatefulWidget {
  const IpChip({super.key, required this.ip, this.fallbackLocation});

  final String ip;
  final String? fallbackLocation;

  @override
  ConsumerState<IpChip> createState() => _IpChipState();
}

class _IpChipState extends ConsumerState<IpChip> {
  final _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = (widget.fallbackLocation ?? '').trim();

    final colorScheme = theme.colorScheme;
    return Material(
      key: _key,
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _showLocation(context),
        onLongPress: () async {
          await Clipboard.setData(ClipboardData(text: widget.ip));
          if (!mounted) return;
          AppSnackBar.show(
            this.context,
            message: '已复制 ${widget.ip}',
            tone: AppSnackBarTone.success,
            icon: Icons.copy_rounded,
          );
        },
        child: Container(
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
                Icons.public_rounded,
                size: 13,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                widget.ip.isEmpty ? '-' : widget.ip,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (fallback.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  fallback,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLocation(BuildContext context) async {
    if (widget.ip.trim().isEmpty) return;
    final cached = ref.read(ipLocationLookupProvider(widget.ip));
    final fallback = widget.fallbackLocation;

    String? location;
    if (cached.value != null) {
      location = cached.value;
    } else {
      // 先弹一个 loading 提示。
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 800),
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text('正在查询 ${widget.ip} 归属地…'),
            ],
          ),
        ),
      );
      location = await ref.read(ipLocationLookupProvider(widget.ip).future);
    }

    if (!mounted) return;
    final shown = (location ?? fallback ?? '').trim();
    if (!context.mounted) return;
    AppSnackBar.show(
      context,
      message: shown.isEmpty ? '${widget.ip} 暂无归属地信息' : '${widget.ip} · $shown',
      tone: shown.isEmpty ? AppSnackBarTone.info : AppSnackBarTone.success,
      icon: Icons.public_rounded,
    );
  }
}
