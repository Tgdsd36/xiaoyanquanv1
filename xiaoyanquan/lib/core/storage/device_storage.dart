import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class DeviceStorage {
  static const _boxName = 'auth';
  static const _deviceIdKey = 'device_id';

  Box get _box => Hive.box(_boxName);

  String? get deviceId => _box.get(_deviceIdKey) as String?;

  Future<String> getOrCreateDeviceId() async {
    final existing = deviceId;
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final created = _generateDeviceId();
    await _box.put(_deviceIdKey, created);
    return created;
  }

  String get platformLabel {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  String get deviceName => 'xiaoyanquan-$platformLabel';

  String _generateDeviceId() {
    final rand = Random.secure();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final randomPart =
        List.generate(20, (_) => rand.nextInt(16).toRadixString(16)).join();
    return 'dev-$timestamp-$randomPart';
  }
}
