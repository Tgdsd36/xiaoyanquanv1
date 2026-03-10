import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../../../core/constants/api.dart';
import '../../../core/network/http_client.dart';
import '../../../core/utils/url_utils.dart';
import '../../../shared/favorite_group_sheet.dart';
import '../../../app/main_scaffold.dart';
import '../../../shared/live_photo_view.dart';
import '../../../shared/material_download_helper.dart';
import '../../home/models/material_model.dart';
import '../../home/repositories/material_repository.dart';

// ==================== Provider ====================

class InspirationState {
  final List<MaterialListItem> items;
  final bool isLoading;
  const InspirationState({this.items = const [], this.isLoading = false});
}

class InspirationNotifier extends StateNotifier<InspirationState> {
  final HttpClient _http = HttpClient();
  final String? type; // null = 推荐(全部), 'video', 'live_photo', 'image'

  InspirationNotifier({this.type}) : super(const InspirationState());

  Future<void> load() async {
    state = InspirationState(items: state.items, isLoading: true);
    try {
      final params = <String, dynamic>{'page_size': 20};
      if (type != null) params['type'] = type;
      final resp = await _http.get(Api.inspirationFeed, params: params);
      if (resp.isSuccess && resp.data is List) {
        final list =
            (resp.data as List)
                .map((e) => MaterialListItem.fromJson(e))
                .toList();
        state = InspirationState(items: [...state.items, ...list]);
      } else {
        state = InspirationState(items: state.items);
      }
    } catch (_) {
      state = InspirationState(items: state.items);
    }
  }

  Future<void> refresh() async {
    state = const InspirationState(isLoading: true);
    try {
      final params = <String, dynamic>{'page_size': 20};
      if (type != null) params['type'] = type;
      final resp = await _http.get(Api.inspirationFeed, params: params);
      if (resp.isSuccess && resp.data is List) {
        final list =
            (resp.data as List)
                .map((e) => MaterialListItem.fromJson(e))
                .toList();
        state = InspirationState(items: list);
      } else {
        state = const InspirationState();
      }
    } catch (_) {
      state = const InspirationState();
    }
  }

  Future<void> dislike(int materialId) async {
    state = InspirationState(
      items: state.items.where((i) => i.id != materialId).toList(),
    );
    try {
      await _http.post(
        Api.inspirationDislike,
        data: {'material_id': materialId},
      );
    } catch (_) {}
  }
}

// 4 个 tab 的 provider，family 模式
final inspirationProvider = StateNotifierProvider.family<
  InspirationNotifier,
  InspirationState,
  String?
>((ref, type) {
  final notifier = InspirationNotifier(type: type);
  notifier.load();
  return notifier;
});

// Tab 定义
class _TabDef {
  final String label;
  final String? type; // null = 全部(推荐)
  const _TabDef(this.label, this.type);
}

const _tabs = [
  _TabDef('Live', 'live_photo'),
  _TabDef('推荐', null),
  _TabDef('视频', 'video'),
  _TabDef('图文', 'image'),
];

const _defaultTabIndex = 1; // 默认"推荐"

// ==================== Page ====================

class InspirationPage extends ConsumerStatefulWidget {
  const InspirationPage({super.key});

  @override
  ConsumerState<InspirationPage> createState() => _InspirationPageState();
}

class _InspirationPageState extends ConsumerState<InspirationPage>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: _defaultTabIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // 内容：TabBarView（可左右滑动）
          TabBarView(
            controller: _tabController,
            children:
                _tabs.map((tab) {
                  return _InspirationFeedView(type: tab.type);
                }).toList(),
          ),
          // 顶部 TabBar（悬浮）
          Positioned(
            top: topPadding + 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.center,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white54,
                  labelStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                  indicator: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerHeight: 0,
                  splashFactory: NoSplash.splashFactory,
                  padding: EdgeInsets.zero,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 16),
                  tabs:
                      _tabs.map((t) => Tab(height: 32, text: t.label)).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 单 Tab 的 Feed 列表 ====================

class _InspirationFeedView extends ConsumerStatefulWidget {
  final String? type;
  const _InspirationFeedView({required this.type});

  @override
  ConsumerState<_InspirationFeedView> createState() =>
      _InspirationFeedViewState();
}

class _InspirationFeedViewState extends ConsumerState<_InspirationFeedView>
    with AutomaticKeepAliveClientMixin {
  final _pageController = PageController();
  int _currentIndex = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(inspirationProvider(widget.type));
    // 监听底部导航 tab 索引，判断找灵感是否是当前活跃 tab
    final isTabActive = ref.watch(activeMainTabProvider) == 1;

    if (state.items.isEmpty) {
      return Center(
        child:
            state.isLoading
                ? const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                )
                : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 48, color: Colors.grey[700]),
                    const SizedBox(height: 12),
                    Text(
                      '暂无推荐',
                      style: TextStyle(color: Colors.grey[600], fontSize: 15),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed:
                          () =>
                              ref
                                  .read(
                                    inspirationProvider(widget.type).notifier,
                                  )
                                  .refresh(),
                      child: const Text('刷新试试'),
                    ),
                  ],
                ),
      );
    }

    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      itemCount: state.items.length,
      onPageChanged: (index) {
        setState(() => _currentIndex = index);
        if (index >= state.items.length - 3) {
          ref.read(inspirationProvider(widget.type).notifier).load();
        }
      },
      itemBuilder: (context, index) {
        final item = state.items[index];
        return _InspirationFullPage(
          item: item,
          isActive: index == _currentIndex && isTabActive,
          onDislike: () {
            ref
                .read(inspirationProvider(widget.type).notifier)
                .dislike(item.id);
          },
        );
      },
    );
  }
}

// ==================== 全屏单页 ====================

class _InspirationFullPage extends StatefulWidget {
  final MaterialListItem item;
  final bool isActive;
  final VoidCallback onDislike;

  const _InspirationFullPage({
    required this.item,
    required this.isActive,
    required this.onDislike,
  });

  @override
  State<_InspirationFullPage> createState() => _InspirationFullPageState();
}

class _InspirationFullPageState extends State<_InspirationFullPage> {
  final MaterialRepository _repo = MaterialRepository();
  VideoPlayerController? _videoController;
  final PageController _imagePageController = PageController();
  Timer? _imageAutoTimer;
  bool _videoInitialized = false;
  bool _videoError = false;
  bool _paused = false;
  bool _togglingFav = false;
  bool _liveEffectEnabled = false;
  int _currentImageIndex = 0;
  List<String> _detailOriginalUrls = const [];
  int? _loadedOriginalForId;
  bool _loadingOriginals = false;
  String _livePreviewMovUrl = '';

  @override
  void initState() {
    super.initState();
    if (widget.item.isVideo && widget.isActive) {
      _initVideo();
    } else if (!widget.item.isVideo && widget.isActive) {
      _maybeLoadOriginalImages();
      _startImageAutoSwitch();
    }
  }

  @override
  void didUpdateWidget(_InspirationFullPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final itemChanged = widget.item.id != oldWidget.item.id;
    final becameActive = widget.isActive && !oldWidget.isActive;
    final becameInactive = !widget.isActive && oldWidget.isActive;

    if (itemChanged) {
      _currentImageIndex = 0;
      _detailOriginalUrls = const [];
      _loadedOriginalForId = null;
      _loadingOriginals = false;
      _livePreviewMovUrl = '';
      _liveEffectEnabled = false;
      if (_imagePageController.hasClients) {
        _imagePageController.jumpToPage(0);
      }
      _stopImageAutoSwitch();
      if (widget.item.isVideo && widget.isActive) {
        _initVideo();
      } else {
        _disposeVideo();
        if (!widget.item.isVideo && widget.isActive) {
          _maybeLoadOriginalImages();
          _startImageAutoSwitch();
        }
      }
      return;
    }

    if (becameActive) {
      if (widget.item.isVideo) {
        _stopImageAutoSwitch();
        if (_videoController != null && _videoInitialized) {
          _videoController!.seekTo(Duration.zero);
          _videoController!.play();
          setState(() => _paused = false);
        } else {
          _initVideo();
        }
      } else {
        _maybeLoadOriginalImages();
        _startImageAutoSwitch();
      }
      return;
    }

    if (becameInactive) {
      _videoController?.pause();
      _stopImageAutoSwitch();
    }
  }

  List<String> get _imageUrls {
    final urls = <String>[];
    void addUrl(String raw) {
      final normalized = UrlUtils.absolute(raw);
      if (normalized.isNotEmpty &&
          !UrlUtils.isVideoUrl(normalized) &&
          !urls.contains(normalized)) {
        urls.add(normalized);
      }
    }

    for (final u in _detailOriginalUrls) {
      addUrl(u);
    }
    for (final u in widget.item.originalUrls) {
      addUrl(u);
    }
    addUrl(widget.item.watermarkUrl);
    return urls;
  }

  void _maybeLoadOriginalImages() {
    if (widget.item.isVideo || !widget.isActive) return;
    if (_loadedOriginalForId == widget.item.id) return;
    _loadOriginalImages();
  }

  Future<void> _loadOriginalImages() async {
    final itemId = widget.item.id;
    if (_loadingOriginals) return;
    setState(() => _loadingOriginals = true);
    try {
      final detail = await _repo.getDetail(itemId);
      if (!mounted || widget.item.id != itemId) return;

      final originals =
          detail?.originalUrls
              .map((e) => UrlUtils.absolute(e))
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[];

      setState(() {
        _loadedOriginalForId = itemId;
        _loadingOriginals = false;
        _livePreviewMovUrl = detail?.previewMovUrl ?? '';
        if (originals.isNotEmpty) {
          _detailOriginalUrls = originals;
          _currentImageIndex = 0;
          if (_imagePageController.hasClients) {
            _imagePageController.jumpToPage(0);
          }
        }
      });
      _startImageAutoSwitch();
    } catch (_) {
      if (!mounted || widget.item.id != itemId) return;
      setState(() {
        _loadedOriginalForId = itemId;
        _loadingOriginals = false;
      });
      _startImageAutoSwitch();
    }
  }

  void _startImageAutoSwitch() {
    _stopImageAutoSwitch();
    if (!widget.isActive || widget.item.isVideo || _imageUrls.length <= 1) {
      return;
    }

    _imageAutoTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !widget.isActive) return;
      final total = _imageUrls.length;
      if (total <= 1) return;
      final next = (_currentImageIndex + 1) % total;
      if (_imagePageController.hasClients) {
        _imagePageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      } else {
        setState(() => _currentImageIndex = next);
      }
    });
  }

  void _stopImageAutoSwitch() {
    _imageAutoTimer?.cancel();
    _imageAutoTimer = null;
  }

  void _disposeVideo() {
    _videoController?.dispose();
    _videoController = null;
    _videoInitialized = false;
    _videoError = false;
    _paused = false;
  }

  void _initVideo() {
    final videoUrl = widget.item.bestVideoUrl;
    if (videoUrl.isEmpty) return;

    _disposeVideo();
    final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
    _videoController = controller;
    controller
        .initialize()
        .then((_) {
          if (!mounted || _videoController != controller) return;
          setState(() {
            _videoInitialized = true;
            _videoError = false;
            _paused = false;
          });
          controller.setLooping(true);
          if (widget.isActive) {
            controller.play();
          }
        })
        .catchError((_) {
          if (!mounted || _videoController != controller) return;
          setState(() => _videoError = true);
        });
  }

  Widget _buildImageCounter() {
    if (widget.item.isLivePhoto && _liveEffectEnabled) {
      return const SizedBox.shrink();
    }
    if (widget.item.isVideo || _imageUrls.isEmpty) {
      return const SizedBox.shrink();
    }
    final total = _imageUrls.length;
    final current = (_currentImageIndex % total) + 1;
    return Positioned(
      top: MediaQuery.of(context).padding.top + 56,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          '$current/$total',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _stopImageAutoSwitch();
    _imagePageController.dispose();
    _disposeVideo();
    super.dispose();
  }

  void _togglePause() {
    if (!widget.item.isVideo || _videoController == null) return;
    setState(() {
      _paused = !_paused;
      if (_paused) {
        _videoController!.pause();
      } else {
        _videoController!.play();
      }
    });
  }

  Future<void> _copyTitle() async {
    final title = widget.item.title.trim();
    if (title.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: title));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('标题已复制')));
  }

  Future<void> _handleDownload() async {
    await MaterialDownloadHelper.downloadToAlbum(
      context,
      materialId: widget.item.id,
      materialType: widget.item.type,
      fallbackUrls: <String>[
        ...widget.item.originalUrls,
        widget.item.watermarkUrl,
        widget.item.thumbnailUrl,
        _livePreviewMovUrl,
      ],
      fallbackVideoUrl: widget.item.bestVideoUrl,
      fallbackLiveVideoUrl: _livePreviewMovUrl,
    );
  }

  String get _mediaTagLabel {
    if (widget.item.isLivePhoto) return '动图';
    if (widget.item.isVideo) return '视频';
    return '图文';
  }

  bool get _supportsLiveMotionDevice =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  String get _liveImageUrl {
    final urls = _imageUrls;
    if (urls.isNotEmpty) return urls.first;
    return widget.item.safeThumbnailUrl;
  }

  void _toggleLiveEffect() {
    if (!widget.item.isLivePhoto) return;
    if (_livePreviewMovUrl.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Live 动态资源未就绪')));
      return;
    }

    final next = !_liveEffectEnabled;
    setState(() => _liveEffectEnabled = next);
    if (next) {
      _stopImageAutoSwitch();
    } else {
      _startImageAutoSwitch();
    }

  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePause,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 内容层
          _buildContent(),
          // Live 开关
          if (widget.item.isLivePhoto)
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              left: 12,
              child: GestureDetector(
                onTap: _toggleLiveEffect,
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _liveEffectEnabled
                        ? Colors.white
                        : Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(16),
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
                        size: 14,
                        color: _liveEffectEnabled ? Colors.black : Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: _liveEffectEnabled ? Colors.black : Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // 图片计数
          _buildImageCounter(),
          // 暂停图标
          if (_paused)
            const Center(
              child: Icon(
                Icons.play_arrow_rounded,
                size: 72,
                color: Colors.white70,
              ),
            ),
          // 底部渐变
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 200,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),
          ),
          // 底部信息
          Positioned(
            left: 16,
            right: 72,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFB5D85), Color(0xFFE13D6E)],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '小颜',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '小颜圈',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              shadows: [
                                Shadow(blurRadius: 8, color: Colors.black54),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _mediaTagLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: _copyTitle,
                        child: Text(
                          widget.item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            shadows: [
                              Shadow(blurRadius: 8, color: Colors.black54),
                            ],
                          ),
                        ),
                      ),
                      if (widget.item.isVideo &&
                          widget.item.durationText.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            widget.item.durationText,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 右侧操作栏
          Positioned(
            right: 12,
            bottom: MediaQuery.of(context).padding.bottom + 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionButton(
                  icon:
                      widget.item.isFavorited
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                  label: _formatCount(widget.item.favoriteCount),
                  color: widget.item.isFavorited ? Colors.orange : Colors.white,
                  onTap: _handleFavorite,
                ),
                const SizedBox(height: 20),
                _ActionButton(
                  icon: Icons.download_rounded,
                  label: _formatCount(widget.item.downloadCount),
                  color: Colors.white,
                  onTap: _handleDownload,
                ),
                const SizedBox(height: 20),
                _ActionButton(
                  icon: Icons.not_interested_rounded,
                  label: '不喜欢',
                  color: Colors.white,
                  onTap: widget.onDislike,
                ),
              ],
            ),
          ),
          // 视频进度条
          if (widget.item.isVideo &&
              _videoInitialized &&
              _videoController != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                _videoController!,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: Colors.white.withValues(alpha: 0.8),
                  bufferedColor: Colors.white.withValues(alpha: 0.3),
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                ),
                padding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (widget.item.isLivePhoto) {
      if (_liveEffectEnabled &&
          _livePreviewMovUrl.isNotEmpty &&
          _liveImageUrl.isNotEmpty) {
        return LivePhotoView(
          imageUrl: _liveImageUrl,
          videoUrl: _livePreviewMovUrl,
          fit: BoxFit.contain,
          isPlaying: widget.isActive,
        );
      }
      return _buildImageContent();
    }

    if (widget.item.isVideo) {
      return _buildVideoContent();
    }
    return _buildImageContent();
  }

  Widget _buildImageContent() {
    final urls = _imageUrls;
    if (_loadingOriginals && urls.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
      );
    }
    if (urls.isEmpty) {
      return const Center(
        child: Icon(Icons.broken_image, color: Colors.grey, size: 48),
      );
    }

    return PageView.builder(
      controller: _imagePageController,
      itemCount: urls.length,
      onPageChanged: (index) {
        if (!mounted) return;
        setState(() => _currentImageIndex = index);
        // 用户手动翻页后暂停自动轮播
        _stopImageAutoSwitch();
      },
      itemBuilder: (context, index) {
        return CachedNetworkImage(
          imageUrl: urls[index],
          fit: BoxFit.contain,
          alignment: Alignment.center,
          placeholder:
              (_, __) => const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white24,
                ),
              ),
          errorWidget:
              (_, __, ___) => const Center(
                child: Icon(Icons.broken_image, color: Colors.grey, size: 48),
              ),
        );
      },
    );
  }

  Widget _buildVideoContent() {
    final thumbnailUrl = widget.item.safeThumbnailUrl;
    if (_videoError) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (thumbnailUrl.isNotEmpty)
            CachedNetworkImage(imageUrl: thumbnailUrl, fit: BoxFit.contain),
          const Center(
            child: Icon(Icons.error_outline, size: 48, color: Colors.white54),
          ),
        ],
      );
    }

    if (!_videoInitialized || _videoController == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (thumbnailUrl.isNotEmpty)
            CachedNetworkImage(imageUrl: thumbnailUrl, fit: BoxFit.contain),
          const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white54,
            ),
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

  Future<void> _handleFavorite() async {
    if (_togglingFav) return;

    if (widget.item.isFavorited) {
      // 已收藏 → 直接取消
      _togglingFav = true;
      final oldFav = widget.item.isFavorited;
      final oldCount = widget.item.favoriteCount;
      setState(() {
        widget.item.isFavorited = false;
        widget.item.favoriteCount = oldCount > 0 ? oldCount - 1 : 0;
      });

      final result = await _repo.toggleFavorite(
        targetType: 'material',
        targetId: widget.item.id,
        groupId: 0,
      );

      if (!mounted) return;
      _togglingFav = false;

      if (result.error == null) {
        setState(() {
          widget.item.isFavorited = result.isFavorited;
          widget.item.favoriteCount = result.favoriteCount;
        });
      } else {
        setState(() {
          widget.item.isFavorited = oldFav;
          widget.item.favoriteCount = oldCount;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.error!)));
      }
    } else {
      // 未收藏 → 弹出分组选择
      final groupId = await FavoriteGroupSheet.show(context);
      if (groupId == null || !mounted) return;

      _togglingFav = true;
      final oldFav = widget.item.isFavorited;
      final oldCount = widget.item.favoriteCount;
      setState(() {
        widget.item.isFavorited = true;
        widget.item.favoriteCount = oldCount + 1;
      });

      final result = await _repo.toggleFavorite(
        targetType: 'material',
        targetId: widget.item.id,
        groupId: groupId,
      );

      if (!mounted) return;
      _togglingFav = false;

      if (result.error == null) {
        setState(() {
          widget.item.isFavorited = result.isFavorited;
          widget.item.favoriteCount = result.favoriteCount;
        });
      } else {
        setState(() {
          widget.item.isFavorited = oldFav;
          widget.item.favoriteCount = oldCount;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.error!)));
      }
    }
  }

  String _formatCount(int count) {
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}w';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '$count';
  }
}

// ==================== 右侧操作按钮 ====================

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 28,
            color: color,
            shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
            ),
          ),
        ],
      ),
    );
  }
}
