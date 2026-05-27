import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'github_mirror.dart';
import 'schedule_timing_preference.dart';

enum AppThemePreset {
  ocean,
  sunrise,
  forest,
  blossom,
  lavender,
  ink,
  amber,
  ruby,
}

extension AppThemePresetX on AppThemePreset {
  String get label => switch (this) {
    AppThemePreset.ocean => '海盐青',
    AppThemePreset.sunrise => '日出橙',
    AppThemePreset.forest => '松林绿',
    AppThemePreset.blossom => '樱花粉',
    AppThemePreset.lavender => '薰衣草',
    AppThemePreset.ink => '水墨蓝',
    AppThemePreset.amber => '琥珀',
    AppThemePreset.ruby => '石榴红',
  };

  String get description => switch (this) {
    AppThemePreset.ocean => '清爽、稳定，适合长时间使用',
    AppThemePreset.sunrise => '更有活力，首页层次更明显',
    AppThemePreset.forest => '柔和低刺激，适合阅读',
    AppThemePreset.blossom => '温柔，适合喜欢暖色的同学',
    AppThemePreset.lavender => '安静细腻，UI 整体偏冷',
    AppThemePreset.ink => '深沉墨蓝，专注向',
    AppThemePreset.amber => '稳重，复古暖调',
    AppThemePreset.ruby => '高对比，主色更跳',
  };

  Color get seedColor => switch (this) {
    AppThemePreset.ocean => const Color(0xFF0E6A71),
    AppThemePreset.sunrise => const Color(0xFFB96A1F),
    AppThemePreset.forest => const Color(0xFF2E6B4B),
    AppThemePreset.blossom => const Color(0xFFC85A8C),
    AppThemePreset.lavender => const Color(0xFF6E62C7),
    AppThemePreset.ink => const Color(0xFF2A4D7A),
    AppThemePreset.amber => const Color(0xFFA46A28),
    AppThemePreset.ruby => const Color(0xFFB42E48),
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

enum ScheduleBackgroundStyle { clean, paper, doodle, linen, aurora, graph }

extension ScheduleBackgroundStyleX on ScheduleBackgroundStyle {
  String get label => switch (this) {
    ScheduleBackgroundStyle.clean => '清爽留白',
    ScheduleBackgroundStyle.paper => '手账纸纹',
    ScheduleBackgroundStyle.doodle => '边角涂鸦',
    ScheduleBackgroundStyle.linen => '织物质感',
    ScheduleBackgroundStyle.aurora => '柔光渐层',
    ScheduleBackgroundStyle.graph => '方格便签',
  };

  String get description => switch (this) {
    ScheduleBackgroundStyle.clean => '保持默认干净背景',
    ScheduleBackgroundStyle.paper => '淡淡横线和页边距',
    ScheduleBackgroundStyle.doodle => '角落藏一点小细节',
    ScheduleBackgroundStyle.linen => '低调细密的纹理',
    ScheduleBackgroundStyle.aurora => '轻柔色块叠在底层',
    ScheduleBackgroundStyle.graph => '像草稿本一样规整',
  };

  IconData get icon => switch (this) {
    ScheduleBackgroundStyle.clean => Icons.layers_clear_outlined,
    ScheduleBackgroundStyle.paper => Icons.description_outlined,
    ScheduleBackgroundStyle.doodle => Icons.draw_outlined,
    ScheduleBackgroundStyle.linen => Icons.texture_outlined,
    ScheduleBackgroundStyle.aurora => Icons.blur_on_rounded,
    ScheduleBackgroundStyle.graph => Icons.grid_4x4_rounded,
  };

  Color get accentColor => switch (this) {
    ScheduleBackgroundStyle.clean => const Color(0xFF607172),
    ScheduleBackgroundStyle.paper => const Color(0xFFB97834),
    ScheduleBackgroundStyle.doodle => const Color(0xFFE07A8A),
    ScheduleBackgroundStyle.linen => const Color(0xFF7C6655),
    ScheduleBackgroundStyle.aurora => const Color(0xFF5478A6),
    ScheduleBackgroundStyle.graph => const Color(0xFF2F8C72),
  };

  /// 在「课表设置」里给用户挑选的背景集合。
  /// 删掉了 paper（横线纸太花）、doodle（涂鸦不够干净），
  /// 留下 4 个气质统一的。其余值仍然存在（旧版本可能已经被持久化），
  /// 但 UI 不再当成可选项展示——遇到这两种值会自动 fallback 到 [aurora]。
  static const List<ScheduleBackgroundStyle> selectable = [
    ScheduleBackgroundStyle.clean,
    ScheduleBackgroundStyle.aurora,
    ScheduleBackgroundStyle.graph,
    ScheduleBackgroundStyle.linen,
  ];

  /// 不在 [selectable] 里的旧值需要回落到默认。
  ScheduleBackgroundStyle get sanitized {
    return selectable.contains(this) ? this : ScheduleBackgroundStyle.aurora;
  }
}

/// 主题模式偏好。新增的"跟随系统"。
enum AppThemeMode { light, dark, system }

extension AppThemeModeX on AppThemeMode {
  String get label => switch (this) {
    AppThemeMode.light => '浅色',
    AppThemeMode.dark => '深色',
    AppThemeMode.system => '跟随系统',
  };

  IconData get icon => switch (this) {
    AppThemeMode.light => Icons.light_mode_outlined,
    AppThemeMode.dark => Icons.dark_mode_outlined,
    AppThemeMode.system => Icons.brightness_auto_outlined,
  };

  ThemeMode toFlutter() {
    return switch (this) {
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.system => ThemeMode.system,
    };
  }
}

enum GymTimePreference { morning, afternoon, evening }

extension GymTimePreferenceX on GymTimePreference {
  String get label => switch (this) {
    GymTimePreference.morning => '上午',
    GymTimePreference.afternoon => '下午',
    GymTimePreference.evening => '晚上',
  };

  String get description => switch (this) {
    GymTimePreference.morning => '优先 12:00 前开场的时段',
    GymTimePreference.afternoon => '优先 12:00-18:00 的时段',
    GymTimePreference.evening => '优先 18:00 后的时段',
  };
}

class AppPreferences {
  const AppPreferences({
    this.themePreset = AppThemePreset.ocean,
    this.darkMode = false,
    this.themeMode = AppThemeMode.light,
    this.fontScale = 0.9,
    this.fontPreset = AppFontPreset.system,
    this.compactMode = false,
    this.highContrast = false,
    this.showWeekends = false,
    this.scheduleBackgroundStyle = ScheduleBackgroundStyle.aurora,
    this.scheduleBackgroundOpacity = 0.24,
    this.customScheduleBackgroundPath,
    this.scheduleTiming = ScheduleTimingPreference.defaults,
    this.scheduleWeekNumber,
    this.scheduleWeekSetDate,
    this.selectedTermId,
    this.pixelPet,
    this.showHomeHitokoto = true,
    this.githubMirrorBundle,
    this.gymPhoneNumber,
    this.gymPreferredSportId,
    this.gymPreferredSportLabel,
    this.gymPreferredVenueTypeId,
    this.gymPreferredVenueTypeLabel,
    this.gymTimePreference,
    this.onboardingCompleted = false,
    this.classRemindersEnabled = false,
    this.classReminderLeadMinutes = 10,
  });

  final AppThemePreset themePreset;
  final bool darkMode;

  /// 主题模式（浅色/深色/跟随系统）。
  /// 优先级高于 [darkMode]。当为 [AppThemeMode.system] 时根据系统决定。
  final AppThemeMode themeMode;
  final double fontScale;
  final AppFontPreset fontPreset;
  final bool compactMode;
  final bool highContrast;
  final bool showWeekends;
  final ScheduleBackgroundStyle scheduleBackgroundStyle;
  final double scheduleBackgroundOpacity;

  /// 用户从相册选的自定义课表背景图本地路径。null 表示未设置。
  final String? customScheduleBackgroundPath;

  /// 节次时间表配置（上午/下午/晚上 + 节长 + 课间）。
  final ScheduleTimingPreference scheduleTiming;

  /// The week number the user manually set.
  final int? scheduleWeekNumber;

  /// The date (ISO 8601) when [scheduleWeekNumber] was set.
  final String? scheduleWeekSetDate;

  /// The term ID the user last selected.
  final String? selectedTermId;

  /// The pixel pet assigned to this user (random on first launch).
  final String? pixelPet;

  /// 是否在首页 Hero 区域显示一言气泡。默认显示。
  final bool showHomeHitokoto;

  /// 用户配置的 GitHub 镜像加速列表 + 当前选中。
  /// null 表示走默认配置（在 [resolvedGithubMirrorBundle] 里实例化）。
  final GithubMirrorBundle? githubMirrorBundle;

  GithubMirrorBundle get resolvedGithubMirrorBundle =>
      githubMirrorBundle ?? GithubMirrorBundle.initial();

  /// The phone number saved for gym booking.
  final String? gymPhoneNumber;

  final String? gymPreferredSportId;
  final String? gymPreferredSportLabel;
  final String? gymPreferredVenueTypeId;
  final String? gymPreferredVenueTypeLabel;
  final GymTimePreference? gymTimePreference;

  /// 用户是否已完成首次启动引导。false 时进入 [OnboardingPage]，
  /// 完成后再走 router 的常规 redirect。
  final bool onboardingCompleted;

  /// 是否启用上课提醒（本地通知）。默认关，用户在设置里主动开。
  final bool classRemindersEnabled;

  /// 上课前 N 分钟提醒。允许 0..30，默认 10。
  final int classReminderLeadMinutes;

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

  ThemeMode get flutterThemeMode {
    // 优先用 themeMode 字段；为兼容老版本（只持久化了 darkMode），
    // 若 themeMode 是默认 light 但 darkMode=true，仍按 dark 处理。
    if (themeMode == AppThemeMode.light && darkMode) {
      return ThemeMode.dark;
    }
    return themeMode.toFlutter();
  }

  String get fontScaleLabel => '${(fontScale * 100).round()}%';

  AppPreferences copyWith({
    AppThemePreset? themePreset,
    bool? darkMode,
    AppThemeMode? themeMode,
    double? fontScale,
    AppFontPreset? fontPreset,
    bool? compactMode,
    bool? highContrast,
    bool? showWeekends,
    ScheduleBackgroundStyle? scheduleBackgroundStyle,
    double? scheduleBackgroundOpacity,
    String? customScheduleBackgroundPath,
    bool clearCustomScheduleBackgroundPath = false,
    ScheduleTimingPreference? scheduleTiming,
    int? scheduleWeekNumber,
    String? scheduleWeekSetDate,
    String? selectedTermId,
    bool clearSelectedTermId = false,
    String? pixelPet,
    bool? showHomeHitokoto,
    GithubMirrorBundle? githubMirrorBundle,
    String? gymPhoneNumber,
    String? gymPreferredSportId,
    String? gymPreferredSportLabel,
    String? gymPreferredVenueTypeId,
    String? gymPreferredVenueTypeLabel,
    GymTimePreference? gymTimePreference,
    bool clearGymPhoneNumber = false,
    bool clearGymPreferredSport = false,
    bool clearGymPreferredVenueType = false,
    bool clearGymTimePreference = false,
    bool? onboardingCompleted,
    bool? classRemindersEnabled,
    int? classReminderLeadMinutes,
  }) {
    return AppPreferences(
      themePreset: themePreset ?? this.themePreset,
      darkMode: darkMode ?? this.darkMode,
      themeMode: themeMode ?? this.themeMode,
      fontScale: fontScale ?? this.fontScale,
      fontPreset: fontPreset ?? this.fontPreset,
      compactMode: compactMode ?? this.compactMode,
      highContrast: highContrast ?? this.highContrast,
      showWeekends: showWeekends ?? this.showWeekends,
      scheduleBackgroundStyle:
          scheduleBackgroundStyle ?? this.scheduleBackgroundStyle,
      scheduleBackgroundOpacity: scheduleBackgroundOpacity == null
          ? this.scheduleBackgroundOpacity
          : _normalizeScheduleBackgroundOpacity(scheduleBackgroundOpacity),
      customScheduleBackgroundPath: clearCustomScheduleBackgroundPath
          ? null
          : (customScheduleBackgroundPath ?? this.customScheduleBackgroundPath),
      scheduleTiming: scheduleTiming ?? this.scheduleTiming,
      scheduleWeekNumber: scheduleWeekNumber ?? this.scheduleWeekNumber,
      scheduleWeekSetDate: scheduleWeekSetDate ?? this.scheduleWeekSetDate,
      selectedTermId: clearSelectedTermId
          ? null
          : (selectedTermId ?? this.selectedTermId),
      pixelPet: pixelPet ?? this.pixelPet,
      showHomeHitokoto: showHomeHitokoto ?? this.showHomeHitokoto,
      githubMirrorBundle: githubMirrorBundle ?? this.githubMirrorBundle,
      gymPhoneNumber: clearGymPhoneNumber
          ? null
          : (gymPhoneNumber ?? this.gymPhoneNumber),
      gymPreferredSportId: clearGymPreferredSport
          ? null
          : (gymPreferredSportId ?? this.gymPreferredSportId),
      gymPreferredSportLabel: clearGymPreferredSport
          ? null
          : (gymPreferredSportLabel ?? this.gymPreferredSportLabel),
      gymPreferredVenueTypeId: clearGymPreferredVenueType
          ? null
          : (gymPreferredVenueTypeId ?? this.gymPreferredVenueTypeId),
      gymPreferredVenueTypeLabel: clearGymPreferredVenueType
          ? null
          : (gymPreferredVenueTypeLabel ?? this.gymPreferredVenueTypeLabel),
      gymTimePreference: clearGymTimePreference
          ? null
          : (gymTimePreference ?? this.gymTimePreference),
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      classRemindersEnabled:
          classRemindersEnabled ?? this.classRemindersEnabled,
      classReminderLeadMinutes:
          classReminderLeadMinutes ?? this.classReminderLeadMinutes,
    );
  }

  static const _themePresetKey = 'app.ui.themePreset';
  static const _darkModeKey = 'app.ui.darkMode';
  static const _themeModeKey = 'app.ui.themeMode';
  static const _fontScaleKey = 'app.ui.fontScale';
  static const _fontPresetKey = 'app.ui.fontPreset';
  static const _compactModeKey = 'app.ui.compactMode';
  static const _highContrastKey = 'app.ui.highContrast';
  static const _showWeekendsKey = 'app.schedule.showWeekends';
  static const _scheduleBackgroundStyleKey = 'app.schedule.backgroundStyle';
  static const _scheduleBackgroundOpacityKey = 'app.schedule.backgroundOpacity';
  static const _customScheduleBackgroundPathKey =
      'app.schedule.customBackgroundPath';
  static const _scheduleTimingKey = 'app.schedule.timing';
  static const _scheduleWeekNumberKey = 'app.schedule.weekNumber';
  static const _scheduleWeekSetDateKey = 'app.schedule.weekSetDate';
  static const _selectedTermIdKey = 'app.schedule.selectedTermId';
  static const _pixelPetKey = 'app.ui.pixelPet';
  static const _showHomeHitokotoKey = 'app.home.showHitokoto';
  static const _githubMirrorKey = 'app.update.githubMirror';
  static const _gymPhoneNumberKey = 'app.gym.phoneNumber';
  static const _gymPreferredSportIdKey = 'app.gym.preferredSportId';
  static const _gymPreferredSportLabelKey = 'app.gym.preferredSportLabel';
  static const _gymPreferredVenueTypeIdKey = 'app.gym.preferredVenueTypeId';
  static const _gymPreferredVenueTypeLabelKey =
      'app.gym.preferredVenueTypeLabel';
  static const _gymTimePreferenceKey = 'app.gym.timePreference';
  static const _onboardingCompletedKey = 'app.onboarding.completed';
  static const _classRemindersEnabledKey = 'app.reminder.classEnabled';
  static const _classReminderLeadKey = 'app.reminder.classLeadMin';

  factory AppPreferences.fromSharedPreferences(SharedPreferences preferences) {
    return AppPreferences(
      themePreset: _themePresetFromName(preferences.getString(_themePresetKey)),
      darkMode: preferences.getBool(_darkModeKey) ?? false,
      themeMode: _themeModeFromName(preferences.getString(_themeModeKey)),
      fontScale: _normalizeFontScale(
        preferences.getDouble(_fontScaleKey) ?? 0.9,
      ),
      fontPreset: _fontPresetFromName(preferences.getString(_fontPresetKey)),
      compactMode: preferences.getBool(_compactModeKey) ?? false,
      highContrast: preferences.getBool(_highContrastKey) ?? false,
      showWeekends: preferences.getBool(_showWeekendsKey) ?? false,
      scheduleBackgroundStyle: _scheduleBackgroundStyleFromName(
        preferences.getString(_scheduleBackgroundStyleKey),
      ).sanitized,
      scheduleBackgroundOpacity: _normalizeScheduleBackgroundOpacity(
        preferences.getDouble(_scheduleBackgroundOpacityKey) ?? 0.24,
      ),
      customScheduleBackgroundPath:
          preferences.getString(_customScheduleBackgroundPathKey),
      scheduleTiming: ScheduleTimingPreference.fromJsonString(
        preferences.getString(_scheduleTimingKey),
      ),
      scheduleWeekNumber: preferences.getInt(_scheduleWeekNumberKey),
      scheduleWeekSetDate: preferences.getString(_scheduleWeekSetDateKey),
      selectedTermId: preferences.getString(_selectedTermIdKey),
      pixelPet: preferences.getString(_pixelPetKey),
      showHomeHitokoto: preferences.getBool(_showHomeHitokotoKey) ?? true,
      githubMirrorBundle: GithubMirrorBundle.fromJsonString(
        preferences.getString(_githubMirrorKey),
      ),
      gymPhoneNumber: preferences.getString(_gymPhoneNumberKey),
      gymPreferredSportId: preferences.getString(_gymPreferredSportIdKey),
      gymPreferredSportLabel: preferences.getString(_gymPreferredSportLabelKey),
      gymPreferredVenueTypeId: preferences.getString(
        _gymPreferredVenueTypeIdKey,
      ),
      gymPreferredVenueTypeLabel: preferences.getString(
        _gymPreferredVenueTypeLabelKey,
      ),
      gymTimePreference: _gymTimePreferenceFromName(
        preferences.getString(_gymTimePreferenceKey),
      ),
      onboardingCompleted:
          preferences.getBool(_onboardingCompletedKey) ?? false,
      classRemindersEnabled:
          preferences.getBool(_classRemindersEnabledKey) ?? false,
      classReminderLeadMinutes:
          preferences.getInt(_classReminderLeadKey) ?? 10,
    );
  }

  Future<void> persist(SharedPreferences preferences) async {
    await preferences.setString(_themePresetKey, themePreset.name);
    await preferences.setBool(_darkModeKey, darkMode);
    await preferences.setString(_themeModeKey, themeMode.name);
    await preferences.setDouble(_fontScaleKey, fontScale);
    await preferences.setString(_fontPresetKey, fontPreset.name);
    await preferences.setBool(_compactModeKey, compactMode);
    await preferences.setBool(_highContrastKey, highContrast);
    await preferences.setBool(_showWeekendsKey, showWeekends);
    await preferences.setString(
      _scheduleBackgroundStyleKey,
      scheduleBackgroundStyle.name,
    );
    await preferences.setDouble(
      _scheduleBackgroundOpacityKey,
      scheduleBackgroundOpacity,
    );
    if (customScheduleBackgroundPath != null) {
      await preferences.setString(
        _customScheduleBackgroundPathKey,
        customScheduleBackgroundPath!,
      );
    } else {
      await preferences.remove(_customScheduleBackgroundPathKey);
    }
    await preferences.setString(
      _scheduleTimingKey,
      scheduleTiming.toJsonString(),
    );
    if (scheduleWeekNumber != null) {
      await preferences.setInt(_scheduleWeekNumberKey, scheduleWeekNumber!);
    } else {
      await preferences.remove(_scheduleWeekNumberKey);
    }
    if (scheduleWeekSetDate != null) {
      await preferences.setString(
        _scheduleWeekSetDateKey,
        scheduleWeekSetDate!,
      );
    } else {
      await preferences.remove(_scheduleWeekSetDateKey);
    }
    if (selectedTermId != null) {
      await preferences.setString(_selectedTermIdKey, selectedTermId!);
    } else {
      await preferences.remove(_selectedTermIdKey);
    }
    if (pixelPet != null) {
      await preferences.setString(_pixelPetKey, pixelPet!);
    } else {
      await preferences.remove(_pixelPetKey);
    }
    await preferences.setBool(_showHomeHitokotoKey, showHomeHitokoto);
    if (githubMirrorBundle != null) {
      await preferences.setString(
        _githubMirrorKey,
        githubMirrorBundle!.toJsonString(),
      );
    }
    if (gymPhoneNumber != null) {
      await preferences.setString(_gymPhoneNumberKey, gymPhoneNumber!);
    } else {
      await preferences.remove(_gymPhoneNumberKey);
    }
    if (gymPreferredSportId != null) {
      await preferences.setString(
        _gymPreferredSportIdKey,
        gymPreferredSportId!,
      );
    } else {
      await preferences.remove(_gymPreferredSportIdKey);
    }
    if (gymPreferredSportLabel != null) {
      await preferences.setString(
        _gymPreferredSportLabelKey,
        gymPreferredSportLabel!,
      );
    } else {
      await preferences.remove(_gymPreferredSportLabelKey);
    }
    if (gymPreferredVenueTypeId != null) {
      await preferences.setString(
        _gymPreferredVenueTypeIdKey,
        gymPreferredVenueTypeId!,
      );
    } else {
      await preferences.remove(_gymPreferredVenueTypeIdKey);
    }
    if (gymPreferredVenueTypeLabel != null) {
      await preferences.setString(
        _gymPreferredVenueTypeLabelKey,
        gymPreferredVenueTypeLabel!,
      );
    } else {
      await preferences.remove(_gymPreferredVenueTypeLabelKey);
    }
    if (gymTimePreference != null) {
      await preferences.setString(
        _gymTimePreferenceKey,
        gymTimePreference!.name,
      );
    } else {
      await preferences.remove(_gymTimePreferenceKey);
    }
    await preferences.setBool(_onboardingCompletedKey, onboardingCompleted);
    await preferences.setBool(
      _classRemindersEnabledKey,
      classRemindersEnabled,
    );
    await preferences.setInt(
      _classReminderLeadKey,
      classReminderLeadMinutes,
    );
  }

  static AppThemePreset _themePresetFromName(String? value) {
    for (final item in AppThemePreset.values) {
      if (item.name == value) {
        return item;
      }
    }
    return AppThemePreset.ocean;
  }

  static AppThemeMode _themeModeFromName(String? value) {
    for (final item in AppThemeMode.values) {
      if (item.name == value) {
        return item;
      }
    }
    return AppThemeMode.light;
  }

  static AppFontPreset _fontPresetFromName(String? value) {
    for (final item in AppFontPreset.values) {
      if (item.name == value) {
        return item;
      }
    }
    return AppFontPreset.system;
  }

  static ScheduleBackgroundStyle _scheduleBackgroundStyleFromName(
    String? value,
  ) {
    for (final item in ScheduleBackgroundStyle.values) {
      if (item.name == value) {
        return item;
      }
    }
    return ScheduleBackgroundStyle.paper;
  }

  static double _normalizeFontScale(double value) {
    return value.clamp(0.9, 1.2);
  }

  static double _normalizeScheduleBackgroundOpacity(double value) {
    return value.clamp(0.0, 1.0);
  }

  static GymTimePreference? _gymTimePreferenceFromName(String? value) {
    for (final item in GymTimePreference.values) {
      if (item.name == value) {
        return item;
      }
    }
    return null;
  }
}
