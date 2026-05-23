import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../integrations/school_portal/sso/slider_captcha.dart';
import '../controllers/sms_login_controller.dart';

/// 滑块验证 BottomSheet。
///
/// 行为对齐学校 web 端 longbow.slidercaptcha.js：
/// - 大图固定渲染 280×155，按 `BoxFit.cover` 填满；
/// - 小拼图渲染宽度 = `tagWidth * (280 / bigImageNaturalWidth)`，
///   完全复刻 web 端的缩放公式（保持视觉与官网一致）；
/// - 拖动按钮位移驱动小拼图同步移动；mousedown / mousemove / mouseup
///   全程采样并组装 tracks 上传。
/// - 校验通过：sheet 自动收起；失败：换图重试。
class SliderCaptchaSheet extends ConsumerStatefulWidget {
  const SliderCaptchaSheet({super.key});

  static const double canvasWidth = 280;
  static const double canvasHeight = 155;

  /// 滑块条与按钮高度（与 web 一致 ≈ 36，更紧凑视觉好看）。
  static const double sliderHeight = 36;

  /// 拖动按钮宽度，这里和 moveLength 计算保持一致。
  static const double sliderButtonWidth = 36;

  /// 弹出 sheet 并等待"是否成功通过"。
  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const SliderCaptchaSheet(),
    );
  }

  @override
  ConsumerState<SliderCaptchaSheet> createState() => _SliderCaptchaSheetState();
}

class _SliderCaptchaSheetState extends ConsumerState<SliderCaptchaSheet> {
  /// 当前按钮（也即拼图）的位移：起点 0，最右等于 `canvasWidth - sliderButtonWidth`。
  double _offset = 0;

  bool _dragging = false;

  /// 一次拖动开始时的 wall-clock 起点。
  DateTime? _dragStart;

  /// 上一个采样点，用于做距离/时间过滤。
  _SamplePoint? _lastSample;

  /// 已采样的轨迹。
  final List<SliderTrackPoint> _tracks = [];

  /// 当前是否正在请求服务端校验。
  bool _verifying = false;

  /// 上一次校验失败的提示。
  String? _hintMessage;

  /// 拖偏 / 失败 / 成功的视觉态：null=默认，'success'=绿，'fail'=红。
  String? _flashState;

  /// 用 `tagWidth * (280 / bigImageNaturalWidth)` 计算出来的真实渲染宽度。
  /// null 表示还没解到大图原尺寸，渲染时按 fitHeight 兜底。
  double? _puzzleRenderWidth;

  /// 当前 challenge 的解码缓存，用来对比 isSameChallenge。
  SliderCaptchaChallenge? _decodedChallenge;

  @override
  void initState() {
    super.initState();
    // 第一次构建后异步算一次。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensurePuzzleSizeFor(
          ref.read(smsLoginControllerProvider).challenge);
    });
  }

  /// 用 [ui.instantiateImageCodec] 拿大图 naturalWidth，再算小拼图渲染宽度。
  Future<void> _ensurePuzzleSizeFor(SliderCaptchaChallenge? challenge) async {
    if (challenge == null) return;
    if (identical(_decodedChallenge, challenge)) return;
    _decodedChallenge = challenge;
    try {
      final codec = await ui.instantiateImageCodec(challenge.bigImageBytes);
      final frame = await codec.getNextFrame();
      final natural = frame.image.width;
      frame.image.dispose();
      if (!mounted) return;
      if (natural <= 0 || challenge.tagWidth <= 0) return;
      setState(() {
        _puzzleRenderWidth =
            challenge.tagWidth * (SliderCaptchaSheet.canvasWidth / natural);
      });
    } catch (_) {
      // 解码失败就保留 null，由兜底的 fitHeight 渲染。
    }
  }

  /// 用于驱动 bar 文案。
  String get _barText {
    if (_verifying) return '校验中...';
    if (_flashState == 'success') return '验证通过';
    if (_flashState == 'fail') return _hintMessage ?? '再试一次';
    return '向右滑动填充拼图';
  }

  @override
  Widget build(BuildContext context) {
    final challenge = ref.watch(
      smsLoginControllerProvider.select((s) => s.challenge),
    );
    final theme = Theme.of(context);

    // challenge 换张图时，重新算渲染宽度。
    if (challenge != null && !identical(_decodedChallenge, challenge)) {
      // ignore: discarded_futures
      _ensurePuzzleSizeFor(challenge);
    }

    if (challenge == null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: SizedBox(
            height: 240,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  '正在加载验证码...',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final canvasWidth = SliderCaptchaSheet.canvasWidth;
    final canvasHeight = SliderCaptchaSheet.canvasHeight;
    final sliderH = SliderCaptchaSheet.sliderHeight;
    final btnW = SliderCaptchaSheet.sliderButtonWidth;
    final maxOffset = canvasWidth - btnW;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '请完成安全验证',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '换一张',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _verifying
                      ? null
                      : () async {
                          await ref
                              .read(smsLoginControllerProvider.notifier)
                              .refreshChallenge();
                          _resetVisualState();
                        },
                ),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _verifying
                      ? null
                      : () {
                          ref
                              .read(smsLoginControllerProvider.notifier)
                              .cancelSlider();
                          Navigator.of(context).maybePop(false);
                        },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // 大图 + 缺口 + 拖动后跟随的小拼图
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: canvasWidth,
                height: canvasHeight,
                child: Stack(
                  children: [
                    Image.memory(
                      challenge.bigImageBytes,
                      width: canvasWidth,
                      height: canvasHeight,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                    Positioned(
                      left: _offset,
                      top: 0,
                      child: SizedBox(
                        width: _puzzleRenderWidth,
                        height: canvasHeight,
                        child: Image.memory(
                          challenge.smallImageBytes,
                          width: _puzzleRenderWidth,
                          height: canvasHeight,
                          // 当还没量出 naturalWidth 时按高度兜底。
                          fit: _puzzleRenderWidth == null
                              ? BoxFit.fitHeight
                              : BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // 滑块条
            SizedBox(
              width: canvasWidth,
              height: sliderH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _barText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _flashState == 'fail'
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // 已经走过的区域
                  Container(
                    width: _offset + btnW,
                    decoration: BoxDecoration(
                      color: _flashState == 'success'
                          ? const Color(0xFFD2F4EF)
                          : _flashState == 'fail'
                              ? const Color(0xFFFCE1E1)
                              : const Color(0xFFD1E9FE),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  Positioned(
                    left: _offset,
                    top: 0,
                    child: GestureDetector(
                      onHorizontalDragStart: _onDragStart,
                      onHorizontalDragUpdate: (d) =>
                          _onDragUpdate(d, maxOffset),
                      onHorizontalDragEnd: (_) => _onDragEnd(),
                      child: Container(
                        width: btnW,
                        height: sliderH,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _flashState == 'success'
                              ? const Color(0xFF52CCBA)
                              : _flashState == 'fail'
                                  ? const Color(0xFFF57A7A)
                                  : Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                          border: Border.all(
                            color: _dragging
                                ? const Color(0xFF1991FA)
                                : const Color(0xFFE6E8EB),
                          ),
                        ),
                        child: Icon(
                          _flashState == 'success'
                              ? Icons.check_rounded
                              : _flashState == 'fail'
                                  ? Icons.close_rounded
                                  : Icons.arrow_forward_rounded,
                          color: _flashState == null
                              ? const Color(0xFF8A8E91)
                              : Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '拖动小拼图到缺口位置即可',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _resetVisualState() {
    setState(() {
      _offset = 0;
      _flashState = null;
      _hintMessage = null;
      _tracks.clear();
      _lastSample = null;
      _dragStart = null;
      _dragging = false;
    });
  }

  void _onDragStart(DragStartDetails details) {
    if (_verifying) return;
    setState(() {
      _dragging = true;
      _flashState = null;
      _dragStart = DateTime.now();
      _tracks
        ..clear()
        ..add(const SliderTrackPoint(a: 0, b: 0, c: 0));
      _lastSample = _SamplePoint(a: 0, b: 0, t: _dragStart!);
    });
  }

  void _onDragUpdate(DragUpdateDetails details, double maxOffset) {
    if (_verifying || !_dragging) return;
    final newOffset = (_offset + details.delta.dx).clamp(0.0, maxOffset);
    final now = DateTime.now();
    final start = _dragStart;
    if (start == null) return;

    final a = newOffset.round();
    final b = _syntheticY(a);
    final last = _lastSample;
    final tSinceLast = last == null
        ? 0
        : now.difference(last.t).inMilliseconds;

    setState(() => _offset = newOffset);

    // 节流：与 web 端一致 —— 时间差 ≥ 20ms 且距离 ≥ 2px 才采样。
    if (last != null) {
      final dx = a - last.a;
      final dy = b - last.b;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (tSinceLast < 20) return;
      if (dist < 2) return;
    }

    _tracks.add(SliderTrackPoint(a: a, b: b, c: tSinceLast));
    _lastSample = _SamplePoint(a: a, b: b, t: now);
  }

  Future<void> _onDragEnd() async {
    if (!_dragging || _verifying) return;
    final start = _dragStart;
    if (start == null) {
      setState(() => _dragging = false);
      return;
    }
    final now = DateTime.now();
    final last = _lastSample;
    final endA = _offset.round();
    final endB = _syntheticY(endA);
    final tSince = last == null ? 0 : now.difference(last.t).inMilliseconds;
    _tracks.add(SliderTrackPoint(a: endA, b: endB, c: tSince));

    setState(() {
      _dragging = false;
      _verifying = true;
    });

    final payload = SliderTrackPayload(
      canvasLength: SliderCaptchaSheet.canvasWidth.toInt(),
      moveLength: endA,
      tracks: List<SliderTrackPoint>.unmodifiable(_tracks),
    );

    final passed = await ref
        .read(smsLoginControllerProvider.notifier)
        .submitSlider(payload: payload);

    if (!mounted) return;

    if (passed) {
      setState(() {
        _flashState = 'success';
        _verifying = false;
      });
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.of(context).maybePop(true);
    } else {
      setState(() {
        _flashState = 'fail';
        _hintMessage = ref.read(smsLoginControllerProvider).errorMessage;
        _verifying = false;
      });
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) {
        _resetVisualState();
      }
    }
  }

  /// 拖动过程中给 b（Y 偏移）加一点点正弦抖动，模拟人手。
  /// 完全为 0 也能通过（offset=5），但少量抖动让风控不那么敏感。
  int _syntheticY(int a) {
    final phase = a / 12.0;
    return (math.sin(phase) * 1.8).round();
  }
}

class _SamplePoint {
  const _SamplePoint({required this.a, required this.b, required this.t});

  final int a;
  final int b;
  final DateTime t;
}
