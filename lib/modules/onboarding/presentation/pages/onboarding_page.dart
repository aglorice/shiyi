import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/settings/app_preferences_controller.dart';
import '../../../../app/theme/design_tokens.dart';

/// 首次启动引导页。
///
/// 4 张 slide 介绍：欢迎、能做什么、如何登录、隐私承诺。
/// 完成后写入 `preferences.onboardingCompleted=true`，router 不再把用户
/// 引到这里。整体风格与 LoginPage 一致：暖白底、单 logo + 大字标题、
/// 圆角主按钮。
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  static const _slides = <_OnboardingSlide>[
    _OnboardingSlide(
      icon: Icons.menu_book_rounded,
      title: '欢迎来到拾邑',
      subtitle: '五邑大学非官方校园助手，把零散系统整合到一处',
      bullets: [
        '课表 / 成绩 / 考试，从教务系统一次取齐',
        '宿舍电费 / 体育馆预约，无需切换浏览器',
        '校园通知 / 要闻，自动同步到本地',
      ],
    ),
    _OnboardingSlide(
      icon: Icons.flash_on_rounded,
      title: '一次登录，处处可用',
      subtitle: '基于学校统一身份认证（SSO），凭证持有者只有你',
      bullets: [
        '支持学号密码、手机号验证码两种登录',
        '需要滑块时会自动弹出，不需要切到浏览器',
        '会话过期会主动重新登录，不打断你的浏览',
      ],
    ),
    _OnboardingSlide(
      icon: Icons.shield_outlined,
      title: '凭证只属于你',
      subtitle: '应用没有任何后端，所有数据都在你手机里',
      bullets: [
        '学号 / 密码加密存储在本机，不会上传',
        '请求日志只保留在内存里，可在设置中查看',
        '完全开源，可在 GitHub 上验证我们说的一切',
      ],
    ),
    _OnboardingSlide(
      icon: Icons.handshake_rounded,
      title: '只用于学习交流',
      subtitle: '使用前请知悉以下两点',
      bullets: [
        '本应用与五邑大学官方无关，仅做技术学习',
        '若学校认为不合适，请联系 GitHub Issue 下架',
      ],
    ),
  ];

  bool get _isLast => _index == _slides.length - 1;

  Future<void> _finish() async {
    await ref
        .read(appPreferencesControllerProvider.notifier)
        .markOnboardingCompleted();
    if (!mounted) return;
    // router 的 redirect 会把已完成 onboarding 的用户引到登录页或主页。
    context.go('/login');
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 顶部跳过按钮，避免新用户被锁在引导里。
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 12),
                child: TextButton(
                  onPressed: _finish,
                  child: Text(
                    '跳过',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, index) => _SlideView(slide: _slides[index]),
              ),
            ),
            const SizedBox(height: 12),
            _Dots(count: _slides.length, current: _index),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: 0.2,
                    ),
                  ),
                  child: Text(_isLast ? '开始使用' : '下一步'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bullets,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> bullets;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(flex: 2),
          // 图标也走"圆角矩形 + 主色淡背景"的 squircle 风，呼应应用图标。
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: tone.primaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(72 * 0.225),
            ),
            child: Icon(
              slide.icon,
              size: 32,
              color: tone.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            slide.title,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            slide.subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: tone.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          ...slide.bullets.map(
            (bullet) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: tone.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      bullet,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: tone.onSurface,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final selected = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: selected ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
