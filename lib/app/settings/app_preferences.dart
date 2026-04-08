import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreset { ocean, sunrise, forest }

extension AppThemePresetX on AppThemePreset {
  String get label => switch (this) {
    AppThemePreset.ocean => '海盐青',
    AppThemePreset.sunrise => '日出橙',
    AppThemePreset.forest => '松林绿',
  };

  String get description => switch (this) {
    AppThemePreset.ocean => '清爽、稳定，适合长时间使用',
    AppThemePreset.sunrise => '更有活力，首页层次更明显',
    AppThemePreset.forest => '更柔和，适合低刺激阅读',
  };

  Color get seedColor => switch (this) {
    AppThemePreset.ocean => const Color(0xFF0E6A71),
    AppThemePreset.sunrise => const Color(0xFFB96A1F),
    AppThemePreset.forest => const Color(0xFF2E6B4B),
  };
}

enum AppFontPreset { system, serif, mono }

extension AppFontPresetX on AppFontPreset {
  String get label => switch (this) {
    AppFontPreset.system => '清爽',
    AppFontPreset.serif => '阅读',
    AppFontPreset.mono => '极简',
  };

  String get description => switch (this) {
    AppFontPreset.system => '系统默认风格',
    AppFontPreset.serif => '更偏阅读排版',
    AppFontPreset.mono => '更偏信息看板',
  };

  String? get fontFamily => switch (this) {
    AppFontPreset.system => null,
    AppFontPreset.serif => 'serif',
    AppFontPreset.mono => 'monospace',
  };
}

class AppPreferences {
  const AppPreferences({
    this.themePreset = AppThemePreset.ocean,
    this.darkMode = false,
    this.fontScale = 1.0,
    this.fontPreset = AppFontPreset.system,
    this.compactMode = false,
    this.highContrast = false,
    this.showWeekends = true,
    this.scheduleWeekNumber,
    this.scheduleWeekSetDate,
    this.pixelPet,
  });

  final AppThemePreset themePreset;
  final bool darkMode;
  final double fontScale;
  final AppFontPreset fontPreset;
  final bool compactMode;
  final bool highContrast;
  final bool showWeekends;

  /// The week number the user manually set.
  final int? scheduleWeekNumber;

  /// The date (ISO 8601) when [scheduleWeekNumber] was set.
  final String? scheduleWeekSetDate;

  /// The pixel pet assigned to this user (random on first launch).
  final String? pixelPet;

  /// Computes the current week number based on the saved reference.
  ///
  /// Returns `null` if no reference was ever set.
  int? get computedScheduleWeek {
    if (scheduleWeekNumber == null || scheduleWeekSetDate == null) {
      return null;
    }
    final refDate = DateTime.tryParse(scheduleWeekSetDate!);
    if (refDate == null) return scheduleWeekNumber;
    final diff = DateTime.now().difference(refDate).inDays;
    return scheduleWeekNumber! + (diff / 7).floor();
  }

  ThemeMode get themeMode => darkMode ? ThemeMode.dark : ThemeMode.light;

  String get fontScaleLabel => '${(fontScale * 100).round()}%';

  AppPreferences copyWith({
    AppThemePreset? themePreset,
    bool? darkMode,
    double? fontScale,
    AppFontPreset? fontPreset,
    bool? compactMode,
    bool? highContrast,
    bool? showWeekends,
    int? scheduleWeekNumber,
    String? scheduleWeekSetDate,
    String? pixelPet,
  }) {
    return AppPreferences(
      themePreset: themePreset ?? this.themePreset,
      darkMode: darkMode ?? this.darkMode,
      fontScale: fontScale ?? this.fontScale,
      fontPreset: fontPreset ?? this.fontPreset,
      compactMode: compactMode ?? this.compactMode,
      highContrast: highContrast ?? this.highContrast,
      showWeekends: showWeekends ?? this.showWeekends,
      scheduleWeekNumber: scheduleWeekNumber ?? this.scheduleWeekNumber,
      scheduleWeekSetDate: scheduleWeekSetDate ?? this.scheduleWeekSetDate,
      pixelPet: pixelPet ?? this.pixelPet,
    );
  }

  static const _themePresetKey = 'app.ui.themePreset';
  static const _darkModeKey = 'app.ui.darkMode';
  static const _fontScaleKey = 'app.ui.fontScale';
  static const _fontPresetKey = 'app.ui.fontPreset';
  static const _compactModeKey = 'app.ui.compactMode';
  static const _highContrastKey = 'app.ui.highContrast';
  static const _showWeekendsKey = 'app.schedule.showWeekends';
  static const _scheduleWeekNumberKey = 'app.schedule.weekNumber';
  static const _scheduleWeekSetDateKey = 'app.schedule.weekSetDate';
  static const _pixelPetKey = 'app.ui.pixelPet';

  factory AppPreferences.fromSharedPreferences(SharedPreferences preferences) {
    return AppPreferences(
      themePreset: _themePresetFromName(preferences.getString(_themePresetKey)),
      darkMode: preferences.getBool(_darkModeKey) ?? false,
      fontScale: _normalizeFontScale(
        preferences.getDouble(_fontScaleKey) ?? 1.0,
      ),
      fontPreset: _fontPresetFromName(preferences.getString(_fontPresetKey)),
      compactMode: preferences.getBool(_compactModeKey) ?? false,
      highContrast: preferences.getBool(_highContrastKey) ?? false,
      showWeekends: preferences.getBool(_showWeekendsKey) ?? true,
      scheduleWeekNumber: preferences.getInt(_scheduleWeekNumberKey),
      scheduleWeekSetDate: preferences.getString(_scheduleWeekSetDateKey),
      pixelPet: preferences.getString(_pixelPetKey),
    );
  }

  Future<void> persist(SharedPreferences preferences) async {
    await preferences.setString(_themePresetKey, themePreset.name);
    await preferences.setBool(_darkModeKey, darkMode);
    await preferences.setDouble(_fontScaleKey, fontScale);
    await preferences.setString(_fontPresetKey, fontPreset.name);
    await preferences.setBool(_compactModeKey, compactMode);
    await preferences.setBool(_highContrastKey, highContrast);
    await preferences.setBool(_showWeekendsKey, showWeekends);
    if (scheduleWeekNumber != null) {
      await preferences.setInt(_scheduleWeekNumberKey, scheduleWeekNumber!);
    } else {
      await preferences.remove(_scheduleWeekNumberKey);
    }
    if (scheduleWeekSetDate != null) {
      await preferences.setString(_scheduleWeekSetDateKey, scheduleWeekSetDate!);
    } else {
      await preferences.remove(_scheduleWeekSetDateKey);
    }
    if (pixelPet != null) {
      await preferences.setString(_pixelPetKey, pixelPet!);
    } else {
      await preferences.remove(_pixelPetKey);
    }
  }

  static AppThemePreset _themePresetFromName(String? value) {
    for (final item in AppThemePreset.values) {
      if (item.name == value) {
        return item;
      }
    }
    return AppThemePreset.ocean;
  }

  static AppFontPreset _fontPresetFromName(String? value) {
    for (final item in AppFontPreset.values) {
      if (item.name == value) {
        return item;
      }
    }
    return AppFontPreset.system;
  }

  static double _normalizeFontScale(double value) {
    return value.clamp(0.9, 1.2);
  }
}
