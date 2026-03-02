import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Live Photo 通道
class LivePhotoChannel {
  static const _channel = MethodChannel('com.xiaoyanquan/live_photo');

  /// 请求相册权限 (iOS only)
  static Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 保存 Live Photo 到相册 (iOS only)
  static Future<bool> saveLivePhoto({
    required String imageUrl,
    required String videoUrl,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('saveLivePhoto', {
        'image_url': imageUrl,
        'video_url': videoUrl,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Live Photo 展示组件
/// - iOS: 使用原生 PHLivePhotoView（长按可播放动效）
/// - Android: 静态图片 + Live Photo 角标
class LivePhotoView extends StatelessWidget {
  final String imageUrl;
  final String videoUrl;
  final double? width;
  final double? height;
  final BoxFit fit;

  const LivePhotoView({
    super.key,
    required this.imageUrl,
    required this.videoUrl,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isIOS) {
      return _IOSLivePhotoView(
        imageUrl: imageUrl,
        videoUrl: videoUrl,
        width: width,
        height: height,
      );
    }

    // Android / other platforms: show static image with badge
    return Stack(
      children: [
        CachedNetworkImage(
          imageUrl: imageUrl,
          width: width,
          height: height,
          fit: fit,
          placeholder: (_, __) => Container(
            color: Colors.grey[900],
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (_, __, ___) => Container(
            color: Colors.grey[900],
            child: const Icon(Icons.broken_image, color: Colors.grey),
          ),
        ),
        // Live Photo badge
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.motion_photos_on, size: 14, color: Colors.white),
                SizedBox(width: 4),
                Text('LIVE', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        // Android hint
        if (!kIsWeb && Platform.isAndroid)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Live Photo 仅支持 iPhone 查看动效',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// iOS 原生 PHLivePhotoView 包装
class _IOSLivePhotoView extends StatelessWidget {
  final String imageUrl;
  final String videoUrl;
  final double? width;
  final double? height;

  const _IOSLivePhotoView({
    required this.imageUrl,
    required this.videoUrl,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: UiKitView(
        viewType: 'com.xiaoyanquan/live_photo_view',
        creationParams: {
          'image_url': imageUrl,
          'video_url': videoUrl,
        },
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}
