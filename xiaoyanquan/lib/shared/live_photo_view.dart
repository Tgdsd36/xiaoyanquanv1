import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

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
  /// 返回 (success, errorMessage)
  static Future<(bool, String?)> saveLivePhoto({
    required String imageUrl,
    required String videoUrl,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('saveLivePhoto', {
        'image_url': imageUrl,
        'video_url': videoUrl,
      });
      return (result ?? false, null);
    } on PlatformException catch (e) {
      return (false, '[${e.code}] ${e.message ?? e.details ?? "unknown"}');
    } catch (e) {
      return (false, e.toString());
    }
  }
}

/// Live Photo 展示组件
/// - iOS/macOS/Android: 使用 MOV 循环播放模拟 Live 动效
/// - Web: 静态图片 + Live Photo 角标
class LivePhotoView extends StatelessWidget {
  final String imageUrl;
  final String videoUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool isPlaying;

  const LivePhotoView({
    super.key,
    required this.imageUrl,
    required this.videoUrl,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.isPlaying = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS || Platform.isAndroid)) {
      return _VideoLiveMotionView(
        imageUrl: imageUrl,
        videoUrl: videoUrl,
        width: width,
        height: height,
        fit: fit,
        isPlaying: isPlaying,
      );
    }

    return Stack(
      children: [
        CachedNetworkImage(
          imageUrl: imageUrl,
          width: width,
          height: height,
          fit: fit,
          placeholder:
              (_, __) => Container(
                color: Colors.grey[900],
                child: const Center(child: CircularProgressIndicator()),
              ),
          errorWidget:
              (_, __, ___) => Container(
                color: Colors.grey[900],
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
        ),
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
                Text(
                  'LIVE',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// iOS/macOS 上使用 MOV 循环播放模拟 Live 动效
class _VideoLiveMotionView extends StatefulWidget {
  final String imageUrl;
  final String videoUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool isPlaying;

  const _VideoLiveMotionView({
    required this.imageUrl,
    required this.videoUrl,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.isPlaying = true,
  });

  @override
  State<_VideoLiveMotionView> createState() => _VideoLiveMotionViewState();
}

class _VideoLiveMotionViewState extends State<_VideoLiveMotionView> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void didUpdateWidget(covariant _VideoLiveMotionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _disposeController();
      _initController();
      return;
    }
    // 响应 isPlaying 变化：暂停/恢复播放
    if (oldWidget.isPlaying != widget.isPlaying && _initialized && _controller != null) {
      if (widget.isPlaying) {
        _controller!.play();
      } else {
        _controller!.pause();
      }
    }
  }

  Future<void> _initController() async {
    if (widget.videoUrl.isEmpty) return;
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted || _controller != controller) return;
      setState(() {
        _initialized = true;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || _controller != controller) return;
      setState(() {
        _initialized = false;
        _failed = true;
      });
    }
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _initialized = false;
    _failed = false;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || !_initialized || _controller == null) {
      return CachedNetworkImage(
        imageUrl: widget.imageUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        placeholder:
            (_, __) => Container(
              color: Colors.grey[900],
              child: const Center(child: CircularProgressIndicator()),
            ),
        errorWidget:
            (_, __, ___) => Container(
              color: Colors.grey[900],
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
      );
    }

    final size = _controller!.value.size;
    final width = size.width <= 0 ? 1.0 : size.width;
    final height = size.height <= 0 ? 1.0 : size.height;

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: FittedBox(
        fit: widget.fit,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: width,
          height: height,
          child: VideoPlayer(_controller!),
        ),
      ),
    );
  }
}
