import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../shared/live_photo_view.dart';
import '../../../shared/share_helper.dart';
import '../models/material_model.dart';
import '../repositories/material_repository.dart';

final materialDetailProvider =
    FutureProvider.family<MaterialDetail?, int>((ref, id) async {
  final repo = MaterialRepository();
  return repo.getDetail(id);
});

class MaterialDetailPage extends ConsumerWidget {
  final int materialId;

  const MaterialDetailPage({super.key, required this.materialId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(materialDetailProvider(materialId));
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('素材详情'),
        actions: [
          if (detailAsync.valueOrNull != null)
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => ShareHelper.shareMaterial(
                id: materialId,
                title: detailAsync.valueOrNull!.title,
              ),
            ),
        ],
      ),
      body: detailAsync.when(
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('素材不存在'));
          }
          return _DetailContent(
            detail: detail,
            isGuest: authState.status == AuthStatus.guest,
            isAuthenticated:
                authState.status == AuthStatus.authenticated,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }
}

class _DetailContent extends StatelessWidget {
  final MaterialDetail detail;
  final bool isGuest;
  final bool isAuthenticated;

  const _DetailContent({
    required this.detail,
    required this.isGuest,
    required this.isAuthenticated,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 预览图 / Live Photo
                AspectRatio(
                  aspectRatio: (detail.width > 0 && detail.height > 0)
                      ? detail.width / detail.height
                      : 4 / 3,
                  child: detail.isLivePhoto && detail.previewMovUrl.isNotEmpty
                      ? LivePhotoView(
                          imageUrl: detail.watermarkUrl.isNotEmpty
                              ? detail.watermarkUrl
                              : detail.thumbnailUrl,
                          videoUrl: detail.previewMovUrl,
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: detail.watermarkUrl.isNotEmpty
                                  ? detail.watermarkUrl
                                  : detail.thumbnailUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) =>
                                  Container(color: Colors.grey[900]),
                              errorWidget: (_, __, ___) => Container(
                                color: Colors.grey[900],
                                child: const Center(
                                    child: Icon(Icons.broken_image,
                                        color: Colors.grey, size: 48)),
                              ),
                            ),
                            if (detail.isVideo)
                              const Center(
                                child: Icon(Icons.play_circle_outline,
                                    size: 64, color: Colors.white70),
                              ),
                          ],
                        ),
                ),
                // 信息区
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(detail.title,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      if (detail.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(detail.description,
                            style: TextStyle(
                                color: Colors.grey[400], fontSize: 14)),
                      ],
                      const SizedBox(height: 16),
                      // 统计
                      Row(
                        children: [
                          _StatItem(Icons.visibility, '${detail.viewCount}'),
                          const SizedBox(width: 20),
                          _StatItem(
                              Icons.download, '${detail.downloadCount}'),
                          const SizedBox(width: 20),
                          _StatItem(
                              Icons.favorite, '${detail.favoriteCount}'),
                        ],
                      ),
                      const Divider(height: 32),
                      // 详细信息
                      _InfoRow('分类', detail.categoryName),
                      _InfoRow(
                          '尺寸', '${detail.width} × ${detail.height}'),
                      _InfoRow('大小', detail.fileSizeText),
                      if (detail.duration > 0)
                        _InfoRow(
                            '时长', '${detail.duration.toStringAsFixed(1)}秒'),
                      _InfoRow('发布时间', detail.createdAt),
                      // 标签
                      if (detail.tags.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: detail.tags
                              .map((tag) => Chip(
                                    label: Text(tag,
                                        style:
                                            const TextStyle(fontSize: 12)),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // 底部操作栏
        Container(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).padding.bottom + 12,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
                top: BorderSide(color: Colors.grey[800]!, width: 0.5)),
          ),
          child: Row(
            children: [
              // 收藏按钮
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isAuthenticated
                      ? () {
                          // TODO: 收藏功能
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('收藏功能即将上线')),
                          );
                        }
                      : () => _showLoginHint(context),
                  icon: Icon(
                    detail.isFavorited
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: detail.isFavorited ? Colors.red : null,
                  ),
                  label: Text(detail.isFavorited ? '已收藏' : '收藏'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    side: BorderSide(color: Colors.grey[700]!),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 下载按钮
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: isAuthenticated
                      ? () {
                          // TODO: 下载功能
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('下载功能即将上线')),
                          );
                        }
                      : () => _showLoginHint(context),
                  icon: const Icon(Icons.download),
                  label: Text(detail.isLivePhoto ? '保存 Live Photo' : '下载原图'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showLoginHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('请先登录并开通会员'),
        backgroundColor: Colors.orange,
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;

  const _StatItem(this.icon, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[500]),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(fontSize: 13, color: Colors.grey[400])),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          ),
          Expanded(
            child:
                Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
