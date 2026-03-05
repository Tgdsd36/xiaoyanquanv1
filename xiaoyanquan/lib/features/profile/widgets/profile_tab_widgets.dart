import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../app/colors.dart';
import '../../../app/styles.dart';
import '../../../core/utils/url_utils.dart';
import '../../../shared/network_video_thumbnail.dart';
import '../../home/models/favorite_group_model.dart';

// ==================== 收藏分组卡片 ====================

class FavoriteGroupCard extends StatelessWidget {
  final FavoriteGroup group;
  final VoidCallback onTap;

  const FavoriteGroupCard({
    super.key,
    required this.group,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final coverUrl = UrlUtils.absolute(group.coverUrl);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: AppStyles.cardDecoration,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: AppColors.surface,
                child:
                    coverUrl.isNotEmpty
                        ? CachedNetworkImage(
                          imageUrl: coverUrl,
                          fit: BoxFit.cover,
                          errorWidget:
                              (_, __, ___) => const Center(
                                child: Icon(
                                  Icons.collections_bookmark_outlined,
                                  color: AppColors.textDisabled,
                                  size: 32,
                                ),
                              ),
                        )
                        : const Center(
                          child: Icon(
                            Icons.collections_bookmark_outlined,
                            color: AppColors.textDisabled,
                            size: 32,
                          ),
                        ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (group.isDefault)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            '默认',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${group.itemCount} 个收藏',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                    ),
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

// ==================== 下载记录项 ====================

class DownloadListItem extends StatelessWidget {
  final Map<String, dynamic> item;
  const DownloadListItem({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = UrlUtils.absolute(item['thumbnail_url']?.toString());
    final canShowImage =
        thumbnailUrl.isNotEmpty && !UrlUtils.isVideoUrl(thumbnailUrl);
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 50,
          height: 50,
          child:
              canShowImage
                  ? CachedNetworkImage(
                    imageUrl: thumbnailUrl,
                    fit: BoxFit.cover,
                  )
                  : (thumbnailUrl.isNotEmpty &&
                      UrlUtils.isVideoUrl(thumbnailUrl))
                  ? NetworkVideoThumbnail(
                    videoUrl: thumbnailUrl,
                    fit: BoxFit.cover,
                    placeholder: Container(
                      color: AppColors.shimmer,
                      child: const Icon(
                        Icons.play_circle_outline_rounded,
                        color: AppColors.textDisabled,
                      ),
                    ),
                    errorWidget: Container(
                      color: AppColors.shimmer,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.textDisabled,
                      ),
                    ),
                  )
                  : Container(
                    color: AppColors.shimmer,
                    child: Icon(
                      thumbnailUrl.isNotEmpty
                          ? Icons.play_circle_outline_rounded
                          : Icons.image,
                      color: AppColors.textDisabled,
                    ),
                  ),
        ),
      ),
      title: Text(
        item['title'] ?? '未知素材',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        item['downloaded_at'] ?? '',
        style: const TextStyle(fontSize: 12, color: AppColors.textHint),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        size: 18,
        color: AppColors.textHint,
      ),
      onTap: () {
        final materialId = item['material_id'];
        if (materialId != null) {
          context.push('/material/$materialId/preview');
        }
      },
      tileColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

// ==================== 提问列表项 ====================

class QuestionListItem extends StatelessWidget {
  final Map<String, dynamic> item;
  const QuestionListItem({super.key, required this.item});

  void _navigateToTarget(BuildContext context) {
    final targetType = item['target_type'] as String? ?? '';
    final targetId = item['target_id'];
    if (targetId == null) return;
    if (targetType == 'material') {
      context.push('/material/$targetId');
    } else if (targetType == 'moment') {
      context.push('/moment/$targetId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = item['status'] ?? 'pending';
    final targetTitle = item['target_title'] as String? ?? '';
    final targetThumb = UrlUtils.absolute(
      item['target_thumbnail_url']?.toString(),
    );
    final canShowTargetImage =
        targetThumb.isNotEmpty && !UrlUtils.isVideoUrl(targetThumb);
    final targetType = item['target_type'] as String? ?? '';

    return GestureDetector(
      onTap: () => _navigateToTarget(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 关联素材/动态信息
            if (targetTitle.isNotEmpty || targetThumb.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    if (canShowTargetImage)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: CachedNetworkImage(
                            imageUrl: targetThumb,
                            fit: BoxFit.cover,
                            errorWidget:
                                (_, __, ___) => Container(
                                  color: AppColors.shimmer,
                                  child: const Icon(
                                    Icons.image,
                                    size: 16,
                                    color: AppColors.textDisabled,
                                  ),
                                ),
                          ),
                        ),
                      )
                    else if (targetThumb.isNotEmpty &&
                        UrlUtils.isVideoUrl(targetThumb))
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: NetworkVideoThumbnail(
                            videoUrl: targetThumb,
                            fit: BoxFit.cover,
                            placeholder: Container(
                              color: AppColors.shimmer,
                              child: const Icon(
                                Icons.play_circle_outline_rounded,
                                size: 16,
                                color: AppColors.textDisabled,
                              ),
                            ),
                            errorWidget: Container(
                              color: AppColors.shimmer,
                              child: const Icon(
                                Icons.broken_image_outlined,
                                size: 16,
                                color: AppColors.textDisabled,
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          targetType == 'moment'
                              ? Icons.article_outlined
                              : (targetThumb.isNotEmpty
                                  ? Icons.play_circle_outline_rounded
                                  : Icons.image_outlined),
                          size: 18,
                          color: AppColors.textDisabled,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            targetType == 'moment' ? '动态' : '素材',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint,
                            ),
                          ),
                          Text(
                            targetTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.textDisabled,
                    ),
                  ],
                ),
              ),
            // 状态 + 时间
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                        status == 'replied'
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    status == 'replied' ? '已回复' : '待回复',
                    style: TextStyle(
                      fontSize: 11,
                      color: status == 'replied' ? Colors.green : Colors.orange,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  item['created_at'] ?? '',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item['question_text'] ?? '',
              style: const TextStyle(fontSize: 14),
            ),
            if ((item['reply_text'] ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.reply,
                      size: 14,
                      color: AppColors.textHint,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item['reply_text'],
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
