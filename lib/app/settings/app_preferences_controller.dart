import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/pixel_pet.dart';
import '../di/app_providers.dart';
import 'app_preferences.dart';

final appPreferencesControllerProvider =
    NotifierProvider<AppPreferencesController, AppPreferences>(
      AppPreferencesController.new,
    );

class AppPreferencesController extends Notifier<AppPreferences> {
  @override
  AppPreferences build() {
    final prefs = AppPreferences.fromSharedPreferences(
      ref.read(sharedPreferencesProvider),
    );
    if (prefs.pixelPet == null) {
      final random = Random();
      final pet =
          PixelPetType.values[random.nextInt(PixelPetType.values.length)];
      debugPrint(
        '🎲 Random pet: ${pet.name} (index: ${PixelPetType.values.indexOf(pet)})',
      );
      Future.microtask(() => _update(prefs.copyWith(pixelPet: pet.name)));
      return prefs.copyWith(pixelPet: pet.name);
    }
    return prefs;
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

  Future<void> setScheduleBackgroundStyle(ScheduleBackgroundStyle value) async {
    await _update(state.copyWith(scheduleBackgroundStyle: value));
  }

  Future<void> setScheduleBackgroundOpacity(double value) async {
    await _update(state.copyWith(scheduleBackgroundOpacity: value));
  }

  Future<void> setScheduleWeek(int weekNumber) async {
    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    await _update(
      state.copyWith(
        scheduleWeekNumber: weekNumber,
        scheduleWeekSetDate: dateStr,
      ),
    );
  }

  /// Auto-save the server-provided current week so that
  /// [AppPreferences.computedScheduleWeek] can auto-advance weekly.
  Future<void> syncScheduleWeekFromServer(int currentWeek) async {
    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    // Only update if the week or date has actually changed.
    if (state.scheduleWeekNumber == currentWeek &&
        state.scheduleWeekSetDate == dateStr) {
      return;
    }
    await _update(
      state.copyWith(
        scheduleWeekNumber: currentWeek,
        scheduleWeekSetDate: dateStr,
      ),
    );
  }

  Future<void> setSelectedTermId(String termId) async {
    if (state.selectedTermId == termId) return;
    await _update(state.copyWith(selectedTermId: termId));
  }

  Future<void> reset() async {
    await _update(const AppPreferences());
  }

  Future<void> resetAppearance() async {
    await _update(
      state.copyWith(
        themePreset: AppThemePreset.ocean,
        darkMode: false,
        fontScale: 1.0,
        fontPreset: AppFontPreset.system,
        compactMode: false,
        highContrast: false,
        showWeekends: true,
        scheduleBackgroundStyle: ScheduleBackgroundStyle.paper,
        scheduleBackgroundOpacity: 0.24,
      ),
    );
  }

  Future<void> setGymPhoneNumber(String value) async {
    await _update(state.copyWith(gymPhoneNumber: value));
  }

  Future<void> clearGymPhoneNumber() async {
    await _update(state.copyWith(clearGymPhoneNumber: true));
  }

  Future<void> setGymPreferredSport({
    required String id,
    required String label,
  }) async {
    await _update(
      state.copyWith(gymPreferredSportId: id, gymPreferredSportLabel: label),
    );
  }

  Future<void> clearGymPreferredSport() async {
    await _update(state.copyWith(clearGymPreferredSport: true));
  }

  Future<void> setGymPreferredVenueType({
    required String id,
    required String label,
  }) async {
    await _update(
      state.copyWith(
        gymPreferredVenueTypeId: id,
        gymPreferredVenueTypeLabel: label,
      ),
    );
  }

  Future<void> clearGymPreferredVenueType() async {
    await _update(state.copyWith(clearGymPreferredVenueType: true));
  }

  Future<void> setGymTimePreference(GymTimePreference value) async {
    await _update(state.copyWith(gymTimePreference: value));
  }

  Future<void> clearGymTimePreference() async {
    await _update(state.copyWith(clearGymTimePreference: true));
  }

  Future<void> _update(AppPreferences nextState) async {
    state = nextState;
    await nextState.persist(ref.read(sharedPreferencesProvider));
  }
}
