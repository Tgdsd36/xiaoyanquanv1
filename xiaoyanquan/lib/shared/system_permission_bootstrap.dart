import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

class SystemPermissionBootstrap {
  SystemPermissionBootstrap._();

  static const String _boxName = 'auth';
  static const String _notificationAskedKey = 'notification_permission_asked';

  static Future<void> requestNotificationOnce() async {
    if (kIsWeb) return;
    if (!_supportsNotificationPermissionRequest) return;

    try {
      final box = Hive.box(_boxName);
      final asked = box.get(_notificationAskedKey) as bool? ?? false;
      if (asked) return;
      await box.put(_notificationAskedKey, true);
      await Permission.notification.request();
    } catch (_) {
      // 权限请求失败不阻断主流程
    }
  }

  static bool get _supportsNotificationPermissionRequest {
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }
}
