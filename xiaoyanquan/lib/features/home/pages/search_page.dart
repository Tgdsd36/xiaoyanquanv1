import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../app/colors.dart';
import '../../../app/styles.dart';
import '../../../shared/network_video_thumbnail.dart';
import '../models/material_model.dart';
import '../repositories/material_repository.dart';

/// 搜索页传参
class SearchArgs {
  final int? categoryId;
  final String? categoryName;

  const SearchArgs({this.categoryId, this.categoryName});
}

class SearchPage extends ConsumerStatefulWidget {
  final SearchArgs? args;

  const SearchPage({super.key, this.args});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _repo = MaterialRepository();

  static const _historyBoxName = 'search_history';
  static const _historyKey = 'recent';
  static const _maxHistory = 10;
  List<String> _history = [];

  List<MaterialListItem> _results = [];
  bool _loading = false;
  bool _hasMore = false;
  int _page = 1;
  String _keyword = '';
  int? _categoryId;
  String _selectedType = ''; // '' = 全部

  static const _typeOptions = [
    {'icon': 'ic_fire', 'label': '全部', 'value': ''},
    {'icon': 'ic_video', 'label': '视频', 'value': 'video'},
    {'icon': 'ic_camera', 'label': '图片', 'value': 'image'},
    {'icon': 'ic_sparkle', 'label': 'Live', 'value': 'live_photo'},
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadHistory();

    // 从分类入口进来
    if (widget.args?.categoryId != null) {
      _categoryId = widget.args!.categoryId;
      _keyword = widget.args!.categoryName ?? '';
      _controller.text = _keyword;
      _doSearch();
    } else {
      _focusNode.requestFocus();
    }
  }

  Future<void> _loadHistory() async {
    final box = await Hive.openBox(_historyBoxName);
    final list = box.get(_historyKey, defaultValue: <dynamic>[]);
    setState(() => _history = List<String>.from(list));
  }

  Future<void> _saveToHistory(String keyword) async {
    _history.remove(keyword);
    _history.insert(0, keyword);
    if (_history.length > _maxHistory) _history = _history.sublist(0, _maxHistory);
    final box = await Hive.openBox(_historyBoxName);
    await box.put(_historyKey, _history);
  }

  Future<void> _clearHistory() async {
    setState(() => _history = []);
    final box = await Hive.openBox(_historyBoxName);
    await box.delete(_historyKey);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _search(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    _saveToHistory(trimmed);
    setState(() {
      _keyword = trimmed;
      _categoryId = null; // 手动搜索时清除分类筛选
    });
    _doSearch();
  }

  Future<void> _doSearch() async {
    setState(() {
      _loading = true;
      _page = 1;
      _results = [];
    });
    try {
      final type = _selectedType.isNotEmpty ? _selectedType : null;

      if (_categoryId != null && _categoryId! > 0) {
        // 分类筛选 → 用 getMaterials
        final result = await _repo.getMaterials(
          page: 1,
          categoryId: _categoryId,
          type: type,
        );
        setState(() {
          _results = result.list;
          _hasMore = result.hasMore;
          _loading = false;
        });
      } else {
        // 关键词搜索
        final result = await _repo.search(
          keyword: _keyword,
          page: 1,
          type: type,
          categoryId: _categoryId,
        );
        setState(() {
          _results = result.list;
          _hasMore = result.hasMore;
          _loading = false;
        });
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final nextPage = _page + 1;
      final type = _selectedType.isNotEmpty ? _selectedType : null;

      late final ({List<MaterialListItem> list, int total, bool hasMore})
      result;
      if (_categoryId != null && _categoryId! > 0) {
        result = await _repo.getMaterials(
          page: nextPage,
          categoryId: _categoryId,
          type: type,
        );
      } else {
        result = await _repo.search(
          keyword: _keyword,
          page: nextPage,
          type: type,
          categoryId: _categoryId,
        );
      }
      setState(() {
        _results = [..._results, ...result.list];
        _hasMore = result.hasMore;
        _page = nextPage;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _onTypeChanged(String type) {
    if (type == _selectedType) return;
    setState(() => _selectedType = type);
    _doSearch();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 52,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Container(
          height: 36,
          margin: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: '搜索素材',
              hintStyle: const TextStyle(
                fontSize: 13,
                color: AppColors.textDisabled,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 18,
                color: AppColors.textDisabled,
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
              suffixIcon:
                  _controller.text.isNotEmpty
                      ? GestureDetector(
                        onTap: () {
                          _controller.clear();
                          setState(() {
                            _results = [];
                            _keyword = '';
                            _categoryId = null;
                          });
                        },
                        child: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: AppColors.textDisabled,
                        ),
                      )
                      : null,
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          // 类型筛选 Tab
          if (_keyword.isNotEmpty || _categoryId != null)
            _TypeTabBar(selectedType: _selectedType, onChanged: _onTypeChanged),
          // 内容区
          Expanded(child: _buildBody(primary)),
        ],
      ),
    );
  }

  Widget _buildBody(Color primary) {
    if (_keyword.isEmpty && _categoryId == null) {
      return _buildHistoryView(primary);
    }
    final mq = MediaQuery.of(context);
    final thumbCacheW = ((mq.size.width - 18) / 2 * mq.devicePixelRatio).round().clamp(100, 600);

    if (_loading && _results.isEmpty) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: primary),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: AppColors.textDisabled,
            ),
            SizedBox(height: 8),
            Text(
              '没有找到相关素材',
              style: TextStyle(color: AppColors.textHint, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      controller: _scrollController,
      cacheExtent: 800,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 0.68,
      ),
      padding: const EdgeInsets.all(6),
      itemCount: _results.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _results.length) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: primary,
                ),
              ),
            ),
          );
        }
        final item = _results[index];
        return _SearchResultCard(
          item: item,
          thumbCacheWidth: thumbCacheW,
          onTap:
              () => context.push('/material/${item.id}/preview', extra: item),
        );
      },
    );
  }

  Widget _buildHistoryView(Color primary) {
    if (_history.isEmpty) {
      return const Center(
        child: Text(
          '输入关键词搜索素材',
          style: TextStyle(color: AppColors.textDisabled, fontSize: 14),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '最近搜索',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _clearHistory,
                child: const Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _history.map((kw) {
              return GestureDetector(
                onTap: () {
                  _controller.text = kw;
                  _search(kw);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    kw,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ==================== 类型筛选栏 ====================

class _TypeTabBar extends StatelessWidget {
  final String selectedType;
  final ValueChanged<String> onChanged;

  const _TypeTabBar({required this.selectedType, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          for (final opt in _SearchPageState._typeOptions)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _buildChip(
                context,
                iconName: opt['icon']!,
                label: opt['label']!,
                isSelected: opt['value'] == selectedType,
                primary: primary,
                onTap: () => onChanged(opt['value']!),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChip(
    BuildContext context, {
    required String iconName,
    required String label,
    required bool isSelected,
    required Color primary,
    required VoidCallback onTap,
  }) {
    final iconColor = isSelected ? primary : AppColors.textHint;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color:
              isSelected ? primary.withValues(alpha: 0.1) : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                isSelected
                    ? primary.withValues(alpha: 0.3)
                    : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/icons/$iconName.svg',
              width: 12,
              height: 12,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            ),
            const SizedBox(width: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? primary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 搜索结果卡片 ====================

class _SearchResultCard extends StatelessWidget {
  final MaterialListItem item;
  final VoidCallback onTap;
  final int thumbCacheWidth;

  const _SearchResultCard({
    required this.item,
    required this.onTap,
    this.thumbCacheWidth = 400,
  });

  static final _kCardRadius = BorderRadius.circular(14);

  @override
  Widget build(BuildContext context) {
    final coverUrl = item.safeThumbnailUrl;
    final videoCoverUrl = item.bestVideoUrl;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: AppStyles.cardDecoration,
        child: ClipRRect(
          borderRadius: _kCardRadius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    coverUrl.isNotEmpty
                        ? CachedNetworkImage(
                          imageUrl: coverUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: thumbCacheWidth,
                          fadeInDuration: Duration.zero,
                          placeholder:
                              (_, __) => Container(color: AppColors.shimmer),
                          errorWidget:
                              (_, __, ___) => Container(
                                color: AppColors.shimmer,
                                child: const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: AppColors.textDisabled,
                                    size: 28,
                                  ),
                                ),
                              ),
                        )
                        : (item.isVideo && videoCoverUrl.isNotEmpty)
                        ? NetworkVideoThumbnail(
                          videoUrl: videoCoverUrl,
                          fit: BoxFit.cover,
                          placeholder: Container(
                            color: AppColors.shimmer,
                            child: const Center(
                              child: Icon(
                                Icons.play_circle_outline_rounded,
                                color: AppColors.textDisabled,
                                size: 30,
                              ),
                            ),
                          ),
                          errorWidget: Container(
                            color: AppColors.shimmer,
                            child: const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: AppColors.textDisabled,
                                size: 28,
                              ),
                            ),
                          ),
                        )
                        : Container(
                          color: AppColors.shimmer,
                          child: Center(
                            child: Icon(
                              item.isVideo
                                  ? Icons.play_circle_outline_rounded
                                  : Icons.image_outlined,
                              color: AppColors.textDisabled,
                              size: 30,
                            ),
                          ),
                        ),
                    // 类型标签（左上角）
                    Positioned(
                      left: 6,
                      top: 6,
                      child: AppStyles.typeBadge(
                        isVideo: item.isVideo,
                        isLivePhoto: item.isLivePhoto,
                      ),
                    ),
                    // 视频时长（右下角）
                    if (item.isVideo && item.durationText.isNotEmpty)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.play_circle_fill_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              item.durationText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 30,
                      child: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 12,
                          color: AppColors.favoriteActive,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${item.favoriteCount}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textHint,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.file_download_outlined,
                          size: 12,
                          color: AppColors.textDisabled,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${item.downloadCount}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
