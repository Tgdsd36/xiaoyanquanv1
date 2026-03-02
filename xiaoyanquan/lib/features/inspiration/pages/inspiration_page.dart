import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/api.dart';
import '../../../core/network/http_client.dart';
import '../../home/models/material_model.dart';

final inspirationProvider =
    StateNotifierProvider<InspirationNotifier, InspirationState>(
  (ref) {
    final notifier = InspirationNotifier();
    notifier.load();
    return notifier;
  },
);

class InspirationState {
  final List<MaterialListItem> items;
  final bool isLoading;
  const InspirationState({this.items = const [], this.isLoading = false});
}

class InspirationNotifier extends StateNotifier<InspirationState> {
  final HttpClient _http = HttpClient();
  InspirationNotifier() : super(const InspirationState());

  Future<void> load() async {
    state = InspirationState(items: state.items, isLoading: true);
    try {
      final resp =
          await _http.get(Api.inspirationFeed, params: {'page_size': 20});
      if (resp.isSuccess && resp.data is List) {
        final list = (resp.data as List)
            .map((e) => MaterialListItem.fromJson(e))
            .toList();
        state = InspirationState(items: list);
      } else {
        state = InspirationState(items: state.items);
      }
    } catch (_) {
      state = InspirationState(items: state.items);
    }
  }

  Future<void> dislike(int materialId) async {
    state = InspirationState(
      items: state.items.where((i) => i.id != materialId).toList(),
    );
    try {
      await _http
          .post(Api.inspirationDislike, data: {'material_id': materialId});
    } catch (_) {}
  }
}

class InspirationPage extends ConsumerWidget {
  const InspirationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(inspirationProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('找灵感')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(inspirationProvider.notifier).load(),
        child: state.items.isEmpty && !state.isLoading
            ? const Center(
                child: Text('暂无推荐', style: TextStyle(color: Colors.grey)))
            : MasonryGridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                padding: const EdgeInsets.all(8),
                itemCount: state.items.length,
                itemBuilder: (context, index) {
                  final item = state.items[index];
                  return _InspirationCard(
                    item: item,
                    onTap: () => context.push('/material/${item.id}'),
                    onDislike: () => ref
                        .read(inspirationProvider.notifier)
                        .dislike(item.id),
                  );
                },
              ),
      ),
    );
  }
}

class _InspirationCard extends StatelessWidget {
  final MaterialListItem item;
  final VoidCallback onTap;
  final VoidCallback onDislike;

  const _InspirationCard({
    required this.item,
    required this.onTap,
    required this.onDislike,
  });

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
              AspectRatio(
                aspectRatio: item.aspectRatio,
                child: CachedNetworkImage(
                  imageUrl: item.thumbnailUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: Colors.grey[900]),
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.grey[900],
                    child: const Center(
                        child: Icon(Icons.image, color: Colors.grey)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                    ),
                    GestureDetector(
                      onTap: onDislike,
                      child: Icon(Icons.not_interested,
                          size: 16, color: Colors.grey[600]),
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
