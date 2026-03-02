import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/api.dart';
import '../../../core/network/http_client.dart';

// 模型
class MomentItem {
  final int id;
  final String contentText;
  final String mediaType;
  final List<String> mediaUrls;
  final int questionCount;
  final bool isFavorited;
  final String createdAt;

  MomentItem({
    required this.id,
    this.contentText = '',
    this.mediaType = '',
    this.mediaUrls = const [],
    this.questionCount = 0,
    this.isFavorited = false,
    this.createdAt = '',
  });

  factory MomentItem.fromJson(Map<String, dynamic> json) {
    return MomentItem(
      id: json['id'] ?? 0,
      contentText: json['content_text'] ?? '',
      mediaType: json['media_type'] ?? '',
      mediaUrls: (json['media_urls'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      questionCount: json['question_count'] ?? 0,
      isFavorited: json['is_favorited'] ?? false,
      createdAt: json['created_at'] ?? '',
    );
  }
}

// Provider
class MomentsState {
  final List<MomentItem> items;
  final bool isLoading;
  final bool hasMore;
  final int page;
  const MomentsState(
      {this.items = const [],
      this.isLoading = false,
      this.hasMore = true,
      this.page = 1});
}

class MomentsNotifier extends StateNotifier<MomentsState> {
  final HttpClient _http = HttpClient();
  MomentsNotifier() : super(const MomentsState());

  Future<void> refresh() async {
    state = MomentsState(items: state.items, isLoading: true);
    try {
      final resp = await _http.get(Api.moments, params: {'page': 1});
      if (resp.isSuccess && resp.data != null) {
        final list = (resp.data['list'] as List?)
                ?.map((e) => MomentItem.fromJson(e))
                .toList() ??
            [];
        state = MomentsState(
          items: list,
          hasMore: (resp.data['has_more'] as bool?) ?? false,
          page: 1,
        );
      }
    } catch (_) {
      state = MomentsState(items: state.items);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    state = MomentsState(
        items: state.items,
        isLoading: true,
        hasMore: state.hasMore,
        page: state.page);
    try {
      final next = state.page + 1;
      final resp = await _http.get(Api.moments, params: {'page': next});
      if (resp.isSuccess && resp.data != null) {
        final list = (resp.data['list'] as List?)
                ?.map((e) => MomentItem.fromJson(e))
                .toList() ??
            [];
        state = MomentsState(
          items: [...state.items, ...list],
          hasMore: (resp.data['has_more'] as bool?) ?? false,
          page: next,
        );
      }
    } catch (_) {
      state = MomentsState(
          items: state.items, hasMore: state.hasMore, page: state.page);
    }
  }
}

final momentsProvider =
    StateNotifierProvider<MomentsNotifier, MomentsState>((ref) {
  final n = MomentsNotifier();
  n.refresh();
  return n;
});

class MomentsPage extends ConsumerStatefulWidget {
  const MomentsPage({super.key});

  @override
  ConsumerState<MomentsPage> createState() => _MomentsPageState();
}

class _MomentsPageState extends ConsumerState<MomentsPage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        ref.read(momentsProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(momentsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('朋友圈')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(momentsProvider.notifier).refresh(),
        child: state.items.isEmpty && !state.isLoading
            ? const Center(
                child: Text('暂无动态', style: TextStyle(color: Colors.grey)))
            : ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount:
                    state.items.length + (state.hasMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index >= state.items.length) {
                    return const Center(
                        child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ));
                  }
                  final m = state.items[index];
                  return _MomentCard(
                    moment: m,
                    onTap: () => context.push('/moment/${m.id}'),
                  );
                },
              ),
      ),
    );
  }
}

class _MomentCard extends StatelessWidget {
  final MomentItem moment;
  final VoidCallback onTap;

  const _MomentCard({required this.moment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (moment.contentText.isNotEmpty)
              Text(moment.contentText,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, height: 1.5)),
            if (moment.mediaUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildMediaGrid(),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Text(moment.createdAt,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                const Spacer(),
                Icon(Icons.help_outline, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text('${moment.questionCount}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaGrid() {
    final urls = moment.mediaUrls;
    if (urls.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: urls[0],
          height: 200,
          width: double.infinity,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
              height: 200, color: Colors.grey[900]),
          errorWidget: (_, __, ___) => Container(
              height: 200,
              color: Colors.grey[900],
              child: const Center(child: Icon(Icons.broken_image))),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: urls.length >= 3 ? 3 : 2,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: urls.length > 9 ? 9 : urls.length,
      itemBuilder: (context, index) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: CachedNetworkImage(
            imageUrl: urls[index],
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: Colors.grey[900]),
            errorWidget: (_, __, ___) => Container(color: Colors.grey[900]),
          ),
        );
      },
    );
  }
}
