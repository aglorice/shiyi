import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/app_providers.dart';
import 'app_preferences.dart';

final appPreferencesControllerProvider =
    NotifierProvider<AppPreferencesController, AppPreferences>(
      AppPreferencesController.new,
    );

class AppPreferencesController extends Notifier<AppPreferences> {
  @override
  AppPreferences build() {
    return AppPreferences.fromSharedPreferences(
      ref.read(sharedPreferencesProvider),
    );
  }

  Future<void> setThemePreset(AppThemePreset value) async {
    await _update(state.copyWith(themePreset: value));
  }

  Future<void> setDarkMode(bool value) async {
    await _update(state.copyWith(darkMode: value));
  }

  Future<void> setFontScale(double value) async {
    await _update(state.copyWith(fontScale: value));
  }

  Future<void> setFontPreset(AppFontPreset value) async {
    await _update(state.copyWith(fontPreset: value));
  }

  Future<void> setCompactMode(bool value) async {
    await _update(state.copyWith(compactMode: value));
  }

  Future<void> setHighContrast(bool value) async {
    await _update(state.copyWith(highContrast: value));
  }

  Future<void> setShowWeekends(bool value) async {
    await _update(state.copyWith(showWeekends: value));
  }

  Future<void> setScheduleWeek(int weekNumber) async {
    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    await _update(state.copyWith(
      scheduleWeekNumber: weekNumber,
      scheduleWeekSetDate: dateStr,
    ));
  }

  Future<void> reset() async {
    await _update(const AppPreferences());
  }

  Future<void> _update(AppPreferences nextState) async {
    state = nextState;
    await nextState.persist(ref.read(sharedPreferencesProvider));
  }
}
