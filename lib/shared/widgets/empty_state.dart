import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings/app_preferences_controller.dart';
import 'pixel_pet.dart';

/// 空状态语气。每种语气只影响 accent 色和文案默认值，动画一致。
///
/// - [rest]：今天没事可做（如"没课"/"无预约"），主色调
/// - [empty]：找不到结果（搜索为空、列表无数据），tertiary
/// - [pending]：还没绑定 / 还没设置好，主色但提示 + 行动按钮
/// - [error]：加载失败兜底，error 色
enum EmptyStateMood { rest, empty, pending, error }

/// 全局统一的空状态组件，主角是用户当前选择的像素宠物。
///
/// 设计目标：
/// - 同一个组件覆盖课表/成绩/考试/电费/通知/体育馆所有空态，文案散落问题一次解决。
/// - 像素猫做主角，与 logo / onboarding / 首页 hero 保持品牌一致性。
/// - 自带柔和呼吸 + accent 光晕动画，比"灰图标 + 一行字"温度高一档。
/// - 支持 `compact` 紧凑模式（内嵌在卡片里，不占整页）和 `action` 行动按钮。
class EmptyState extends ConsumerStatefulWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.mood = EmptyStateMood.rest,
    this.action,
    this.padding,
    this.compact = false,
    this.pet,
  });

  /// 主标题，如"今天没课，好好休息"。
  final String title;

  /// 副标题，可选。"凑近看星星，远看像猫"那种轻描淡写的补充。
  final String? subtitle;

  /// 语气：决定 accent 色与默认文案。
  final EmptyStateMood mood;

  /// 行动按钮：通常用 `FilledButton.tonal` 或 `OutlinedButton`。
  final Widget? action;

  /// 自定义外边距。null 时按 [compact] 自动选择。
  final EdgeInsetsGeometry? padding;

  /// 紧凑模式：嵌在卡片里时用，缩小猫体型与字号。
  final bool compact;

  /// 强制指定宠物类型，否则跟随用户偏好（[appPreferencesControllerProvider]）。
  final PixelPetType? pet;

  @override
  ConsumerState<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends ConsumerState<EmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 4s 一个循环，呼吸感优先。太快就显得焦躁。
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _accentFor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (widget.mood) {
      case EmptyStateMood.rest:
      case EmptyStateMood.pending:
        return cs.primary;
      case EmptyStateMood.empty:
        return cs.tertiary;
      case EmptyStateMood.error:
        return cs.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentFor(context);
    final pet =
        widget.pet ??
        PixelPetType.fromName(
          ref.watch(
            appPreferencesControllerProvider.select((p) => p.pixelPet),
          ),
        );
    final padding =
        widget.padding ??
        EdgeInsets.symmetric(
          horizontal: 24,
          vertical: widget.compact ? 18 : 32,
        );
    final petSize = widget.compact ? 56.0 : 84.0;
    final haloSize = petSize + 36;

    // 用 SizedBox(width: double.infinity) + Padding 让组件占满父级可用宽度，
    // 否则 Column 默认按"最宽子节点"收缩，外层若是 start-aligned 就会出现整块
    // 靠左的视觉假象（这正是 venue_detail 评论区出现的问题）。
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;
                final bob = math.sin(t * math.pi * 2);
                final pulse = (math.sin(t * math.pi * 2 - 0.5) + 1) / 2;
                return SizedBox(
                  width: haloSize,
                  height: haloSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: haloSize * (0.78 + pulse * 0.18),
                        height: haloSize * (0.78 + pulse * 0.18),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              accent.withValues(alpha: 0.22),
                              accent.withValues(alpha: 0),
                            ],
                            stops: const [0.0, 1.0],
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(0, bob * 2.2),
                        child: Transform.scale(
                          scale: petSize / 72,
                          child: PixelPet(type: pet),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            SizedBox(height: widget.compact ? 12 : 16),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style:
                  (widget.compact
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.titleMedium)
                      ?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                        height: 1.3,
                        color: theme.colorScheme.onSurface,
                      ),
            ),
            if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                widget.subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (widget.action != null) ...[
              SizedBox(height: widget.compact ? 14 : 20),
              widget.action!,
            ],
          ],
        ),
      ),
    );
  }
}
