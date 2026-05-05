import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
              opacity: 0.001,
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
      await _waitForRender();
      final boundary =
          boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null || boundary.size.isEmpty) {
        throw StateError('分享长图生成失败。');
      }

      await _waitForRender();
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
        files: [XFile.fromData(bytes, name: fileName, mimeType: 'image/png')],
        fileNameOverrides: [fileName],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  static Rect? shareOriginFor(BuildContext context) {
    final renderObject = context.findRenderObject();
    return renderObject is RenderBox && renderObject.hasSize
        ? renderObject.localToGlobal(Offset.zero) & renderObject.size
        : null;
  }

  static Future<void> _waitForRender() async {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 32));
    await WidgetsBinding.instance.endOfFrame;
  }
}
