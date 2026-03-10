import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../app/colors.dart';
import '../../../app/styles.dart';
import '../../../shared/network_video_thumbnail.dart';
import '../models/material_model.dart';
import '../providers/home_provider.dart';
import '../providers/favorite_provider.dart';
import '../widgets/category_sheet.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _scrollController = ScrollController();
  int _thumbCacheWidth = 400;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(materialListProvider.notifier).loadMore();
    }
  }

  void _showCategorySheet(BuildContext context) {
    final categories = ref.read(categoriesProvider).valueOrNull ?? [];
    CategorySheet.show(context, categories: categories);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    _thumbCacheWidth = ((mq.size.width - 18) / 2 * mq.devicePixelRatio).round().clamp(100, 600);
    final primary = Theme.of(context).colorScheme.primary;
    final categoriesAsync = ref.watch(categoriesProvider);
    final selectedType = ref.watch(selectedTypeProvider);
    final selectedGender = ref.watch(selectedGenderProvider);
    final sortType = ref.watch(sortTypeProvider);
    final materialState = ref.watch(materialListProvider);

    return Scaffold(
      // ========== AppBar ==========
      appBar: AppBar(
        toolbarHeight: 52,
        titleSpacing: 16,
        title: Row(
          children: [
            GestureDetector(
              onTap: () => _showCategorySheet(context),
              child: Icon(Icons.grid_view_rounded, size: 26, color: primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: GestureDetector(
                onTap: () => context.push('/search'),
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: AppColors.textDisabled,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '搜索素材',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textDisabled,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: const [],
        elevation: 0,
      ),
      // ========== Body ==========
      body: Column(
        children: [
          // ========== 筛选栏 ==========
          categoriesAsync.when(
            data: (categories) {
              const typeOptions = [
                {'icon': 'ic_fire', 'label': '全部', 'value': ''},
                {'icon': 'ic_video', 'label': '视频', 'value': 'video'},
                {'icon': 'ic_camera', 'label': '图片', 'value': 'image'},
                {'icon': 'ic_sparkle', 'label': 'Live', 'value': 'live_photo'},
              ];

              // 性别选项（固定）
              const genderOptions = [
                {'label': '不限', 'value': '', 'icon': ''},
                {'label': '男', 'value': 'male', 'icon': 'ic_male'},
                {'label': '女', 'value': 'female', 'icon': 'ic_female'},
              ];

              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  children: [
                    // 第一行：类型 Chips + 性别 Chips
                    SizedBox(
                      height: 34,
                      child: Row(
                        children: [
                          // 左侧：类型筛选
                          Expanded(
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: typeOptions.length,
                              separatorBuilder:
                                  (_, __) => const SizedBox(width: 4),
                              itemBuilder: (context, index) {
                                final opt = typeOptions[index];
                                final isSelected = opt['value'] == selectedType;
                                return _FilterChip(
                                  iconName: opt['icon']!,
                                  label: opt['label']!,
                                  isSelected: isSelected,
                                  onTap: () {
                                    ref
                                        .read(selectedTypeProvider.notifier)
                                        .state = opt['value']!;
                                    ref
                                        .read(materialListProvider.notifier)
                                        .updateFilters(type: opt['value']);
                                  },
                                );
                              },
                            ),
                          ),
                          // 右侧：性别筛选
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Container(
                              width: 1,
                              height: 18,
                              color: AppColors.divider,
                            ),
                          ),
                          ...genderOptions.map((opt) {
                            final isGenderSelected =
                                opt['value'] == selectedGender;
                            return Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child:
                                  opt['icon']!.isNotEmpty
                                      ? _FilterChip(
                                        iconName: opt['icon']!,
                                        label: opt['label']!,
                                        isSelected: isGenderSelected,
                                        onTap: () {
                                          ref
                                              .read(
                                                selectedGenderProvider.notifier,
                                              )
                                              .state = opt['value']!;
                                          ref
                                              .read(
                                                materialListProvider.notifier,
                                              )
                                              .updateFilters(
                                                gender: opt['value'],
                                              );
                                        },
                                      )
                                      : _TextChip(
                                        label: opt['label']!,
                                        isSelected: isGenderSelected,
                                        onTap: () {
                                          ref
                                              .read(
                                                selectedGenderProvider.notifier,
                                              )
                                              .state = '';
                                          ref
                                              .read(
                                                materialListProvider.notifier,
                                              )
                                              .updateFilters(gender: '');
                                        },
                                      ),
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 第三行：排序
                    Row(
                      children: [
                        _SortPill('ic_fire', '热门', 'hot', sortType, ref),
                        const SizedBox(width: 12),
                        _SortPill('ic_clock', '最新', 'latest', sortType, ref),
                        const SizedBox(width: 12),
                        _SortPill(
                          'ic_download',
                          '最多下载',
                          'downloads',
                          sortType,
                          ref,
                        ),
                        const Spacer(),
                        Text(
                          '${materialState.items.length} 个素材',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textDisabled,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox(height: 110),
            error: (_, __) => const SizedBox(height: 110),
          ),
          const Divider(height: 0.5, thickness: 0.5, color: AppColors.divider),
          // ========== 瀑布流 ==========
          Expanded(
            child: RefreshIndicator(
              displacement: 20,
              edgeOffset: 0,
              strokeWidth: 2,
              color: primary,
              onRefresh:
                  () => ref.read(materialListProvider.notifier).refresh(),
          child:
                  materialState.items.isEmpty && materialState.isLoading
                      ? const _SkeletonGrid()
                      : materialState.items.isEmpty
                      ? ListView(
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.4,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.photo_library_outlined,
                                  size: 64,
                                  color: AppColors.textDisabled,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  '还没有素材哦～',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: AppColors.textHint,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  '下拉刷新试试',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textDisabled,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                      : GridView.builder(
                        controller: _scrollController,
                        cacheExtent: 800,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                              // 固定卡片比例，保证网格等高显示
                              childAspectRatio: 0.68,
                            ),
                        padding: const EdgeInsets.all(6),
                        itemCount:
                            materialState.items.length +
                            (materialState.hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= materialState.items.length) {
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
                          final item = materialState.items[index];
                          return _MaterialCard(
                            item: item,
                            thumbCacheWidth: _thumbCacheWidth,
                            onTap:
                                () => context.push(
                                  '/material/${item.id}/preview',
                                  extra: item,
                                ),
                          );
                        },
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 筛选 Chip（带 Emoji）====================

class _FilterChip extends StatelessWidget {
  final String iconName;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.iconName,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final iconColor = isSelected ? primary : AppColors.textHint;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: 32),
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

// ==================== 纯文字 Chip ====================

class _TextChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TextChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: 32),
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
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ==================== 排序 Pill ====================

class _SortPill extends StatelessWidget {
  final String iconName;
  final String label;
  final String value;
  final String current;
  final WidgetRef ref;

  const _SortPill(
    this.iconName,
    this.label,
    this.value,
    this.current,
    this.ref,
  );

  @override
  Widget build(BuildContext context) {
    final isSelected = value == current;
    final color =
        isSelected ? Theme.of(context).colorScheme.primary : AppColors.textHint;
    return GestureDetector(
      onTap: () {
        ref.read(sortTypeProvider.notifier).state = value;
        ref.read(materialListProvider.notifier).updateFilters(sort: value);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/icons/$iconName.svg',
            width: 13,
            height: 13,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 素材卡片 ====================

class _MaterialCard extends ConsumerWidget {
  final MaterialListItem item;
  final VoidCallback onTap;
  final int thumbCacheWidth;

  const _MaterialCard({
    required this.item,
    required this.onTap,
    required this.thumbCacheWidth,
  });

  static final _kCardRadius = BorderRadius.circular(14);
  static final _kGradientOverlay = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.transparent,
        Colors.black.withValues(alpha: 0.3),
      ],
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favState = ref.watch(materialFavoriteProvider(item.id));
    final favoriteCount = favState?.favoriteCount ?? item.favoriteCount;
    final isFavorited = favState?.isFavorited ?? item.isFavorited;
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
              // 缩略图区域
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
                              (_, __) => Container(
                                color: AppColors.shimmer,
                                child: const Center(
                                  child: Icon(
                                    Icons.image_outlined,
                                    color: AppColors.textDisabled,
                                    size: 28,
                                  ),
                                ),
                              ),
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
                    // 底部渐变遮罩
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 28,
                      child: DecoratedBox(decoration: _kGradientOverlay),
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
              // 底部信息
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
                        Icon(
                          Icons.star_rounded,
                          size: 12,
                          color:
                              isFavorited
                                  ? AppColors.favoriteActive
                                  : AppColors.textDisabled,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          _formatCount(favoriteCount),
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
                          _formatCount(item.downloadCount),
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

  String _formatCount(int count) {
    if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}w';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '$count';
  }
}

// ==================== 骨架屏 占位 ====================

class _SkeletonGrid extends StatefulWidget {
  const _SkeletonGrid();

  @override
  State<_SkeletonGrid> createState() => _SkeletonGridState();
}

class _SkeletonGridState extends State<_SkeletonGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        final opacity = 0.3 + 0.4 * _anim.value;
        return Opacity(opacity: opacity, child: child!);
      },
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 0.68,
        ),
        padding: const EdgeInsets.all(6),
        itemCount: 6,
        itemBuilder: (_, __) => const _SkeletonCard(),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Container(color: AppColors.shimmer)),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 12,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.shimmer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 12,
                    width: 80,
                    decoration: BoxDecoration(
                      color: AppColors.shimmer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        height: 10,
                        width: 40,
                        decoration: BoxDecoration(
                          color: AppColors.shimmer,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        height: 10,
                        width: 40,
                        decoration: BoxDecoration(
                          color: AppColors.shimmer,
                          borderRadius: BorderRadius.circular(3),
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
    );
  }
}
