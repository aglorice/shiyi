import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'json_cache_store.dart';

class SharedPreferencesJsonStore implements JsonCacheStore {
  SharedPreferencesJsonStore(this._preferences);

  final SharedPreferences _preferences;

  @override
  Future<Map<String, dynamic>?> readMap(String key) async {
    final raw = _preferences.getString(key);
    if (raw == null) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return decoded;
  }

  @override
  Future<void> remove(String key) async {
    await _preferences.remove(key);
  }

  @override
  Future<void> removeByPrefix(String prefix) async {
    final keys =
        _preferences.getKeys().where((key) => key.startsWith(prefix));
    for (final key in keys) {
      await _preferences.remove(key);
    }
  }

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    await _preferences.setString(key, jsonEncode(value));
  }
}
