import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../models/category_model.dart';
import '../models/material_model.dart';
import '../providers/home_provider.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _scrollController = ScrollController();

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

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final selectedType = ref.watch(selectedTypeProvider);
    final selectedGender = ref.watch(selectedGenderCategoryProvider);
    final sortType = ref.watch(sortTypeProvider);
    final materialState = ref.watch(materialListProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            // 左侧：图库标题
            Icon(
              Icons.filter_list_alt, // 或者 Icons.image_outlined
              size: 20,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(width: 4),
            Text(
              '小颜圈',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 16),
            // 中间：搜索框
            Expanded(
              child: GestureDetector(
                onTap: () => context.push('/search'),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).inputDecorationTheme.fillColor ??
                        Colors.grey[100],
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Theme.of(context).dividerColor,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        size: 18,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '请输入关键字搜索',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 右侧：搜索按钮（红色背景）
            GestureDetector(
              onTap: () => context.push('/search'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text(
                  '搜索',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: const [], // 清空原来的 action
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Divider(
            height: 0.5,
            thickness: 0.5,
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      body: Column(
        children: [
          // 分类栏
          categoriesAsync.when(
            data: (categories) {
              // 类型筛选选项
              const typeOptions = [
                {'label': '综合', 'value': ''}, // 改名为"综合"以匹配UI
                {'label': '视频', 'value': 'video'},
                {'label': '图片', 'value': 'image'},
                {'label': 'Live', 'value': 'live_photo'},
              ];

              // 性别分类（从后端获取）
              bool isGender(CategoryModel c) =>
                  c.slug == 'male' || c.slug == 'female';
              final genderCats = categories.where(isGender).toList();
              // 这里不需要"不限"选项了，通过取消选中来表示不限，或者UI上只显示男女

              return Container(
                height: 54, // 增加一点高度
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).dividerColor,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // 左侧：类型 Tab (综合/视频/图片...)
                    Expanded(
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: typeOptions.length,
                        itemBuilder: (context, index) {
                          final opt = typeOptions[index];
                          final isSelected = opt['value'] == selectedType;
                          return _TypeTab(
                            label: opt['label']!,
                            isSelected: isSelected,
                            onTap: () {
                              ref.read(selectedTypeProvider.notifier).state =
                                  opt['value']!;
                              ref
                                  .read(materialListProvider.notifier)
                                  .updateFilters(type: opt['value']);
                            },
                          );
                        },
                      ),
                    ),
                    
                    // 右侧：性别 Chip (男/女)
                    Padding(
                      padding: const EdgeInsets.only(right: 16, left: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: genderCats.map((cat) {
                          final isSelected = cat.id == selectedGender;
                          return Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: _GenderChip(
                              label: cat.name,
                              isSelected: isSelected,
                              onTap: () {
                                // 如果点击已选中的，则取消选中（变为不限）；否则选中当前
                                final newId = isSelected ? 0 : cat.id;
                                ref
                                    .read(selectedGenderCategoryProvider.notifier)
                                    .state = newId;
                                ref
                                    .read(materialListProvider.notifier)
                                    .updateFilters(genderCategoryId: newId);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox(height: 54),
            error: (_, __) => const SizedBox(height: 54),
          ),
          // 排序栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _SortChip('热门', 'hot', sortType, ref),
                const SizedBox(width: 12),
                _SortChip('最新', 'latest', sortType, ref),
                const SizedBox(width: 12),
                _SortChip('下载最多', 'downloads', sortType, ref),
              ],
            ),
          ),
          // 瀑布流
          Expanded(
            child: RefreshIndicator(
              displacement: 20,
              edgeOffset: 0,
              strokeWidth: 2,
              onRefresh: () =>
                  ref.read(materialListProvider.notifier).refresh(),
              child: materialState.items.isEmpty && !materialState.isLoading
                  ? const Center(
                      child: Text('暂无素材',
                          style: TextStyle(color: Colors.grey)))
                  : MasonryGridView.count(
                      controller: _scrollController,
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      padding: const EdgeInsets.all(8),
                      itemCount: materialState.items.length +
                          (materialState.hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= materialState.items.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child:
                                Center(child: CircularProgressIndicator()),
                          );
                        }
                        return _MaterialCard(
                          item: materialState.items[index],
                          onTap: () => context.push(
                              '/material/${materialState.items[index].id}'),
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

class _SortChip extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final WidgetRef ref;

  const _SortChip(this.label, this.value, this.current, this.ref);

  @override
  Widget build(BuildContext context) {
    final isSelected = value == current;
    return GestureDetector(
      onTap: () {
        ref.read(sortTypeProvider.notifier).state = value;
        ref.read(materialListProvider.notifier).updateFilters(sort: value);
      },
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey,
        ),
      ),
    );
  }
}

class _TypeTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 4),
            // 指示器
            if (isSelected)
              Container(
                width: 16,
                height: 3,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary, // 粉色/主题色
                  borderRadius: BorderRadius.circular(1.5),
                ),
              )
            else
              const SizedBox(height: 3),
          ],
        ),
      ),
    );
  }
}

class _GenderChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _GenderChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class _MaterialCard extends StatelessWidget {
  final MaterialListItem item;
  final VoidCallback onTap;

  const _MaterialCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: Theme.of(context).cardColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 缩略图
              AspectRatio(
                aspectRatio: item.aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: item.thumbnailUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: Colors.grey[200],
                        child: Center(
                            child: Icon(Icons.image,
                                color: Colors.grey[400], size: 32)),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[200],
                        child: Center(
                            child: Icon(Icons.broken_image,
                                color: Colors.grey[400], size: 32)),
                      ),
                    ),
                    // 视频时长 / Live Photo 标记
                    if (item.isVideo && item.durationText.isNotEmpty)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(item.durationText,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11)),
                        ),
                      ),
                    if (item.isLivePhoto)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('LIVE',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
              ),
              // 底部信息
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.download,
                            size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 2),
                        Text('${item.downloadCount}',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500])),
                        const SizedBox(width: 8),
                        Icon(Icons.favorite_border,
                            size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 2),
                        Text('${item.favoriteCount}',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500])),
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
