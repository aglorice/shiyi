import 'package:flutter/widgets.dart';

/// 全局间距常量。每个值在文件里只出现一次，避免散落的 12/16/20/24/32。
class AppSpacing {
  const AppSpacing._();

  static const double xxs = 4;
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double xxl = 36;

  /// 页面左右默认留白。
  static const double pageH = 20;

  /// 设置/列表页两侧+顶部留白。底部要给 nav bar 让位，
  /// 用 [pageBottomGap] 放在 ListView padding 末位即可。
  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(20, 12, 20, 32);

  /// 当页面底部紧挨着 BottomNavigationBar 时使用。
  static const EdgeInsets pagePaddingWithNav =
      EdgeInsets.fromLTRB(20, 12, 20, 96);

  /// 下边距，单独使用。
  static const double pageBottomGap = 32;
  static const double pageBottomGapWithNav = 96;
}

/// 全局圆角常量。
class AppRadius {
  const AppRadius._();

  static const double xs = 12;
  static const double sm = 16;
  static const double md = 20;
  static const double lg = 24;
  static const double pill = 999;
}
