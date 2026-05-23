import 'dart:convert';
import 'dart:typed_data';

/// 描述一次滑块验证挑战所需的全部信息。
///
/// 五邑统一身份认证的滑块协议（南软 / Pankuangjie 那一套）：
/// - `bigImage` 为 280×155 jpeg，带缺口阴影；
/// - `smallImage` 为 `tagWidth`×155 png，是要拖到缺口的拼图；
/// - `safeSecure` 是 `smallImage` base64 解码后字节流的最后 16 个 ASCII 字节，
///   作为 verifySliderCaptcha 时 AES-CBC 的 key（详见
///   `customTheme/.../js/ids-sliderCaptcha.js`）。
class SliderCaptchaChallenge {
  const SliderCaptchaChallenge({
    required this.bigImageBytes,
    required this.smallImageBytes,
    required this.tagWidth,
    required this.yHeight,
    required this.safeSecure,
  });

  final Uint8List bigImageBytes;
  final Uint8List smallImageBytes;
  final int tagWidth;
  final int yHeight;
  final String safeSecure;

  /// 从 `/authserver/common/openSliderCaptcha.htl` 的 JSON 响应构造。
  factory SliderCaptchaChallenge.fromJson(Map<String, dynamic> json) {
    final bigBase64 = (json['bigImage'] as String? ?? '').trim();
    final smallBase64 = (json['smallImage'] as String? ?? '').trim();
    if (bigBase64.isEmpty || smallBase64.isEmpty) {
      throw const FormatException('滑块验证响应缺少图片字段。');
    }
    final big = base64Decode(bigBase64);
    final small = base64Decode(smallBase64);
    if (small.length < 16) {
      throw const FormatException('滑块小图字节数不足，无法提取 safeSecure。');
    }

    // safeSecure：取小图字节流尾 16 字节，按 charCode 拼成 16 字节 ASCII 串。
    final tail = small.sublist(small.length - 16);
    final secure = String.fromCharCodes(tail);

    return SliderCaptchaChallenge(
      bigImageBytes: big,
      smallImageBytes: small,
      tagWidth: (json['tagWidth'] as num?)?.toInt() ?? 0,
      yHeight: (json['yHeight'] as num?)?.toInt() ?? 0,
      safeSecure: secure,
    );
  }
}

/// 拖动轨迹中的一个采样点。
///
/// - `a` = 当前距起点的 X 偏移（px）
/// - `b` = 当前距起点的 Y 偏移（px，可有微小抖动）
/// - `c` = 距上一个采样点的时间差（ms）
class SliderTrackPoint {
  const SliderTrackPoint({required this.a, required this.b, required this.c});

  final int a;
  final int b;
  final int c;

  Map<String, int> toJson() => {'a': a, 'b': b, 'c': c};
}

/// verifySliderCaptcha.htl 调用所需的完整轨迹包。
class SliderTrackPayload {
  const SliderTrackPayload({
    required this.canvasLength,
    required this.moveLength,
    required this.tracks,
  });

  /// 前端固定为 280。
  final int canvasLength;

  /// 终点 X 与起点 X 的差值（px）。
  final int moveLength;

  /// 至少 3 个采样点（含 mousedown 占位 + mouseup 终点）。
  final List<SliderTrackPoint> tracks;

  Map<String, dynamic> toJson() => {
        'canvasLength': canvasLength,
        'moveLength': moveLength,
        'tracks': tracks.map((p) => p.toJson()).toList(),
      };
}

/// `verifySliderCaptcha.htl` 的服务端返回，errorCode == 1 即通过。
class SliderVerifyResult {
  const SliderVerifyResult({required this.passed, this.message});

  final bool passed;
  final String? message;

  factory SliderVerifyResult.fromJson(Map<String, dynamic> json) {
    final code = json['errorCode'];
    final passed = code is int ? code == 1 : code?.toString() == '1';
    return SliderVerifyResult(
      passed: passed,
      message: json['msg']?.toString() ?? json['errorMsg']?.toString(),
    );
  }
}
