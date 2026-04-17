abstract class JsonCacheStore {
  Future<void> writeMap(String key, Map<String, dynamic> value);
  Future<Map<String, dynamic>?> readMap(String key);
  Future<void> remove(String key);
  Future<void> removeByPrefix(String prefix);
}
