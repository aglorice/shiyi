import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:share_plus/share_plus.dart';

class LongImageShare {
  const LongImageShare._();

  static Future<Uint8List> capturePng({
    required BuildContext context,
    required Widget child,
    double? width,
    double maxPixelDimension = 16000,
  }) async {
    final boundaryKey = GlobalKey();
    final overlay = Overlay.of(context, rootOverlay: true);
    final screenSize = MediaQuery.sizeOf(context);
    final deviceRatio = MediaQuery.devicePixelRatioOf(context);
    final captureWidth =
        width ?? screenSize.width.clamp(320.0, 430.0).toDouble();
    final capturedThemes = InheritedTheme.capture(
      from: context,
      to: overlay.context,
    );
    final mediaQuery = MediaQuery.maybeOf(context);
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;

    final entry = OverlayEntry(
      builder: (overlayContext) {
        final viewportHeight = MediaQuery.sizeOf(overlayContext).height;
        return Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.004,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: captureWidth,
                  height: viewportHeight,
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: capturedThemes.wrap(
                      MediaQuery(
                        data:
                            mediaQuery ??
                            MediaQueryData(
                              size: Size(captureWidth, viewportHeight),
                            ),
                        child: Directionality(
                          textDirection: textDirection,
                          child: Material(
                            type: MaterialType.transparency,
                            child: RepaintBoundary(
                              key: boundaryKey,
                              child: SizedBox(
                                width: captureWidth,
                                child: child,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    try {
      await _waitForPaint(boundaryKey);
      final boundary =
          boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null || boundary.size.isEmpty) {
        throw StateError('分享长图生成失败。');
      }

      await _ensurePainted(boundary);
      final maxSide = math.max(boundary.size.width, boundary.size.height);
      final limitedRatio = maxPixelDimension / maxSide;
      final pixelRatio = math.min(deviceRatio, limitedRatio).clamp(0.5, 3.0);
      final image = await boundary.toImage(pixelRatio: pixelRatio.toDouble());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) {
        throw StateError('分享长图生成失败。');
      }
      return bytes.buffer.asUint8List();
    } finally {
      entry.remove();
    }
  }

  static Future<ShareResult> sharePng({
    required Uint8List bytes,
    required String fileName,
    String? title,
    String? text,
    Rect? sharePositionOrigin,
  }) {
    return SharePlus.instance.share(
      ShareParams(
        title: title,
        text: text,
        files: [XFile.fromData(bytes, mimeType: 'image/png')],
        fileNameOverrides: [fileName],
        sharePositionOrigin:
            sharePositionOrigin ?? const Rect.fromLTWH(0, 0, 100, 100),
      ),
    );
  }

  static Rect? shareOriginFor(BuildContext context) {
    final renderObject = context.findRenderObject();
    return renderObject is RenderBox && renderObject.hasSize
        ? renderObject.localToGlobal(Offset.zero) & renderObject.size
        : null;
  }

  /// Wait until the overlay entry has been built, laid out, and painted.
  static Future<void> _waitForPaint(GlobalKey key) async {
    // Give the overlay entry a chance to be built and laid out.
    await _nextFrame;
    await _nextFrame;
    // Extra delay for paint to finish on slow devices.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await _nextFrame;
  }

  /// Ensure a [RenderRepaintBoundary] has been painted before calling toImage.
  static Future<void> _ensurePainted(RenderRepaintBoundary boundary) async {
    // debugNeedsPaint is always false in release mode, so we must wait
    // a fixed number of frames regardless.
    if (kDebugMode) {
      for (var i = 0; i < 8; i++) {
        if (!boundary.debugNeedsPaint) return;
        await _nextFrame;
      }
    } else {
      await _nextFrame;
      await _nextFrame;
    }
  }

  static Future<void> get _nextFrame {
    final completer = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      completer.complete();
    });
    SchedulerBinding.instance.scheduleFrame();
    return completer.future;
  }
}
