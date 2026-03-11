import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart' as vt;
import 'package:video_player/video_player.dart';

/// 视频缩略图组件。
/// - Android：使用原生 MediaMetadataRetriever 提取首帧（轻量，无 ANR 风险）
/// - iOS：使用 VideoPlayerController 抓取首帧
class NetworkVideoThumbnail extends StatefulWidget {
  final String videoUrl;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const NetworkVideoThumbnail({
    super.key,
    required this.videoUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  /// Android 上使用原生缩略图提取
  static bool get _useNativeThumbnail => !kIsWeb && Platform.isAndroid;

  /// 内存缓存，避免同一视频重复提取
  static final Map<String, Uint8List> _cache = {};

  @override
  State<NetworkVideoThumbnail> createState() => _NetworkVideoThumbnailState();
}

class _NetworkVideoThumbnailState extends State<NetworkVideoThumbnail> {
  // ===== Android 原生缩略图 =====
  Uint8List? _thumbnailData;
  bool _nativeFailed = false;

  // ===== iOS VideoPlayer =====
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (NetworkVideoThumbnail._useNativeThumbnail) {
      _loadNativeThumbnail();
    } else {
      _initController();
    }
  }

  @override
  void didUpdateWidget(covariant NetworkVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      if (NetworkVideoThumbnail._useNativeThumbnail) {
        _thumbnailData = null;
        _nativeFailed = false;
        _loadNativeThumbnail();
      } else {
        _disposeController();
        _initController();
      }
    }
  }

  // ---------- Android: 原生提取首帧 ----------

  Future<void> _loadNativeThumbnail() async {
    if (widget.videoUrl.isEmpty) return;

    final cached = NetworkVideoThumbnail._cache[widget.videoUrl];
    if (cached != null) {
      if (mounted) setState(() => _thumbnailData = cached);
      return;
    }

    try {
      final data = await vt.VideoThumbnail.thumbnailData(
        video: widget.videoUrl,
        imageFormat: vt.ImageFormat.JPEG,
        maxWidth: 300,
        quality: 75,
      );
      if (!mounted) return;
      if (data != null && data.isNotEmpty) {
        NetworkVideoThumbnail._cache[widget.videoUrl] = data;
        setState(() => _thumbnailData = data);
      } else {
        setState(() => _nativeFailed = true);
      }
    } catch (_) {
      if (mounted) setState(() => _nativeFailed = true);
    }
  }

  // ---------- iOS: VideoPlayerController ----------

  Future<void> _initController() async {
    if (widget.videoUrl.isEmpty) return;
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.seekTo(const Duration(milliseconds: 1));
      await controller.pause();
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

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    // Android: 原生缩略图
    if (NetworkVideoThumbnail._useNativeThumbnail) {
      if (_thumbnailData != null) {
        return Image.memory(
          _thumbnailData!,
          fit: widget.fit,
          gaplessPlayback: true,
        );
      }
      if (_nativeFailed) {
        return widget.errorWidget ?? _defaultError;
      }
      return widget.placeholder ?? _defaultPlaceholder;
    }

    // iOS: VideoPlayer 首帧
    if (_failed) {
      return widget.errorWidget ?? _defaultError;
    }

    if (!_initialized || _controller == null) {
      return widget.placeholder ?? _defaultPlaceholder;
    }

    final size = _controller!.value.size;
    final w = size.width <= 0 ? 1.0 : size.width;
    final h = size.height <= 0 ? 1.0 : size.height;

    return ClipRect(
      child: FittedBox(
        fit: widget.fit,
        child: SizedBox(
          width: w,
          height: h,
          child: VideoPlayer(_controller!),
        ),
      ),
    );
  }

  static const Widget _defaultPlaceholder = ColoredBox(
    color: Colors.black12,
    child: Center(
      child: Icon(
        Icons.play_circle_outline_rounded,
        color: Colors.white70,
        size: 36,
      ),
    ),
  );

  static const Widget _defaultError = ColoredBox(
    color: Colors.black12,
    child: Center(child: Icon(Icons.broken_image_outlined)),
  );
}
