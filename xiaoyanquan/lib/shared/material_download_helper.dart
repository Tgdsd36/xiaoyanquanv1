import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/network/http_client.dart';
import '../core/utils/url_utils.dart';
import '../features/home/repositories/material_repository.dart';
import 'live_photo_view.dart';

enum _DownloadKind { image, video, livePhoto }

class MaterialDownloadHelper {
  MaterialDownloadHelper._();

  static final MaterialRepository _repo = MaterialRepository();
  static const String _authBoxName = 'auth';
  static const String _downloadNoticeShownKey = 'download_notice_shown';

  static Future<bool> downloadToAlbum(
    BuildContext context, {
    required int materialId,
    required String materialType,
    List<String> fallbackUrls = const [],
    String fallbackVideoUrl = '',
    String fallbackLiveVideoUrl = '',
  }) async {
    if (kIsWeb) {
      _showSnack(context, 'Web 端暂不支持一键保存，请长按素材手动保存');
      return false;
    }

    final shouldShowNotice = _shouldShowDownloadNotice();
    if (shouldShowNotice) {
      final shouldContinue = await _showDownloadConfirmDialog(context);
      if (!shouldContinue || !context.mounted) return false;
      await _markDownloadNoticeShown();
    }

    final kind = _resolveKind(materialType);
    final permission = await _ensureMediaPermission(kind);
    if (!permission.granted) {
      if (!context.mounted) return false;
      _showSnack(context, '未获得相册权限，无法保存素材');
      if (permission.shouldOpenSettings) {
        await _showOpenSettingsDialog(context);
      }
      return false;
    }

    if (!context.mounted) return false;
    _showSnack(
      context,
      _isDesktopPlatform() ? '正在下载并保存到本机下载目录...' : '正在下载并保存到系统相册...',
    );

    final downloadData = await _requestDownloadData(materialId);
    if (!downloadData.ok) {
      if (!context.mounted) return false;
      _showSnack(context, downloadData.message);
      return false;
    }

    final responseUrls = _parseDownloadUrls(downloadData.data);
    final mergedUrls = _normalizeDistinctUrls([
      ...responseUrls,
      ...fallbackUrls,
      fallbackVideoUrl,
      fallbackLiveVideoUrl,
    ]);

    try {
      final bool saved;
      String successMessage = '下载成功，已保存到系统相册';
      if (_isDesktopPlatform()) {
        successMessage = '下载成功，已保存到本机下载目录';
      }

      if (kind == _DownloadKind.livePhoto && Platform.isIOS) {
        final imageUrl = UrlUtils.firstImageUrl(mergedUrls);
        final videoUrl = UrlUtils.firstVideoUrl(mergedUrls);
        if (imageUrl.isEmpty || videoUrl.isEmpty) {
          if (!context.mounted) return false;
          _showSnack(context, 'Live 素材缺少静态图或动态视频资源');
          return false;
        }

        final channelGranted = await LivePhotoChannel.requestPermission();
        if (!channelGranted) {
          if (!context.mounted) return false;
          _showSnack(context, '未获得相册写入权限，无法保存 Live');
          return false;
        }

        saved = await LivePhotoChannel.saveLivePhoto(
          imageUrl: imageUrl,
          videoUrl: videoUrl,
        );
        successMessage = 'Live Photo 已保存到 iPhone 相册';
      } else if (kind == _DownloadKind.video) {
        final videoUrl = UrlUtils.firstVideoUrl(mergedUrls);
        if (videoUrl.isEmpty) {
          if (!context.mounted) return false;
          _showSnack(context, '未获取到可下载的视频地址');
          return false;
        }
        saved = await _saveRemoteFileToAlbum(videoUrl);
      } else {
        // 图片与非 iOS 设备的 Live 素材，统一保存静态图
        final imageUrl = UrlUtils.firstImageUrl(mergedUrls);
        if (imageUrl.isEmpty) {
          if (!context.mounted) return false;
          _showSnack(context, '未获取到可下载的图片地址');
          return false;
        }
        saved = await _saveRemoteFileToAlbum(imageUrl);
        if (kind == _DownloadKind.livePhoto) {
          successMessage = '已保存静态图，Live 动效请在 iPhone 相册查看';
        }
      }

      if (!context.mounted) return false;
      if (saved) {
        _showSnack(context, successMessage);
        return true;
      }

      _showSnack(context, '保存失败，请稍后重试');
      return false;
    } catch (_) {
      if (!context.mounted) return false;
      _showSnack(context, '下载失败，请检查网络后重试');
      return false;
    }
  }

  static _DownloadKind _resolveKind(String rawType) {
    final type = rawType.trim().toLowerCase();
    if (type == 'video') return _DownloadKind.video;
    if (type == 'live_photo' || type == 'live') return _DownloadKind.livePhoto;
    return _DownloadKind.image;
  }

  static bool _shouldShowDownloadNotice() {
    try {
      final box = Hive.box(_authBoxName);
      return !(box.get(_downloadNoticeShownKey) as bool? ?? false);
    } catch (_) {
      return true;
    }
  }

  static Future<void> _markDownloadNoticeShown() async {
    try {
      final box = Hive.box(_authBoxName);
      await box.put(_downloadNoticeShownKey, true);
    } catch (_) {}
  }

  static Future<bool> _showDownloadConfirmDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('确认下载'),
          content: const Text('下载会消耗网络流量，并请求相册权限用于保存素材，是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('继续下载'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  static Future<({bool granted, bool shouldOpenSettings})> _ensureMediaPermission(
    _DownloadKind kind,
  ) async {
    if (kIsWeb) {
      return (granted: false, shouldOpenSettings: false);
    }

    // 桌面端不申请系统相册权限，避免缺少插件实现导致崩溃。
    if (_isDesktopPlatform()) {
      return (granted: true, shouldOpenSettings: false);
    }

    if (Platform.isIOS) {
      PermissionStatus status;
      try {
        status = await Permission.photosAddOnly.request();
      } on MissingPluginException {
        return (granted: false, shouldOpenSettings: false);
      }
      return (
        granted: status.isGranted || status.isLimited,
        shouldOpenSettings: status.isPermanentlyDenied || status.isRestricted,
      );
    }

    if (Platform.isAndroid) {
      final permissions =
          kind == _DownloadKind.video
              ? <Permission>[Permission.videos, Permission.storage]
              : <Permission>[Permission.photos, Permission.storage];
      Map<Permission, PermissionStatus> statusMap;
      try {
        statusMap = await permissions.request();
      } on MissingPluginException {
        return (granted: false, shouldOpenSettings: false);
      }
      final statuses = statusMap.values.toList();
      final granted = statuses.any((s) => s.isGranted || s.isLimited);
      final shouldOpenSettings = statuses.any((s) => s.isPermanentlyDenied);
      return (granted: granted, shouldOpenSettings: shouldOpenSettings);
    }

    return (granted: true, shouldOpenSettings: false);
  }

  static Future<void> _showOpenSettingsDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('需要相册权限'),
          content: const Text('当前权限已被永久拒绝，请前往系统设置开启相册权限后重试。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await openAppSettings();
              },
              child: const Text('去设置'),
            ),
          ],
        );
      },
    );
  }

  static Future<({bool ok, String message, dynamic data})> _requestDownloadData(
    int materialId,
  ) async {
    try {
      final resp = await _repo.download(materialId);
      if (resp.isSuccess) {
        return (ok: true, message: '', data: resp.data);
      }
      final message = resp.message.isNotEmpty ? resp.message : '下载失败，请稍后重试';
      return (ok: false, message: message, data: null);
    } on DioException catch (e) {
      return (
        ok: false,
        message: _extractDioMessage(e),
        data: e.response?.data,
      );
    } catch (_) {
      return (ok: false, message: '下载失败，请稍后重试', data: null);
    }
  }

  static String _extractDioMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final msg = (data['message'] ?? '').toString().trim();
      if (msg.isNotEmpty) return msg;
    }
    if (e.message != null && e.message!.trim().isNotEmpty) {
      return e.message!.trim();
    }
    return '网络异常，请稍后重试';
  }

  static List<String> _parseDownloadUrls(dynamic data) {
    final urls = <String>[];
    if (data is! Map<String, dynamic>) return urls;

    final list = data['download_urls'];
    if (list is List) {
      for (final item in list) {
        urls.add(item.toString());
      }
    }

    final single = data['download_url'];
    if (single != null) {
      urls.add(single.toString());
    }
    return urls;
  }

  static List<String> _normalizeDistinctUrls(Iterable<String?> rawUrls) {
    final set = <String>{};
    for (final raw in rawUrls) {
      final normalized = UrlUtils.absolute(raw);
      if (normalized.isEmpty) continue;
      set.add(normalized);
    }
    return set.toList();
  }

  static Future<bool> _saveRemoteFileToAlbum(String url) async {
    final normalizedUrl = UrlUtils.absolute(url);
    if (normalizedUrl.isEmpty) return false;

    final tempFile = await _downloadToTempFile(normalizedUrl);
    try {
      if (_isDesktopPlatform()) {
        return _saveToDesktopDirectory(tempFile);
      }

      final result = await ImageGallerySaver.saveFile(
        tempFile.path,
        isReturnPathOfIOS: true,
      );
      return _isSaveSuccess(result);
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  static Future<File> _downloadToTempFile(String url) async {
    final tempDir = await getTemporaryDirectory();
    final uri = Uri.parse(url);
    final originalName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    final extension = _extractExtension(originalName);
    final fileName =
        'xyq_${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}$extension';
    final file = File('${tempDir.path}/$fileName');
    await HttpClient().dio.download(url, file.path);
    return file;
  }

  static Future<bool> _saveToDesktopDirectory(File tempFile) async {
    try {
      final downloadsDir = await getDownloadsDirectory();
      final targetDir = downloadsDir ?? await getApplicationDocumentsDirectory();
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      final fileName =
          tempFile.uri.pathSegments.isNotEmpty
              ? tempFile.uri.pathSegments.last
              : 'xyq_${DateTime.now().millisecondsSinceEpoch}';
      final targetFile = File('${targetDir.path}/$fileName');
      await tempFile.copy(targetFile.path);
      return await targetFile.exists();
    } catch (_) {
      return false;
    }
  }

  static bool _isDesktopPlatform() {
    if (kIsWeb) return false;
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  static bool _isSaveSuccess(dynamic result) {
    if (result is bool) return result;
    if (result is Map) {
      final map = result.cast<dynamic, dynamic>();
      final rawSuccess = map['isSuccess'] ?? map['success'];
      if (rawSuccess is bool) return rawSuccess;
      if (rawSuccess is num) return rawSuccess > 0;
      if (rawSuccess is String) {
        final lowered = rawSuccess.trim().toLowerCase();
        if (lowered == 'true' || lowered == '1') return true;
      }
      final rawPath = map['filePath'] ?? map['file_path'];
      if (rawPath is String && rawPath.isNotEmpty) return true;
    }
    return false;
  }

  static String _extractExtension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot >= name.length - 1) return '';
    return name.substring(dot).toLowerCase();
  }

  static String _randomSuffix() {
    return DateTime.now().microsecond.toString().padLeft(6, '0');
  }

  static void _showSnack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
