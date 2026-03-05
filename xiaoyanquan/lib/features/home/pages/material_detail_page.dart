import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../app/colors.dart';
import '../../../app/styles.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/constants/api.dart';
import '../../../core/network/http_client.dart';
import '../../../core/utils/url_utils.dart';
import '../../../shared/network_video_thumbnail.dart';
import '../../../shared/favorite_group_sheet.dart';
import '../../../shared/material_download_helper.dart';
import '../../../shared/share_helper.dart';
import '../models/material_model.dart';
import '../providers/favorite_provider.dart';
import '../repositories/material_repository.dart';
import 'material_preview_page.dart';

final materialDetailProvider = FutureProvider.family<MaterialDetail?, int>((
  ref,
  id,
) async {
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
        title: const Text('详情'),
        centerTitle: true,
        actions: [
          if (detailAsync.valueOrNull != null)
            IconButton(
              icon: const Icon(Icons.share_outlined, size: 22),
              onPressed:
                  () => ShareHelper.shareMaterial(
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
            isAuthenticated: authState.status == AuthStatus.authenticated,
          );
        },
        loading:
            () =>
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }
}

class _DetailContent extends ConsumerStatefulWidget {
  final MaterialDetail detail;
  final bool isAuthenticated;

  const _DetailContent({required this.detail, required this.isAuthenticated});

  @override
  ConsumerState<_DetailContent> createState() => _DetailContentState();
}

class _DetailContentState extends ConsumerState<_DetailContent> {
  MaterialDetail get detail => widget.detail;
  bool get isAuthenticated => widget.isAuthenticated;

  // 提问相关
  List<Map<String, dynamic>> _questions = [];
  bool _questionsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
    // 初始化共享收藏状态（仅当还未被预览页设置时才生效）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(materialFavoriteProvider(detail.id).notifier)
          .init(
            isFavorited: detail.isFavorited,
            favoriteCount: detail.favoriteCount,
          );
    });
  }

  Future<void> _loadQuestions() async {
    try {
      final resp = await HttpClient().get(
        Api.questionsByMaterial(detail.id),
        params: {'page': 1, 'page_size': 50},
      );
      if (resp.isSuccess && resp.data != null) {
        if (!mounted) return;
        setState(() {
          _questions = List<Map<String, dynamic>>.from(resp.data['list'] ?? []);
          _questionsLoading = false;
        });
      } else {
        if (mounted) setState(() => _questionsLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _questionsLoading = false);
    }
  }

  void _showQuestionSheet() {
    if (!isAuthenticated) {
      _showLoginHint(context);
      return;
    }
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.of(ctx).padding.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '提问',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  maxLength: 500,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '输入你的提问...',
                    hintStyle: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () async {
                      final text = controller.text.trim();
                      if (text.length < 2) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入至少2个字')),
                        );
                        return;
                      }

                      final messenger = ScaffoldMessenger.of(context);

                      try {
                        final resp = await HttpClient().post(
                          Api.questions,
                          data: {
                            'target_type': 'material',
                            'target_id': detail.id,
                            'question_text': text,
                          },
                        );

                        if (!mounted) return;

                        if (ctx.mounted) Navigator.pop(ctx);

                        if (resp.isSuccess) {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('提问成功，等待回复')),
                          );
                          _loadQuestions();
                        } else {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                resp.message.isNotEmpty ? resp.message : '提问失败',
                              ),
                            ),
                          );
                        }
                      } catch (_) {
                        if (!mounted) return;
                        if (ctx.mounted) Navigator.pop(ctx);
                        messenger.showSnackBar(
                          const SnackBar(content: Text('提问失败')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('发送', style: TextStyle(fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleFavorite() async {
    if (!isAuthenticated) {
      _showLoginHint(context);
      return;
    }

    final favState = ref.read(materialFavoriteProvider(detail.id));
    final isFavorited = favState?.isFavorited ?? detail.isFavorited;

    if (isFavorited) {
      // 已收藏 → 直接取消
      final error = await ref
          .read(materialFavoriteProvider(detail.id).notifier)
          .removeFavorite(detail.id);
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
          .read(materialFavoriteProvider(detail.id).notifier)
          .addToGroup(detail.id, groupId);
      if (error != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final favState = ref.watch(materialFavoriteProvider(detail.id));
    final isFavorited = favState?.isFavorited ?? detail.isFavorited;
    final favoriteCount = favState?.favoriteCount ?? detail.favoriteCount;

    return Column(
      children: [
        // ========== 可滚动内容 ==========
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                // 发布者 + 标题/描述
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 左侧类型徽章
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppStyles.typeBadgeColor(
                            isVideo: detail.isVideo,
                            isLivePhoto: detail.isLivePhoto,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            AppStyles.typeBadgeText(
                              isVideo: detail.isVideo,
                              isLivePhoto: detail.isLivePhoto,
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 右侧标题
                      Expanded(
                        child: Text(
                          detail.title,
                          style: const TextStyle(fontSize: 15, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 缩略图区域（可点击进入预览）
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildThumbnails(context),
                ),
                const SizedBox(height: 12),
                // 素材信息
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _infoText(
                    '浏览 ${detail.viewCount}  收藏 $favoriteCount  下载 ${detail.downloadCount}',
                  ),
                ),
                // 标签
                if (detail.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children:
                          detail.tags
                              .map(
                                (tag) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '#$tag',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                ],
                // 提问区域
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.divider),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    '提问 (${_questions.length})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_questionsLoading)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_questions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        '暂无提问，点击下方“提问”按钮发起提问',
                        style: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                else
                  ...List.generate(_questions.length, (i) {
                    final q = _questions[i];
                    return Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.cardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                q['user_nickname'] ?? '匿名',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                q['created_at'] ?? '',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textHint,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            q['question_text'] ?? '',
                            style: const TextStyle(fontSize: 14),
                          ),
                          if ((q['reply_text'] ?? '').isNotEmpty) ...[
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
                                      q['reply_text'],
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
                    );
                  }),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
        // ========== 底部操作栏 ==========
        Container(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.divider, width: 0.5),
            ),
          ),
          padding: EdgeInsets.only(
            left: 8,
            right: 8,
            top: 10,
            bottom: MediaQuery.of(context).padding.bottom + 10,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ActionBtn(
                icon:
                    isFavorited
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                label: isFavorited ? '已收藏' : '收藏',
                color: isFavorited ? AppColors.favoriteActive : null,
                onTap: _handleFavorite,
              ),
              _ActionBtn(
                icon: Icons.sentiment_dissatisfied_outlined,
                label: '不喜欢',
                onTap: () {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已标记不喜欢')));
                },
              ),
              _ActionBtn(
                icon: Icons.chat_bubble_outline_rounded,
                label: '提问',
                onTap: _showQuestionSheet,
              ),
              _ActionBtn(
                icon: Icons.file_download_outlined,
                label: '下载',
                onTap: () async {
                  if (!isAuthenticated) {
                    _showLoginHint(context);
                    return;
                  }
                  await _handleDownload();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 原图列表（优先 originalUrls，否则封面/水印图）
  List<String> get _displayUrls {
    if (detail.isVideo) {
      return const [];
    }
    if (detail.originalUrls.isNotEmpty) {
      return detail.originalUrls
          .where((e) => e.isNotEmpty && !UrlUtils.isVideoUrl(e))
          .toList();
    }
    final url =
        detail.watermarkUrl.isNotEmpty
            ? detail.watermarkUrl
            : detail.thumbnailUrl;
    if (url.isNotEmpty && !UrlUtils.isVideoUrl(url)) return [url];
    return const [];
  }

  Future<void> _handleDownload() async {
    final fallbackUrls = <String>[
      ...detail.originalUrls,
      detail.watermarkUrl,
      detail.thumbnailUrl,
      detail.previewMovUrl,
    ];
    await MaterialDownloadHelper.downloadToAlbum(
      context,
      materialId: detail.id,
      materialType: detail.type,
      fallbackUrls: fallbackUrls,
      fallbackVideoUrl: detail.bestVideoUrl,
      fallbackLiveVideoUrl: detail.previewMovUrl,
    );
  }

  /// 微信九宫格缩略图
  Widget _buildThumbnails(BuildContext context) {
    if (detail.isVideo) {
      final coverUrl = detail.safeThumbnailUrl;
      final videoUrl = detail.bestVideoUrl;
      return GestureDetector(
        onTap: () => _openPreview(context, const [], 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (coverUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: coverUrl,
                    fit: BoxFit.cover,
                    placeholder:
                        (_, __) =>
                            Container(height: 180, color: AppColors.shimmer),
                    errorWidget:
                        (_, __, ___) => Container(
                          height: 180,
                          color: AppColors.shimmer,
                          child: const Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.textDisabled,
                              size: 36,
                            ),
                          ),
                        ),
                  )
                else if (videoUrl.isNotEmpty)
                  NetworkVideoThumbnail(
                    videoUrl: videoUrl,
                    fit: BoxFit.cover,
                    placeholder: Container(
                      color: AppColors.shimmer,
                      child: const Center(
                        child: Icon(
                          Icons.play_circle_outline_rounded,
                          color: AppColors.textSecondary,
                          size: 42,
                        ),
                      ),
                    ),
                    errorWidget: Container(
                      color: AppColors.shimmer,
                      child: const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textDisabled,
                          size: 36,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    color: AppColors.shimmer,
                    child: const Center(
                      child: Icon(
                        Icons.play_circle_outline_rounded,
                        color: AppColors.textSecondary,
                        size: 42,
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.15),
                    child: const Center(
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white,
                        size: 52,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final urls = _displayUrls;
    if (urls.isEmpty) {
      return const SizedBox.shrink();
    }

    // 单张：宽度最多占 2/3，最高 240
    if (urls.length == 1) {
      return GestureDetector(
        onTap: () => _openPreview(context, urls, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: CachedNetworkImage(
              imageUrl: urls[0],
              fit: BoxFit.cover,
              width: double.infinity,
              placeholder:
                  (_, __) => Container(height: 180, color: AppColors.shimmer),
              errorWidget:
                  (_, __, ___) => Container(
                    height: 180,
                    color: AppColors.shimmer,
                    child: const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.textDisabled,
                        size: 36,
                      ),
                    ),
                  ),
            ),
          ),
        ),
      );
    }

    // 多张：微信九宫格布局
    final screenWidth = MediaQuery.of(context).size.width;
    const padding = 16.0 * 2;
    const spacing = 4.0;
    final columns = urls.length == 4 ? 2 : 3;
    final cellSize =
        (screenWidth - padding - spacing * (columns - 1)) / columns;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: List.generate(urls.length, (i) {
        return GestureDetector(
          onTap: () => _openPreview(context, urls, i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: cellSize,
              height: cellSize,
              child: CachedNetworkImage(
                imageUrl: urls[i],
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: AppColors.shimmer),
                errorWidget:
                    (_, __, ___) => Container(
                      color: AppColors.shimmer,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.textDisabled,
                        size: 24,
                      ),
                    ),
              ),
            ),
          ),
        );
      }),
    );
  }

  void _openPreview(BuildContext context, List<String> urls, int index) {
    context.push(
      '/material/${detail.id}/preview',
      extra: MaterialPreviewArgs(
        imageUrls: urls,
        initialIndex: index,
        title: detail.title,
      ),
    );
  }

  void _showLoginHint(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('请先登录并开通会员'),
        backgroundColor: AppColors.warning,
      ),
    );
  }

  static Widget _infoText(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 12, color: AppColors.textHint),
    );
  }
}

// ==================== 底部操作按钮 ====================

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: c),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 14, color: c)),
          ],
        ),
      ),
    );
  }
}
