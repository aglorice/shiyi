import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../app/theme/design_tokens.dart';
import '../../../../integrations/school_portal/sso/slider_captcha.dart';

/// 调用方在 sheet 里点"换一张"时执行：返回新的挑战；返回 null 视为失败。
typedef SliderRefreshCallback = Future<SliderCaptchaChallenge?> Function();

/// 调用方在 sheet 里完成拖动后执行：拿轨迹和当前 challenge 去服务端校验。
/// 返回 [SliderVerifyResult.passed]==true 即视为通过。
typedef SliderVerifyCallback = Future<SliderVerifyResult> Function(
  SliderCaptchaChallenge challenge,
  SliderTrackPayload payload,
);

/// 滑块验证 BottomSheet（控制器无关版本）。
///
/// 行为对齐学校 web 端 longbow.slidercaptcha.js：
/// - 大图固定渲染 280×155，按 `BoxFit.cover` 填满；
/// - 小拼图渲染宽度 = `smallNatural × (280 / bigNatural)`，
///   完全复刻 web 端的缩放公式；
/// - 拖动按钮位移驱动小拼图同步移动；按节流（≥20ms 且 ≥2px）采样轨迹。
/// - 校验通过：sheet 自动收起；失败：调 [onRefresh] 换图重试。
class SliderCaptchaSheet extends StatefulWidget {
  const SliderCaptchaSheet({
    super.key,
    required this.initialChallenge,
    required this.onVerify,
    required this.onRefresh,
  });

  final SliderCaptchaChallenge initialChallenge;
  final SliderVerifyCallback onVerify;
  final SliderRefreshCallback onRefresh;

  static const double canvasWidth = 280;
  static const double canvasHeight = 155;
  static const double sliderHeight = 36;
  static const double sliderButtonWidth = 36;

  /// 弹出 sheet 并等待"是否成功通过"。
  static Future<bool?> show(
    BuildContext context, {
    required SliderCaptchaChallenge initialChallenge,
    required SliderVerifyCallback onVerify,
    required SliderRefreshCallback onRefresh,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => SliderCaptchaSheet(
        initialChallenge: initialChallenge,
        onVerify: onVerify,
        onRefresh: onRefresh,
      ),
    );
  }

  @override
  State<SliderCaptchaSheet> createState() => _SliderCaptchaSheetState();
}

class _SliderCaptchaSheetState extends State<SliderCaptchaSheet> {
  late SliderCaptchaChallenge _challenge = widget.initialChallenge;

  /// 当前按钮（也即拼图）的位移：起点 0，最右等于 `canvasWidth - sliderButtonWidth`。
  double _offset = 0;
  bool _dragging = false;
  bool _verifying = false;
  bool _refreshing = false;

  /// 一次拖动开始时的 wall-clock 起点。
  DateTime? _dragStart;
  _SamplePoint? _lastSample;
  final List<SliderTrackPoint> _tracks = [];

  /// 上一次校验失败的提示。
  String? _hintMessage;

  /// 拖偏 / 失败 / 成功的视觉态：null=默认，'success'=绿，'fail'=红。
  String? _flashState;

  /// 用 `smallNatural × (280 / bigNatural)` 计算出来的真实渲染宽度。
  /// null 表示还没解到原图尺寸，渲染时按 fitHeight 兜底。
  double? _puzzleRenderWidth;

  /// 当前已经测过尺寸的 challenge，避免重复解码。
  SliderCaptchaChallenge? _decodedChallenge;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensurePuzzleSizeFor(_challenge);
    });
  }

  /// 用 [ui.instantiateImageCodec] 拿大图 + 小图的 naturalWidth，按 web 公式
  /// 算出真正的渲染宽度。
  Future<void> _ensurePuzzleSizeFor(SliderCaptchaChallenge challenge) async {
    if (identical(_decodedChallenge, challenge)) return;
    _decodedChallenge = challenge;
    try {
      final bigCodec = await ui.instantiateImageCodec(challenge.bigImageBytes);
      final bigFrame = await bigCodec.getNextFrame();
      final bigNatural = bigFrame.image.width;
      bigFrame.image.dispose();
      final smallCodec =
          await ui.instantiateImageCodec(challenge.smallImageBytes);
      final smallFrame = await smallCodec.getNextFrame();
      final smallNatural = smallFrame.image.width;
      smallFrame.image.dispose();
      if (!mounted) return;
      if (bigNatural <= 0 || smallNatural <= 0) return;
      setState(() {
        _puzzleRenderWidth =
            smallNatural * (SliderCaptchaSheet.canvasWidth / bigNatural);
      });
    } catch (_) {
      // 解码失败保留 null，由兜底 fitHeight 渲染。
    }
  }

  String get _barText {
    if (_verifying) return '校验中...';
    if (_refreshing) return '加载中...';
    if (_flashState == 'success') return '验证通过';
    if (_flashState == 'fail') return _hintMessage ?? '再试一次';
    return '向右滑动填充拼图';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  onPressed: _verifying || _refreshing ? null : _doRefresh,
                ),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _verifying
                      ? null
                      : () => Navigator.of(context).maybePop(false),
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
                      _challenge.bigImageBytes,
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
                          _challenge.smallImageBytes,
                          width: _puzzleRenderWidth,
                          height: canvasHeight,
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

  Future<void> _doRefresh() async {
    setState(() => _refreshing = true);
    final next = await widget.onRefresh();
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      if (next != null) {
        _challenge = next;
        _puzzleRenderWidth = null;
        _decodedChallenge = null;
      }
      _resetTrackingFields();
    });
    if (next != null) {
      // 异步算新挑战的尺寸。
      // ignore: discarded_futures
      _ensurePuzzleSizeFor(next);
    }
  }

  void _resetTrackingFields() {
    _offset = 0;
    _flashState = null;
    _hintMessage = null;
    _tracks.clear();
    _lastSample = null;
    _dragStart = null;
    _dragging = false;
  }

  void _onDragStart(DragStartDetails details) {
    if (_verifying || _refreshing) return;
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
    if (_dragStart == null) return;

    final a = newOffset.round();
    final b = _syntheticY(a);
    final last = _lastSample;
    final tSinceLast =
        last == null ? 0 : now.difference(last.t).inMilliseconds;

    setState(() => _offset = newOffset);

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
    if (_dragStart == null) {
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

    SliderVerifyResult? result;
    try {
      result = await widget.onVerify(_challenge, payload);
    } catch (_) {
      // onVerify 内部应自行 SnackBar 提示，这里只复位 sheet 状态。
    }

    if (!mounted) return;

    if (result?.passed == true) {
      setState(() {
        _flashState = 'success';
        _verifying = false;
      });
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.of(context).maybePop(true);
      return;
    }

    setState(() {
      _flashState = 'fail';
      _hintMessage = result?.message;
      _verifying = false;
    });
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    // 校验失败：自动换图给用户重试。
    await _doRefresh();
  }

  /// 拖动过程中给 b（Y 偏移）加一点点正弦抖动，模拟人手。
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
