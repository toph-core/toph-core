import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

/// A real, correct `FlutterSecureStoragePlatform` implementation backed by a
/// plain in-memory map, swapped in for [FlutterSecureStoragePlatform.instance]
/// in tests. Not a mock of business logic — it's the same kind of stub
/// `shared_preferences`'s own `setMockInitialValues` provides, just written
/// out explicitly because `flutter_secure_storage` doesn't ship one. Install
/// it once per test via [install], which also clears any state left over
/// from a previous test.
class InMemorySecureStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> _store = {};

  static InMemorySecureStoragePlatform install() {
    final platform = InMemorySecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = platform;
    return platform;
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _store[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    return _store[key];
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    return _store.containsKey(key);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _store.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    return Map.of(_store);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _store.clear();
  }
}
