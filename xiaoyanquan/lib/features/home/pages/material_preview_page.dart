import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../../shared/live_photo_view.dart';
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
  ConsumerState<MaterialPreviewPage> createState() => _MaterialPreviewPageState();
}

class _MaterialPreviewPageState extends ConsumerState<MaterialPreviewPage> {
  final MaterialRepository _repo = MaterialRepository();

  MaterialDetail? _detail;
  bool _loadingDetail = false;

  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _videoFailed = false;

  late final PageController _pageController;
  int _currentIndex = 0;
  double _overscrollAccum = 0;

  @override
  void initState() {
    super.initState();

    _currentIndex = widget.initialIndex < 0 ? 0 : widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);

    // 沉浸式状态栏
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
    ));

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
        ref.read(materialFavoriteProvider(widget.materialId).notifier).init(
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

  String get _title =>
      widget.titleOverride ?? _detail?.title ?? widget.initialItem?.title ?? '';

  List<String> get _imageUrls {
    // 优先用 detail 的 original_urls（接口已返回 full URL）
    final fromDetail = _detail?.originalUrls ?? const <String>[];
    if (fromDetail.isNotEmpty) {
      return fromDetail.where((e) => e.isNotEmpty).toList();
    }

    // 其次用路由参数传进来的原图列表（从详情九宫格进入）
    final fromWidget = widget.imageUrls ?? const <String>[];
    if (fromWidget.isNotEmpty) {
      return fromWidget.where((e) => e.isNotEmpty).toList();
    }

    // 最后兜底用封面/水印图（用于列表进入时的快速占位）
    final url = _fallbackImageUrl;
    if (url.isNotEmpty) return [url];
    return const <String>[];
  }

  String get _fallbackImageUrl {
    final d = _detail;
    if (d != null) {
      if (!d.isVideo) {
        if (d.originalUrls.isNotEmpty && d.originalUrls.first.isNotEmpty) {
          return d.originalUrls.first;
        }
        if (d.watermarkUrl.isNotEmpty) return d.watermarkUrl;
      }
      if (d.thumbnailUrl.isNotEmpty) return d.thumbnailUrl;
    }

    final i = widget.initialItem;
    if (i != null) {
      if (!i.isVideo && i.watermarkUrl.isNotEmpty) return i.watermarkUrl;
      if (i.thumbnailUrl.isNotEmpty) return i.thumbnailUrl;
    }

    return '';
  }

  String get _bestVideoUrl {
    final d = _detail;
    if (d != null && d.watermarkUrl.isNotEmpty) return d.watermarkUrl;
    final i = widget.initialItem;
    if (i != null && i.watermarkUrl.isNotEmpty) return i.watermarkUrl;
    return '';
  }

  String get _livePhotoImageUrl {
    final d = _detail;
    if (d != null && d.originalUrls.isNotEmpty && d.originalUrls.first.isNotEmpty) {
      return d.originalUrls.first;
    }
    return _fallbackImageUrl;
  }

  void _ensureVideoController() {
    if (!_isVideo) return;

    final url = _bestVideoUrl;
    if (url.isEmpty) return;

    if (_videoController != null && _videoController!.dataSource == url) {
      // 已经初始化过同一个 url
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

    controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _videoInitialized = true);
      controller.setLooping(true);
      controller.play();
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _videoFailed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    final imageCount = _imageUrls.length;
    final showPageIndicator = !_isVideo && !_isLivePhoto && imageCount > 1;

    // 图片列表更新时，确保下标不越界
    if (!_isVideo && !_isLivePhoto && imageCount > 0 && _currentIndex >= imageCount) {
      final newIndex = imageCount - 1;
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
                    icon: const Icon(Icons.arrow_back_ios_rounded,
                        size: 20, color: Colors.white),
                  ),
                ),
                if (showPageIndicator)
                  Positioned(
                    right: 16,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Text(
                        '${_currentIndex + 1} / $imageCount',
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // ========== 中间内容区 ==========
        Expanded(
          child: Center(child: _buildContent()),
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
                    icon: isFavorited
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
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('下载功能即将上线')),
                      );
                    },
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
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right_rounded,
                            size: 20, color: Colors.white),
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

  Future<void> _handleFavorite() async {
    final favState = ref.read(materialFavoriteProvider(widget.materialId));
    final isFavorited = favState?.isFavorited ?? false;

    if (isFavorited) {
      // 已收藏 → 直接取消
      final error = await ref
          .read(materialFavoriteProvider(widget.materialId).notifier)
          .removeFavorite(widget.materialId);
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    } else {
      // 未收藏 → 弹出分组选择
      final groupId = await FavoriteGroupSheet.show(context);
      if (groupId == null || !mounted) return;
      final error = await ref
          .read(materialFavoriteProvider(widget.materialId).notifier)
          .addToGroup(widget.materialId, groupId);
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    }
  }

  Widget _wrapDismissIfNeeded(Widget child) {
    // 图片预览要支持 PageView 横滑，所以不使用 Dismissible（会抢手势）
    if (!_isVideo && !_isLivePhoto) return child;

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
      final d = _detail;
      if (d != null && d.previewMovUrl.isNotEmpty) {
        return LivePhotoView(
          imageUrl: _livePhotoImageUrl,
          videoUrl: d.previewMovUrl,
        );
      }
      return _buildImagePager();
    }

    if (_isVideo) {
      return _buildVideo();
    }

    return _buildImagePager();
  }

  Widget _buildImagePager() {
    final urls = _imageUrls;
    if (urls.isEmpty) {
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
              notification.metrics.pixels <= notification.metrics.minScrollExtent + 0.5;
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
              placeholder: (_, __) => const CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white24,
              ),
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.broken_image, color: Colors.grey, size: 48),
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
              strokeWidth: 2, color: Colors.white54),
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
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: c),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: c, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
