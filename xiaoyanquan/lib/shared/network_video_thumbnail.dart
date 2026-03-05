import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 使用视频首帧作为缩略图展示（不自动播放）。
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

  @override
  State<NetworkVideoThumbnail> createState() => _NetworkVideoThumbnailState();
}

class _NetworkVideoThumbnailState extends State<NetworkVideoThumbnail> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void didUpdateWidget(covariant NetworkVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _disposeController();
      _initController();
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

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return widget.errorWidget ??
          const ColoredBox(
            color: Colors.black12,
            child: Center(child: Icon(Icons.broken_image_outlined)),
          );
    }

    if (!_initialized || _controller == null) {
      return widget.placeholder ??
          const ColoredBox(
            color: Colors.black12,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
    }

    final size = _controller!.value.size;
    final width = size.width <= 0 ? 1.0 : size.width;
    final height = size.height <= 0 ? 1.0 : size.height;

    return ClipRect(
      child: FittedBox(
        fit: widget.fit,
        child: SizedBox(
          width: width,
          height: height,
          child: VideoPlayer(_controller!),
        ),
      ),
    );
  }
}
