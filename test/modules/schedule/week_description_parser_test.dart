import 'package:flutter_test/flutter_test.dart';
import 'package:uni_yi/modules/schedule/domain/parsers/week_description_parser.dart';

/// 周次描述解析器单测。这是过滤"今天到底有没有这节课"的关键路径，
/// 教务系统给的字符串五花八门，每种格式都要 cover 到。
void main() {
  group('parseWeekDescription · 边界', () {
    test('null / 空串 / 空白返回 null', () {
      expect(parseWeekDescription(null), isNull);
      expect(parseWeekDescription(''), isNull);
      expect(parseWeekDescription('   '), isNull);
      expect(parseWeekDescription('\t \n'), isNull);
    });

    test('纯非法字符返回 null', () {
      expect(parseWeekDescription('abc'), isNull);
      expect(parseWeekDescription('周'), isNull);
    });

    test('end < start 的逆区间不会塞数据', () {
      // 16-1 这种异常应回 null（没有合法周）
      expect(parseWeekDescription('16-1'), isNull);
    });
  });

  group('parseWeekDescription · 连续区间', () {
    test('1-16 → 1..16', () {
      expect(parseWeekDescription('1-16'), List.generate(16, (i) => i + 1));
    });

    test('1-16周 末尾的"周"字被剥掉', () {
      expect(parseWeekDescription('1-16周'), List.generate(16, (i) => i + 1));
    });

    test('1~16 用波浪号也能识别', () {
      expect(parseWeekDescription('1~16'), List.generate(16, (i) => i + 1));
    });

    test('1～16 全角波浪号', () {
      expect(parseWeekDescription('1～16'), List.generate(16, (i) => i + 1));
    });

    test('单周（start == end）返回单元素列表', () {
      expect(parseWeekDescription('5'), [5]);
      expect(parseWeekDescription('5-5'), [5]);
    });
  });

  group('parseWeekDescription · 单/双周', () {
    test('1-16(单周) → 奇数周', () {
      expect(parseWeekDescription('1-16(单周)'), [1, 3, 5, 7, 9, 11, 13, 15]);
    });

    test('2-16(双周) → 偶数周', () {
      expect(parseWeekDescription('2-16(双周)'), [2, 4, 6, 8, 10, 12, 14, 16]);
    });

    test('全角括号 1-16（单周）也识别', () {
      expect(parseWeekDescription('1-16（单周）'), [1, 3, 5, 7, 9, 11, 13, 15]);
    });

    test('1-16(双周)周 同时有"周"字与括号 也能正确解析', () {
      expect(parseWeekDescription('1-16(双周)周'), [2, 4, 6, 8, 10, 12, 14, 16]);
    });
  });

  group('parseWeekDescription · 离散周次', () {
    test('1,3,5,7 用半角逗号', () {
      expect(parseWeekDescription('1,3,5,7'), [1, 3, 5, 7]);
    });

    test('1、3、5 中文顿号', () {
      expect(parseWeekDescription('1、3、5'), [1, 3, 5]);
    });

    test('混合区间 + 离散 1-4,7,9-12', () {
      expect(parseWeekDescription('1-4,7,9-12'), [1, 2, 3, 4, 7, 9, 10, 11, 12]);
    });

    test('停课周次 1-12,14-16 跳过 13 周', () {
      expect(parseWeekDescription('1-12,14-16'), [
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15, 16,
      ]);
    });

    test('重复的周次自动去重并升序', () {
      expect(parseWeekDescription('5,3,1,3,5'), [1, 3, 5]);
    });
  });

  group('parseWeekDescription · 噪声', () {
    test('"教学"两字会被剥掉 1-16教学周', () {
      expect(parseWeekDescription('1-16教学周'), List.generate(16, (i) => i + 1));
    });

    test('内部空格容忍 "1 - 16 周"', () {
      expect(parseWeekDescription('1 - 16 周'), List.generate(16, (i) => i + 1));
    });
  });
}
