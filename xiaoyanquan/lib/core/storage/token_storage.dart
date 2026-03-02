import 'package:hive_flutter/hive_flutter.dart';

class TokenStorage {
  static const _boxName = 'auth';
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  Box get _box => Hive.box(_boxName);

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_boxName);
  }

  String? get accessToken => _box.get(_accessTokenKey);
  String? get refreshToken => _box.get(_refreshTokenKey);

  bool get isLoggedIn => accessToken != null && accessToken!.isNotEmpty;

  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _box.put(_accessTokenKey, accessToken);
    await _box.put(_refreshTokenKey, refreshToken);
  }

  Future<void> clear() async {
    await _box.delete(_accessTokenKey);
    await _box.delete(_refreshTokenKey);
  }
}
