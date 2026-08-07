import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mary_ai_pos/features/view/auth/data/models/user/user_model.dart';

class OfflineCachedUser {
  final String brandId;
  final String password;
  final String accessToken;
  final String refreshToken;
  final Map<String, dynamic> userModelJson;

  const OfflineCachedUser({
    required this.brandId,
    required this.password,
    required this.accessToken,
    required this.refreshToken,
    required this.userModelJson,
  });

  Map<String, dynamic> toJson() => {
        'brandId': brandId,
        'password': password,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'userModelJson': userModelJson,
      };

  factory OfflineCachedUser.fromJson(Map<String, dynamic> json) =>
      OfflineCachedUser(
        brandId: json['brandId'] as String? ?? '',
        password: json['password'] as String? ?? '',
        accessToken: json['accessToken'] as String? ?? '',
        refreshToken: json['refreshToken'] as String? ?? '',
        userModelJson: (json['userModelJson'] as Map?)
                ?.cast<String, dynamic>() ??
            {},
      );
}

/// Barcha online login qilgan userlarni lokal saqlaydigan cache.
/// Internet yo'qligida shu cache orqali login imkonini beradi.
///
/// Bu yerda parollar/pincodelar/tokenlar saqlanadi — shuning uchun
/// `SharedPreferences` emas, OS-backed secure storage ishlatiladi
/// (offline-first-architecture-plan.md §11 Phase 6).
class OfflineAuthCache {
  static const _key = 'offline_users_v1';

  /// Pincode → user mapping: har bir ofitsiant pincodi bo'yicha alohida saqlanadi.
  /// Key: "${brandId}_${pincode}"
  static const _pinKey = 'offline_pin_users_v1';

  final FlutterSecureStorage _secure;

  const OfflineAuthCache(this._secure);

  Future<Map<String, OfflineCachedUser>> _readAll() async {
    try {
      final raw = await _secure.read(key: _key);
      if (raw == null) return {};
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map(
        (k, v) => MapEntry(
          k,
          OfflineCachedUser.fromJson(v as Map<String, dynamic>),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeAll(Map<String, OfflineCachedUser> map) async {
    await _secure.write(
      key: _key,
      value: jsonEncode(map.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// Online login muvaffaqiyatli bo'lgandan keyin chaqiriladi.
  Future<void> saveUser({
    required String brandId,
    required String password,
    required UserModel user,
    required String accessToken,
    required String refreshToken,
  }) async {
    if (brandId.isEmpty) return;
    final all = await _readAll();
    all[brandId] = OfflineCachedUser(
      brandId: brandId,
      password: password,
      accessToken: accessToken,
      refreshToken: refreshToken,
      userModelJson: user.toJson(),
    );
    await _writeAll(all);
  }

  /// Offline login: brandId + password mos kelsa cached userni qaytaradi.
  Future<OfflineCachedUser?> validateAndGetUser(
    String brandId,
    String password,
  ) async {
    if (brandId.isEmpty || password.isEmpty) return null;
    final cached = (await _readAll())[brandId];
    if (cached == null) return null;
    if (cached.password != password) return null;
    return cached;
  }

  /// UserBloc fallback: faqat brandId bilan (parol tekshirmasdan).
  Future<OfflineCachedUser?> getCachedUser(String brandId) async {
    if (brandId.isEmpty) return null;
    return (await _readAll())[brandId];
  }

  /// Server aniq rad javobini bergandan keyin chaqiriladi (masalan foydalanuvchi
  /// endi faol emas) — shu brand-darajali cache endi offline holatda ham
  /// ishlamasin. Vaqt asosidagi muddat yo'q — bu yagona bekor qilish yo'li.
  Future<void> removeUser(String brandId) async {
    if (brandId.isEmpty) return;
    final all = await _readAll();
    if (all.remove(brandId) != null) await _writeAll(all);
  }

  // ── Per-pincode cache ─────────────────────────────────────────────────────

  Future<Map<String, OfflineCachedUser>> _readPins() async {
    try {
      final raw = await _secure.read(key: _pinKey);
      if (raw == null) return {};
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map(
        (k, v) => MapEntry(k, OfflineCachedUser.fromJson(v as Map<String, dynamic>)),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _writePins(Map<String, OfflineCachedUser> map) async {
    await _secure.write(
      key: _pinKey,
      value: jsonEncode(map.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// Har bir ofitsiantning pincodi bilan loginini saqlab qo'yadi.
  Future<void> saveForPin({
    required String brandId,
    required String pincode,
    required UserModel user,
    required String accessToken,
    required String refreshToken,
  }) async {
    if (brandId.isEmpty || pincode.isEmpty) return;
    final all = await _readPins();
    all['${brandId}_$pincode'] = OfflineCachedUser(
      brandId: brandId,
      password: pincode,
      accessToken: accessToken,
      refreshToken: refreshToken,
      userModelJson: user.toJson(),
    );
    await _writePins(all);
  }

  /// Offline PIN login: pincode mos kelsa cached user qaytaradi.
  Future<OfflineCachedUser?> getForPin(String brandId, String pincode) async {
    if (brandId.isEmpty || pincode.isEmpty) return null;
    return (await _readPins())['${brandId}_$pincode'];
  }

  /// [removeUser]ning pincode-darajali versiyasi — server shu aniq pincode
  /// endi yaroqsiz deb aniq javob bergandan keyin chaqiriladi.
  Future<void> removeForPin(String brandId, String pincode) async {
    if (brandId.isEmpty || pincode.isEmpty) return;
    final all = await _readPins();
    if (all.remove('${brandId}_$pincode') != null) await _writePins(all);
  }

  /// One-time upgrade path for installs that predate the secure-storage
  /// migration: moves the two cache blobs out of plaintext
  /// `SharedPreferences` into secure storage, then deletes the plaintext
  /// copy. Idempotent — a no-op once the plaintext keys are gone.
  static Future<void> migrateLegacyPlaintext(
    SharedPreferences prefs,
    FlutterSecureStorage secure,
  ) async {
    for (final key in [_key, _pinKey]) {
      final plain = prefs.getString(key);
      if (plain == null) continue;
      await secure.write(key: key, value: plain);
      await prefs.remove(key);
    }
  }
}
