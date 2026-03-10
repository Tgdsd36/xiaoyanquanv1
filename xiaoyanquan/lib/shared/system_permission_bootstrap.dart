import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants/api.dart';

/// 启动时一次性请求所有需要的系统权限
class SystemPermissionBootstrap {
  SystemPermissionBootstrap._();

  static const String _boxName = 'auth';
  static const String _allPermissionsAskedKey = 'all_permissions_asked';

  /// 首次启动时依次请求全部权限，后续不再重复弹窗
  static Future<void> requestAllOnce() async {
    if (kIsWeb) return;
    if (!_isMobilePlatform) return;

    try {
      final box = Hive.box(_boxName);
      final asked = box.get(_allPermissionsAskedKey) as bool? ?? false;
      if (asked) return;
      await box.put(_allPermissionsAskedKey, true);

      if (Platform.isIOS) {
        // iOS 首次联网会弹出「允许使用无线数据」系统弹窗
        await _triggerNetworkDialog();
        await Future<void>.delayed(const Duration(milliseconds: 800));
      } else {
        // Android 上等待 Activity 完全就绪
        await Future<void>.delayed(const Duration(seconds: 1));
      }

      // 依次请求，每个权限之间间隔足够时间确保弹窗完整显示
      await _requestSafe(Permission.notification);
      await Future<void>.delayed(const Duration(milliseconds: 800));

      if (Platform.isIOS) {
        await _requestSafe(Permission.photos);
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await _requestSafe(Permission.photosAddOnly);
      } else if (Platform.isAndroid) {
        // Android: 逐个请求，不用 requestManySafe 批量，避免弹窗重叠
        await _requestSafe(Permission.photos);
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await _requestSafe(Permission.videos);
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await _requestSafe(Permission.storage);
      }
    } catch (_) {
      // 权限请求失败不阻断主流程
    }
  }

  /// 发一个轻量 HEAD 请求触发 iOS 网络权限弹窗
  static Future<void> _triggerNetworkDialog() async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      // HEAD 请求不传输 body，开销最小
      await dio.head(Api.baseUrl);
    } catch (_) {
      // 请求成功与否不重要，目的只是触发系统弹窗
    }
  }

  static Future<void> _requestSafe(Permission permission) async {
    try {
      await permission.request();
    } catch (_) {}
  }

  static Future<void> _requestManySafe(List<Permission> permissions) async {
    try {
      await permissions.request();
    } catch (_) {}
  }

  static bool get _isMobilePlatform {
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }
}
