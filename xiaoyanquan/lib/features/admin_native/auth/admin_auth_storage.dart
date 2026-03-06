import 'package:hive_flutter/hive_flutter.dart';

class AdminAuthStorage {
  static const _boxName = 'auth';
  static const _tokenKey = 'admin_native_token';
  static const _usernameKey = 'admin_native_username';
  static const _roleKey = 'admin_native_role';

  Box get _box => Hive.box(_boxName);

  String? get token => _box.get(_tokenKey) as String?;
  String? get username => _box.get(_usernameKey) as String?;
  String? get role => _box.get(_roleKey) as String?;

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  Future<void> saveSession({
    required String token,
    required String username,
    required String role,
  }) async {
    await _box.put(_tokenKey, token);
    await _box.put(_usernameKey, username);
    await _box.put(_roleKey, role);
  }

  Future<void> clear() async {
    await _box.delete(_tokenKey);
    await _box.delete(_usernameKey);
    await _box.delete(_roleKey);
  }
}
