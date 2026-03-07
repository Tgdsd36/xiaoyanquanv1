import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../../core/utils/url_utils.dart';
import '../../../shared/live_photo_view.dart';
import '../../../shared/material_download_helper.dart';
import '../models/material_model.dart';
import '../../../shared/favorite_group_sheet.dart';
import '../providers/favorite_provider.dart';
import '../repositories/material_repository.dart';

/// 预览页路由参数（GoRouter extra）
class MaterialPreviewArgs {
  final MaterialListItem? initialItem;
  final List<String>? imageUrls;
  final int initialIndex;
  final String? title;

  const MaterialPreviewArgs({
    this.initialItem,
    this.imageUrls,
    this.initialIndex = 0,
    this.title,
  });
}

/// 朋友圈式预览：先沉浸式看图/视频，右下角「详情」再进入详情页。
/// - 不支持双指缩放
/// - 视频进入后自动播放
/// - 右滑（从左往右）可关闭预览（图片在第一页右滑回弹触发关闭）
class MaterialPreviewPage extends ConsumerStatefulWidget {
  final int materialId;
  final MaterialListItem? initialItem;

  /// 可选：直接传入原图列表（用于从详情九宫格进入，避免等待 detail 请求）
  final List<String>? imageUrls;

  /// 图片预览初始下标
  final int initialIndex;

  /// 可选：标题覆盖（避免等待 detail 请求）
  final String? titleOverride;

  const MaterialPreviewPage({
    super.key,
    required this.materialId,
    this.initialItem,
    this.imageUrls,
    this.initialIndex = 0,
    this.titleOverride,
  });

  @override
  ConsumerState<MaterialPreviewPage> createState() =>
      _MaterialPreviewPageState();
}

class _MaterialPreviewPageState extends ConsumerState<MaterialPreviewPage> {
  final MaterialRepository _repo = MaterialRepository();

  MaterialDetail? _detail;
  bool _loadingDetail = false;

  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _videoFailed = false;
  bool _videoPaused = false;
  bool _liveEffectEnabled = false;

  late final PageController _pageController;
  int _currentIndex = 0;
  double _overscrollAccum = 0;

  @override
  void initState() {
    super.initState();

    _currentIndex = widget.initialIndex < 0 ? 0 : widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);

    // 沉浸式状态栏
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    _loadDetail();
    _ensureVideoController();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    if (widget.materialId <= 0) return;
    setState(() => _loadingDetail = true);
    try {
      final detail = await _repo.getDetail(widget.materialId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loadingDetail = false;
      });
      if (detail != null) {
        ref
            .read(materialFavoriteProvider(widget.materialId).notifier)
            .init(
              isFavorited: detail.isFavorited,
              favoriteCount: detail.favoriteCount,
            );
      }
      _ensureVideoController();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDetail = false);
    }
  }

  bool get _isVideo => _detail?.isVideo ?? widget.initialItem?.isVideo ?? false;

  bool get _isLivePhoto =>
      _detail?.isLivePhoto ?? widget.initialItem?.isLivePhoto ?? false;

  bool get _supportsLiveMotionDevice =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  String get _title =>
      widget.titleOverride ?? _detail?.title ?? widget.initialItem?.title ?? '';

  List<String> get _imageUrls {
    // 优先用 detail 的 original_urls（接口已返回 full URL）
    final fromDetail = _detail?.originalUrls ?? const <String>[];
    if (fromDetail.isNotEmpty) {
      return fromDetail
          .where((e) => e.isNotEmpty && !UrlUtils.isVideoUrl(e))
          .toList();
    }

    // 其次用路由参数传进来的原图列表（从详情九宫格进入）
    final fromWidget = widget.imageUrls ?? const <String>[];
    if (fromWidget.isNotEmpty) {
      return fromWidget
          .where((e) => e.isNotEmpty && !UrlUtils.isVideoUrl(e))
          .toList();
    }

    // 最后兜底用封面/水印图（用于列表进入时的快速占位）
    final url = _fallbackImageUrl;
    if (url.isNotEmpty) return [url];
    return const <String>[];
  }

  String get _fallbackImageUrl {
    final d = _detail;
    if (d != null) {
      if (d.safeThumbnailUrl.isNotEmpty) return d.safeThumbnailUrl;
    }

    final i = widget.initialItem;
    if (i != null) {
      if (i.safeThumbnailUrl.isNotEmpty) return i.safeThumbnailUrl;
    }

    return '';
  }

  String get _bestVideoUrl {
    final d = _detail;
    if (d != null && d.bestVideoUrl.isNotEmpty) return d.bestVideoUrl;
    final i = widget.initialItem;
    if (i != null && i.bestVideoUrl.isNotEmpty) return i.bestVideoUrl;
    return '';
  }

  /// 视频类型素材的所有视频 URL
  List<String> get _videoUrls {
    final fromDetail = _detail?.originalUrls ?? const <String>[];
    if (fromDetail.isNotEmpty) {
      final videos = fromDetail
          .where((e) => e.isNotEmpty && UrlUtils.isVideoUrl(e))
          .toList();
      if (videos.isNotEmpty) return videos;
    }
    // 兜底：使用 bestVideoUrl
    final best = _bestVideoUrl;
    if (best.isNotEmpty) return [best];
    return const <String>[];
  }

  /// 从 originalUrls + previewMovUrl 提取所有视频 URL（与 _imageUrls 按索引配对）
  List<String> get _liveVideoUrls {
    final fromDetail = _detail?.originalUrls ?? const <String>[];
    final videos = fromDetail
        .where((e) => e.isNotEmpty && UrlUtils.isVideoUrl(e))
        .toList();
    // 确保 previewMovUrl 也包含在内
    final mov = _detail?.previewMovUrl ?? '';
    if (mov.isNotEmpty && !videos.contains(mov)) {
      videos.insert(0, mov);
    }
    return videos;
  }

  void _ensureVideoController() {
    if (!_isVideo) return;

    final urls = _videoUrls;
    final url = _currentIndex < urls.length ? urls[_currentIndex] : _bestVideoUrl;
    if (url.isEmpty) return;

    if (_videoController != null && _videoController!.dataSource == url) {
      if (_videoInitialized) {
        _videoController!.play();
      }
      return;
    }

    _videoController?.dispose();
    _videoController = null;
    _videoInitialized = false;
    _videoFailed = false;

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _videoController = controller;

    controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => _videoInitialized = true);
          controller.setLooping(true);
          controller.play();
        })
        .catchError((_) {
          if (!mounted) return;
          setState(() => _videoFailed = true);
        });
  }

  void _onVideoPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _videoPaused = false;
    });
    _ensureVideoController();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    final imageCount = _imageUrls.length;
    final videoCount = _videoUrls.length;
    final pageCount = _isVideo ? videoCount : imageCount;
    final showPageIndicator = pageCount > 1;

    // 列表更新时，确保下标不越界
    if (pageCount > 0 && _currentIndex >= pageCount) {
      final newIndex = pageCount - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pageController.jumpToPage(newIndex);
        setState(() => _currentIndex = newIndex);
      });
    }

    final favState = ref.watch(materialFavoriteProvider(widget.materialId));
    final isFavorited = favState?.isFavorited ?? false;

    final content = Column(
      children: [
        // ========== 顶部导航栏 ==========
        Container(
          color: Colors.black,
          padding: EdgeInsets.only(top: topPadding),
          child: SizedBox(
            height: 44,
            child: Stack(
              children: [
                // 返回按钮
                Positioned(
                  left: 4,
                  top: 0,
                  bottom: 0,
                  child: IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (_isLivePhoto)
                  Positioned(
                    left: 48,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: _toggleLiveEffect,
                        child: Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _liveEffectEnabled
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.55),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.motion_photos_on,
                                size: 15,
                                color: _liveEffectEnabled
                                    ? Colors.black
                                    : Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'LIVE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _liveEffectEnabled
                                      ? Colors.black
                                      : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (showPageIndicator)
                  Positioned(
                    right: 16,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Text(
                        '${_currentIndex + 1} / $pageCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // ========== 中间内容区 ==========
        Expanded(
          child: GestureDetector(
            onTap: _toggleVideoPause,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(child: _buildContent()),
                if (_isVideo && _videoPaused)
                  const Icon(
                    Icons.play_arrow_rounded,
                    size: 72,
                    color: Colors.white70,
                  ),
              ],
            ),
          ),
        ),
        // ========== 底部操作栏 ==========
        Container(
          color: Colors.black,
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题
              if (_title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              // 操作按钮行
              Row(
                children: [
                  // ☆ 收藏
                  _BottomAction(
                    icon:
                        isFavorited
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                    label: isFavorited ? '已收藏' : '收藏',
                    color: isFavorited ? Colors.orange : null,
                    onTap: _handleFavorite,
                  ),
                  const SizedBox(width: 24),
                  // ⤓ 下载
                  _BottomAction(
                    icon: Icons.file_download_outlined,
                    label: '下载',
                    onTap: _handleDownload,
                  ),
                  const Spacer(),
                  // 详情 >
                  GestureDetector(
                    onTap: () => context.push('/material/${widget.materialId}'),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '详情',
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                        SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: _wrapDismissIfNeeded(content),
    );
  }

  void _toggleVideoPause() {
    if (!_isVideo || _videoController == null || !_videoInitialized) return;
    setState(() {
      _videoPaused = !_videoPaused;
      if (_videoPaused) {
        _videoController!.pause();
      } else {
        _videoController!.play();
      }
    });
  }

  Future<void> _handleFavorite() async {
    final favState = ref.read(materialFavoriteProvider(widget.materialId));
    final isFavorited = favState?.isFavorited ?? false;

    if (isFavorited) {
      // 已收藏 → 直接取消
      final error = await ref
          .read(materialFavoriteProvider(widget.materialId).notifier)
          .removeFavorite(widget.materialId);
      if (error != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    } else {
      // 未收藏 → 弹出分组选择
      final groupId = await FavoriteGroupSheet.show(context);
      if (groupId == null || !mounted) return;
      final error = await ref
          .read(materialFavoriteProvider(widget.materialId).notifier)
          .addToGroup(widget.materialId, groupId);
      if (error != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    }
  }

  Future<void> _handleDownload() async {
    final detail = _detail;
    final item = widget.initialItem;
    final fallbackUrls = <String>[
      if (detail != null) ...detail.originalUrls,
      if (detail != null) detail.watermarkUrl,
      if (detail != null) detail.thumbnailUrl,
      if (detail != null) detail.previewMovUrl,
      if (item != null) ...item.originalUrls,
      if (item != null) item.watermarkUrl,
      if (item != null) item.thumbnailUrl,
    ];

    await MaterialDownloadHelper.downloadToAlbum(
      context,
      materialId: widget.materialId,
      materialType: detail?.type ?? item?.type ?? '',
      fallbackUrls: fallbackUrls,
      fallbackVideoUrl: _bestVideoUrl,
      fallbackLiveVideoUrl: detail?.previewMovUrl ?? '',
    );
  }

  Widget _wrapDismissIfNeeded(Widget child) {
    // 多页内容（图片/Live/多视频）使用 PageView 横滑，不用 Dismissible
    if (!_isVideo || _videoUrls.length > 1) {
      return child;
    }

    // 单视频才用 Dismissible
    return Dismissible(
      key: ValueKey('material-preview-${widget.materialId}'),
      direction: DismissDirection.startToEnd,
      onDismissed: (_) => context.pop(),
      background: const ColoredBox(color: Colors.black),
      child: child,
    );
  }

  Widget _buildContent() {
    if (_isLivePhoto) {
      if (!_liveEffectEnabled) {
        return _buildImagePager();
      }
      return _buildLivePhotoPager();
    }

    if (_isVideo) {
      final urls = _videoUrls;
      if (urls.length > 1) {
        return _buildVideoPager(urls);
      }
      return _buildVideo();
    }

    return _buildImagePager();
  }

  /// 多视频 PageView，每页一个视频播放器（共享 _videoController）
  Widget _buildVideoPager(List<String> urls) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification ||
            notification is ScrollEndNotification) {
          _overscrollAccum = 0;
        }
        if (notification is OverscrollNotification) {
          final isAtStart =
              notification.metrics.pixels <=
              notification.metrics.minScrollExtent + 0.5;
          if (isAtStart && _currentIndex == 0 && notification.overscroll < 0) {
            _overscrollAccum += notification.overscroll;
            if (_overscrollAccum.abs() > 80) {
              context.pop();
            }
          }
        }
        return false;
      },
      child: PageView.builder(
        controller: _pageController,
        itemCount: urls.length,
        onPageChanged: _onVideoPageChanged,
        itemBuilder: (context, index) {
          // 只有当前页使用真正的视频播放器，其他页显示占位
          if (index == _currentIndex) {
            return _buildVideo();
          }
          // 非当前页显示封面占位
          return Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_fallbackImageUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: _fallbackImageUrl,
                    fit: BoxFit.contain,
                  ),
                Icon(
                  Icons.play_circle_fill_rounded,
                  size: 64,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Live Photo 动效模式的 PageView，每页一个 LivePhotoView
  Widget _buildLivePhotoPager() {
    final images = _imageUrls;
    final videos = _liveVideoUrls;
    final count = images.length;

    if (count == 0) {
      return _loadingDetail
          ? const CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)
          : const Icon(Icons.broken_image, color: Colors.grey, size: 48);
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification ||
            notification is ScrollEndNotification) {
          _overscrollAccum = 0;
        }
        if (notification is OverscrollNotification) {
          final isAtStart =
              notification.metrics.pixels <=
              notification.metrics.minScrollExtent + 0.5;
          if (isAtStart && _currentIndex == 0 && notification.overscroll < 0) {
            _overscrollAccum += notification.overscroll;
            if (_overscrollAccum.abs() > 80) {
              context.pop();
            }
          }
        }
        return false;
      },
      child: PageView.builder(
        controller: _pageController,
        itemCount: count,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (context, index) {
          final imageUrl = index < images.length ? images[index] : '';
          final videoUrl = index < videos.length ? videos[index] : '';
          if (videoUrl.isNotEmpty) {
            return LivePhotoView(
              imageUrl: imageUrl,
              videoUrl: videoUrl,
            );
          }
          // 没有视频的 pack 显示静态图
          if (imageUrl.isNotEmpty) {
            return Center(
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                placeholder: (_, __) => const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white24,
                ),
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.broken_image, color: Colors.grey, size: 48),
              ),
            );
          }
          return const Icon(Icons.broken_image, color: Colors.grey, size: 48);
        },
      ),
    );
  }

  void _toggleLiveEffect() {
    if (!_isLivePhoto) return;
    // 检查是否有任何可用的 Live 视频
    final hasAnyVideo = _liveVideoUrls.any((v) => v.isNotEmpty);
    if (!hasAnyVideo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Live 动态资源未就绪，请稍后重试')),
      );
      return;
    }

    final next = !_liveEffectEnabled;
    setState(() => _liveEffectEnabled = next);

    if (next && !_supportsLiveMotionDevice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前设备仅展示静态图，Live 动效要在 iPhone 或 Mac 上查看')),
      );
    }
  }

  Widget _buildImagePager() {
    final urls = _imageUrls;
    if (urls.isEmpty) {
      return _loadingDetail
          ? const CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white54,
          )
          : const Icon(Icons.broken_image, color: Colors.grey, size: 48);
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification ||
            notification is ScrollEndNotification) {
          _overscrollAccum = 0;
        }

        if (notification is OverscrollNotification) {
          final isAtStart =
              notification.metrics.pixels <=
              notification.metrics.minScrollExtent + 0.5;
          // 只在第一页向右回弹时触发关闭
          if (isAtStart && _currentIndex == 0 && notification.overscroll < 0) {
            _overscrollAccum += notification.overscroll;
            if (_overscrollAccum.abs() > 80) {
              context.pop();
            }
          }
        }

        return false;
      },
      child: PageView.builder(
        controller: _pageController,
        itemCount: urls.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (context, index) {
          final url = urls[index];
          return Center(
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              placeholder:
                  (_, __) => const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white24,
                  ),
              errorWidget:
                  (_, __, ___) => const Icon(
                    Icons.broken_image,
                    color: Colors.grey,
                    size: 48,
                  ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVideo() {
    if (_videoFailed) {
      return Stack(
        alignment: Alignment.center,
        children: [
          if (_fallbackImageUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: _fallbackImageUrl,
              fit: BoxFit.contain,
            ),
          const Icon(Icons.error_outline, size: 48, color: Colors.white54),
        ],
      );
    }

    if (!_videoInitialized || _videoController == null) {
      return Stack(
        alignment: Alignment.center,
        children: [
          if (_fallbackImageUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: _fallbackImageUrl,
              fit: BoxFit.contain,
            ),
          const CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white54,
          ),
        ],
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: VideoPlayer(_videoController!),
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _BottomAction({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: c, fontSize: 14)),
        ],
      ),
    );
  }
}
