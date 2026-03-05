import 'dart:async';
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
    final progress = _DownloadProgressController();
    progress.update('正在准备下载...');
    _showDownloadProgressDialog(context, progress);

    bool canceledByUser = false;

    try {
      progress.update('正在获取下载地址...');
      final downloadData = await _requestDownloadData(materialId);
      if (progress.isCanceled) {
        canceledByUser = true;
        return false;
      }
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

      final bool saved;
      String successMessage = '下载成功，已保存到系统相册';
      if (_isDesktopPlatform()) {
        successMessage = '下载成功，已保存到本机下载目录';
      }

      if (kind == _DownloadKind.livePhoto && Platform.isIOS) {
        progress.update('正在下载实况...');
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
        if (progress.isCanceled) {
          canceledByUser = true;
          return false;
        }
        successMessage = 'Live Photo 已保存到 iPhone 相册';
      } else if (kind == _DownloadKind.video) {
        progress.update('正在下载视频...');
        final videoUrl = UrlUtils.firstVideoUrl(mergedUrls);
        if (videoUrl.isEmpty) {
          if (!context.mounted) return false;
          _showSnack(context, '未获取到可下载的视频地址');
          return false;
        }
        saved = await _saveRemoteFileToAlbum(
          videoUrl,
          cancelToken: progress.cancelToken,
        );
        if (progress.isCanceled) {
          canceledByUser = true;
          return false;
        }
      } else {
        // 图片与非 iOS 设备的 Live 素材，统一保存静态图；图片素材会逐张下载。
        final imageUrls =
            mergedUrls.where((url) => !UrlUtils.isVideoUrl(url)).toList();
        if (imageUrls.isEmpty) {
          if (!context.mounted) return false;
          _showSnack(context, '未获取到可下载的图片地址');
          return false;
        }

        var successCount = 0;
        final total = imageUrls.length;
        final label = kind == _DownloadKind.livePhoto ? '实况' : '图片';
        for (var i = 0; i < total; i++) {
          if (progress.isCanceled) {
            canceledByUser = true;
            break;
          }
          progress.update('正在下载$label ${i + 1}/$total...');
          final ok = await _saveRemoteFileToAlbum(
            imageUrls[i],
            cancelToken: progress.cancelToken,
          );
          if (progress.isCanceled) {
            canceledByUser = true;
            break;
          }
          if (ok) {
            successCount += 1;
          }
        }

        if (canceledByUser) return false;
        if (successCount <= 0) {
          saved = false;
        } else {
          saved = successCount == total;
          if (successCount < total && context.mounted) {
            _showSnack(context, '已下载 $successCount/$total 张，部分图片下载失败');
          }
        }

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
    } on DioException catch (e) {
      if (CancelToken.isCancel(e) || progress.isCanceled) {
        canceledByUser = true;
        return false;
      }
      if (!context.mounted) return false;
      _showSnack(context, _extractDioMessage(e));
      return false;
    } catch (_) {
      if (progress.isCanceled) {
        canceledByUser = true;
        return false;
      }
      if (!context.mounted) return false;
      _showSnack(context, '下载失败，请检查网络后重试');
      return false;
    } finally {
      progress.close();
      progress.dispose();
      if (canceledByUser && context.mounted) {
        _showSnack(context, '已结束下载');
      }
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
    if (data is Map) {
      final msg = (data['message'] ?? '').toString().trim();
      if (msg.isNotEmpty) return msg;
    }
    if (data is String) {
      final msg = data.trim();
      if (msg.isNotEmpty && !msg.startsWith('<')) return msg;
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return '下载失败，请检查网络后重试';
    }
    if (e.message != null && e.message!.trim().isNotEmpty) {
      return e.message!.trim();
    }
    return '下载失败，请稍后重试';
  }

  static List<String> _parseDownloadUrls(dynamic data) {
    final urls = <String>[];
    if (data is! Map) return urls;

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

  static Future<bool> _saveRemoteFileToAlbum(
    String url, {
    CancelToken? cancelToken,
  }) async {
    final normalizedUrl = UrlUtils.absolute(url);
    if (normalizedUrl.isEmpty) return false;

    final tempFile = await _downloadToTempFile(
      normalizedUrl,
      cancelToken: cancelToken,
    );
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

  static Future<File> _downloadToTempFile(
    String url, {
    CancelToken? cancelToken,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final uri = Uri.parse(url);
    final originalName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    final extension = _extractExtension(originalName);
    final fileName =
        'xyq_${DateTime.now().millisecondsSinceEpoch}_${_randomSuffix()}$extension';
    final file = File('${tempDir.path}/$fileName');
    await HttpClient().dio.download(url, file.path, cancelToken: cancelToken);
    return file;
  }

  static void _showDownloadProgressDialog(
    BuildContext context,
    _DownloadProgressController controller,
  ) {
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) {
          controller.attach(dialogContext);
          return PopScope<void>(
            canPop: false,
            onPopInvokedWithResult: (didPop, __) {
              if (!didPop) {
                controller.cancelAndClose();
              }
            },
            child: Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 36,
                vertical: 24,
              ),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(minHeight: 116, maxWidth: 560),
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(
                            strokeWidth: 3.2,
                            color: Color(0xFFFF3B5C),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: ValueListenableBuilder<String>(
                            valueListenable: controller.message,
                            builder: (_, value, __) {
                              return Text(
                                value,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2F2F2F),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF2F2F2F),
                          textStyle: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: controller.cancelAndClose,
                        child: const Text('结束下载'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
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

class _DownloadProgressController {
  final CancelToken cancelToken = CancelToken();
  final ValueNotifier<String> message = ValueNotifier<String>('正在准备下载...');

  BuildContext? _dialogContext;
  bool _closed = false;

  bool get isCanceled => cancelToken.isCancelled;

  void attach(BuildContext context) {
    _dialogContext = context;
  }

  void update(String text) {
    if (_closed) return;
    message.value = text;
  }

  void cancelAndClose() {
    if (!cancelToken.isCancelled) {
      cancelToken.cancel('user canceled');
    }
    close();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    final ctx = _dialogContext;
    if (ctx != null && ctx.mounted) {
      Navigator.of(ctx, rootNavigator: true).pop();
    }
  }

  void dispose() {
    message.dispose();
  }
}
