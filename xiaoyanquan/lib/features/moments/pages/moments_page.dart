import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../app/colors.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/constants/api.dart';
import '../../../core/network/http_client.dart';
import '../../../core/utils/url_utils.dart';
import '../../../shared/network_video_thumbnail.dart';
import '../../../shared/favorite_group_sheet.dart';
import '../../../shared/material_download_helper.dart';
import '../../profile/pages/profile_page.dart';

// ==================== 模型 ====================

class MomentItem {
  final int id;
  final String nickname;
  final String avatarUrl;
  final String gender;
  final String contentText;
  final String mediaType;
  final List<String> mediaUrls;
  final bool isFavorited;
  final String createdAt;

  MomentItem({
    required this.id,
    this.nickname = '',
    this.avatarUrl = '',
    this.gender = '',
    this.contentText = '',
    this.mediaType = '',
    this.mediaUrls = const [],
    this.isFavorited = false,
    this.createdAt = '',
  });

  factory MomentItem.fromJson(Map<String, dynamic> json) {
    return MomentItem(
      id: json['id'] ?? 0,
      nickname: json['nickname'] ?? '',
      avatarUrl: json['avatar_url'] ?? '',
      gender: json['gender'] ?? '',
      contentText: json['content_text'] ?? '',
      mediaType: json['media_type'] ?? '',
      mediaUrls:
          (json['media_urls'] as List?)?.map((e) => e.toString()).toList() ??
          [],
      isFavorited: json['is_favorited'] ?? false,
      createdAt: json['created_at'] ?? '',
    );
  }
}

// ==================== State + Notifier ====================

class MomentsState {
  final List<MomentItem> items;
  final bool isLoading;
  final bool hasMore;
  final int page;
  final String mediaType; // '' = 综合, 'video', 'image', 'live'
  final String gender; // '' = 不限, 'male', 'female'

  const MomentsState({
    this.items = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.page = 1,
    this.mediaType = '',
    this.gender = '',
  });

  MomentsState copyWith({
    List<MomentItem>? items,
    bool? isLoading,
    bool? hasMore,
    int? page,
    String? mediaType,
    String? gender,
  }) {
    return MomentsState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      mediaType: mediaType ?? this.mediaType,
      gender: gender ?? this.gender,
    );
  }
}

class MomentsNotifier extends StateNotifier<MomentsState> {
  final HttpClient _http = HttpClient();
  MomentsNotifier() : super(const MomentsState());

  Map<String, dynamic> get _filterParams {
    final params = <String, dynamic>{};
    if (state.mediaType.isNotEmpty) params['type'] = state.mediaType;
    if (state.gender.isNotEmpty) params['gender'] = state.gender;
    return params;
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    try {
      final resp = await _http.get(
        Api.moments,
        params: {'page': 1, 'page_size': 20, ..._filterParams},
      );
      if (resp.isSuccess && resp.data != null) {
        final list =
            (resp.data['list'] as List?)
                ?.map((e) => MomentItem.fromJson(e))
                .toList() ??
            [];
        state = state.copyWith(
          items: list,
          hasMore: (resp.data['has_more'] as bool?) ?? false,
          page: 1,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true);
    try {
      final next = state.page + 1;
      final resp = await _http.get(
        Api.moments,
        params: {'page': next, 'page_size': 20, ..._filterParams},
      );
      if (resp.isSuccess && resp.data != null) {
        final list =
            (resp.data['list'] as List?)
                ?.map((e) => MomentItem.fromJson(e))
                .toList() ??
            [];
        state = state.copyWith(
          items: [...state.items, ...list],
          hasMore: (resp.data['has_more'] as bool?) ?? false,
          page: next,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  void setMediaType(String type) {
    if (state.mediaType == type) return;
    state = MomentsState(mediaType: type, gender: state.gender);
    refresh();
  }

  void setGender(String g) {
    // 单选切换：再点取消
    final newGender = state.gender == g ? '' : g;
    state = MomentsState(mediaType: state.mediaType, gender: newGender);
    refresh();
  }
}

final momentsProvider = StateNotifierProvider<MomentsNotifier, MomentsState>((
  ref,
) {
  final n = MomentsNotifier();
  n.refresh();
  return n;
});

// ==================== 页面 ====================

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
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(momentsProvider.notifier).loadMore();
    }
  }

  Future<void> _changeCover(BuildContext ctx) async {
    final authState = ref.read(authProvider);
    if (authState.status != AuthStatus.authenticated) {
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }

    final granted = await _ensureGalleryPermission(ctx);
    if (!granted || !ctx.mounted) return;

    final messenger = ScaffoldMessenger.of(ctx);

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      imageQuality: 85,
    );
    if (picked == null || !ctx.mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('正在上传...')));

    try {
      // 1. 上传图片
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          picked.path,
          filename: picked.name,
        ),
      });
      final uploadResp = await HttpClient().dio.post(
        Api.userUpload,
        data: formData,
      );
      final uploadData = uploadResp.data;
      if (uploadData['code'] != 0) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(content: Text(uploadData['message'] ?? '上传失败')),
        );
        return;
      }
      final url = uploadData['data']['url'] as String;

      // 2. 更新个人资料
      final updateResp = await HttpClient().put(
        Api.userProfile,
        data: {'cover_url': url},
      );
      messenger.hideCurrentSnackBar();
      if (updateResp.isSuccess) {
        ref.invalidate(profileProvider);
        messenger.showSnackBar(const SnackBar(content: Text('封面已更换')));
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              updateResp.message.isNotEmpty ? updateResp.message : '更新失败',
            ),
          ),
        );
      }
    } catch (_) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('上传失败，请重试')));
    }
  }

  Future<bool> _ensureGalleryPermission(BuildContext context) async {
    if (kIsWeb) return true;

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      final status = await Permission.photos.request();
      final granted = status.isGranted || status.isLimited;
      if (granted) return true;

      if (!context.mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先允许相册权限后再选择封面')));
      if (status.isPermanentlyDenied || status.isRestricted) {
        await _showGalleryPermissionSettingsDialog(context);
      }
      return false;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final statusMap =
          await <Permission>[Permission.photos, Permission.storage].request();
      final statuses = statusMap.values.toList();
      final granted = statuses.any((s) => s.isGranted || s.isLimited);
      if (granted) return true;

      if (!context.mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先允许相册权限后再选择封面')));
      if (statuses.any((s) => s.isPermanentlyDenied)) {
        await _showGalleryPermissionSettingsDialog(context);
      }
      return false;
    }

    return true;
  }

  Future<void> _showGalleryPermissionSettingsDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('需要相册权限'),
          content: const Text('当前相册权限已被拒绝，请到系统设置中开启后再试。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await openAppSettings();
              },
              child: const Text('去设置'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final momentsState = ref.watch(momentsProvider);
    final profileAsync = ref.watch(profileProvider);
    final profile = profileAsync.valueOrNull;

    final coverUrl = UrlUtils.absolute(profile?['cover_url']?.toString());
    final nickname = profile?['nickname'] as String? ?? '用户';

    return Scaffold(
      body: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder:
            (context, innerBoxIsScrolled) => [
              // ========== 封面区 ==========
              SliverAppBar(
                expandedHeight: 280,
                pinned: false,
                floating: false,
                backgroundColor: AppColors.primary,
                automaticallyImplyLeading: false,
                flexibleSpace: FlexibleSpaceBar(
                  background: _CoverArea(
                    coverUrl: coverUrl,
                    nickname: nickname,
                    onSearchTap: () => context.push('/search'),
                    onCoverTap: () => _changeCover(context),
                  ),
                ),
              ),
              // ========== 吸顶筛选栏 ==========
              SliverPersistentHeader(
                pinned: true,
                delegate: _FilterBarDelegate(
                  mediaType: momentsState.mediaType,
                  gender: momentsState.gender,
                  onMediaTypeChanged:
                      (t) => ref.read(momentsProvider.notifier).setMediaType(t),
                  onGenderChanged:
                      (g) => ref.read(momentsProvider.notifier).setGender(g),
                ),
              ),
            ],
        body: RefreshIndicator(
          onRefresh: () => ref.read(momentsProvider.notifier).refresh(),
          child:
              momentsState.items.isEmpty && !momentsState.isLoading
                  ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Text(
                          '暂无动态',
                          style: TextStyle(color: AppColors.textHint),
                        ),
                      ),
                    ],
                  )
                  : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount:
                        momentsState.items.length +
                        (momentsState.hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      if (index >= momentsState.items.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      return _MomentCard(moment: momentsState.items[index]);
                    },
                  ),
        ),
      ),
    );
  }
}

// ==================== 封面区 ====================

class _CoverArea extends StatelessWidget {
  final String coverUrl;
  final String nickname;
  final VoidCallback onSearchTap;
  final VoidCallback onCoverTap;

  const _CoverArea({
    required this.coverUrl,
    required this.nickname,
    required this.onSearchTap,
    required this.onCoverTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 封面图
        if (coverUrl.isNotEmpty)
          CachedNetworkImage(
            imageUrl: coverUrl,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => _defaultCover(),
          )
        else
          _defaultCover(),
        // 底部渐变遮罩
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 100,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
              ),
            ),
          ),
        ),
        // 右上角搜索按钮
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          right: 12,
          child: GestureDetector(
            onTap: onSearchTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search, size: 16, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    '搜索',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 左下角更换封面按钮
        Positioned(
          left: 16,
          bottom: 16,
          child: GestureDetector(
            onTap: onCoverTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.camera_alt_outlined,
                    size: 14,
                    color: Colors.white70,
                  ),
                  SizedBox(width: 4),
                  Text(
                    '更换封面',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 右下角头像+昵称
        Positioned(
          right: 16,
          bottom: 16,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                nickname,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    nickname.isNotEmpty ? nickname[0] : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _defaultCover() {
    return Image.asset(
      'assets/images/covers/default_moments_cover.png',
      fit: BoxFit.cover,
      errorBuilder:
          (_, __, ___) => Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, Color(0xFFFF8A9B)],
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.photo_camera_outlined,
                size: 48,
                color: Colors.white38,
              ),
            ),
          ),
    );
  }
}

// ==================== 吸顶筛选栏 ====================

class _FilterBarDelegate extends SliverPersistentHeaderDelegate {
  final String mediaType;
  final String gender;
  final ValueChanged<String> onMediaTypeChanged;
  final ValueChanged<String> onGenderChanged;

  _FilterBarDelegate({
    required this.mediaType,
    required this.gender,
    required this.onMediaTypeChanged,
    required this.onGenderChanged,
  });

  static const _tabs = [
    ('', '综合'),
    ('video', '视频'),
    ('image', '图片'),
    ('live', 'Live'),
  ];

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: 48,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // 类型 Tab
          ..._tabs.map((tab) {
            final isSelected = mediaType == tab.$1;
            return GestureDetector(
              onTap: () => onMediaTypeChanged(tab.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      tab.$2,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color:
                            isSelected
                                ? AppColors.textPrimary
                                : AppColors.textHint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      width: 16,
                      height: 2,
                      decoration: BoxDecoration(
                        color:
                            isSelected ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const Spacer(),
          // 性别筛选
          _GenderChip(
            label: '男',
            isSelected: gender == 'male',
            onTap: () => onGenderChanged('male'),
          ),
          const SizedBox(width: 8),
          _GenderChip(
            label: '女',
            isSelected: gender == 'female',
            onTap: () => onGenderChanged('female'),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _FilterBarDelegate oldDelegate) {
    return mediaType != oldDelegate.mediaType || gender != oldDelegate.gender;
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ==================== 动态卡片 ====================

class _MomentCard extends ConsumerStatefulWidget {
  final MomentItem moment;
  const _MomentCard({required this.moment});

  @override
  ConsumerState<_MomentCard> createState() => _MomentCardState();
}

class _MomentCardState extends ConsumerState<_MomentCard> {
  late bool _isFavorited;

  MomentItem get moment => widget.moment;

  @override
  void initState() {
    super.initState();
    _isFavorited = moment.isFavorited;
  }

  Future<void> _handleFavorite() async {
    final authState = ref.read(authProvider);
    if (authState.status != AuthStatus.authenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先登录并开通会员'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    if (_isFavorited) {
      // 取消收藏
      setState(() => _isFavorited = false);
      try {
        await HttpClient().post(
          Api.favoriteToggle,
          data: {
            'target_type': 'material',
            'target_id': moment.id,
            'group_id': 0,
          },
        );
      } catch (_) {
        if (mounted) setState(() => _isFavorited = true);
      }
    } else {
      // 收藏 — 弹出分组选择
      final groupId = await FavoriteGroupSheet.show(context);
      if (groupId == null || !mounted) return;
      setState(() => _isFavorited = true);
      try {
        final resp = await HttpClient().post(
          Api.favoriteToggle,
          data: {
            'target_type': 'material',
            'target_id': moment.id,
            'group_id': groupId,
          },
        );
        if (!resp.isSuccess && mounted) {
          setState(() => _isFavorited = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(resp.message.isNotEmpty ? resp.message : '收藏失败'),
            ),
          );
        }
      } catch (_) {
        if (mounted) setState(() => _isFavorited = false);
      }
    }
  }

  Future<void> _handleDownload() async {
    final authState = ref.read(authProvider);
    if (authState.status != AuthStatus.authenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先登录并开通会员'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final mediaType =
        moment.mediaType == 'live' ? 'live_photo' : moment.mediaType;
    await MaterialDownloadHelper.downloadToAlbum(
      context,
      materialId: moment.id,
      materialType: mediaType,
      fallbackUrls: moment.mediaUrls,
      fallbackVideoUrl:
          moment.mediaUrls.firstWhere(
            (url) => UrlUtils.isVideoUrl(url),
            orElse: () => '',
          ),
      fallbackLiveVideoUrl:
          moment.mediaUrls.firstWhere(
            (url) => UrlUtils.isVideoUrl(url),
            orElse: () => '',
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头像 + 昵称
          Row(
            children: [
              if (moment.avatarUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CachedNetworkImage(
                      imageUrl: moment.avatarUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _defaultAvatar(),
                    ),
                  ),
                )
              else
                _defaultAvatar(),
              const SizedBox(width: 10),
              Text(
                moment.nickname.isNotEmpty ? moment.nickname : '匿名',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          // 内容文字
          if (moment.contentText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              moment.contentText,
              style: const TextStyle(fontSize: 14, height: 1.6),
            ),
          ],
          // 媒体区域
          if (moment.mediaUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildMedia(context),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 8),
          // 操作栏
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ActionBtn(
                icon:
                    _isFavorited
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                label: _isFavorited ? '已收藏' : '收藏',
                color: _isFavorited ? AppColors.favoriteActive : null,
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
                onTap: () => context.push('/material/${moment.id}'),
              ),
              _ActionBtn(
                icon: Icons.file_download_outlined,
                label: '下载',
                onTap: _handleDownload,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _defaultAvatar() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.person, size: 22, color: AppColors.primary),
    );
  }

  Widget _buildMedia(BuildContext context) {
    final urls = moment.mediaUrls;
    final isVideo = moment.mediaType == 'video';

    // 视频：缩略图 + 播放图标
    if (isVideo && urls.isNotEmpty) {
      final coverUrl = urls.first;
      final isVideoCover = UrlUtils.isVideoUrl(coverUrl);
      return GestureDetector(
        onTap: () => context.push('/material/${moment.id}/preview'),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child:
                    isVideoCover
                        ? NetworkVideoThumbnail(
                          videoUrl: coverUrl,
                          fit: BoxFit.cover,
                          placeholder: Container(
                            height: 200,
                            width: double.infinity,
                            color: AppColors.shimmer,
                            child: const Center(
                              child: Icon(
                                Icons.play_circle_outline_rounded,
                                color: AppColors.textSecondary,
                                size: 40,
                              ),
                            ),
                          ),
                          errorWidget: Container(
                            height: 200,
                            width: double.infinity,
                            color: AppColors.shimmer,
                            child: const Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: AppColors.textDisabled,
                                size: 32,
                              ),
                            ),
                          ),
                        )
                        : CachedNetworkImage(
                          imageUrl: coverUrl,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholder:
                              (_, __) => Container(
                                height: 200,
                                color: AppColors.shimmer,
                              ),
                          errorWidget:
                              (_, __, ___) => Container(
                                height: 200,
                                color: AppColors.shimmer,
                                child: const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: AppColors.textDisabled,
                                    size: 32,
                                  ),
                                ),
                              ),
                        ),
              ),
              Positioned.fill(
                child: Center(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 单张图片
    if (urls.length == 1) {
      return GestureDetector(
        onTap: () => context.push('/material/${moment.id}/preview'),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: CachedNetworkImage(
              imageUrl: urls[0],
              width: double.infinity,
              fit: BoxFit.cover,
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
                        size: 32,
                      ),
                    ),
                  ),
            ),
          ),
        ),
      );
    }

    // 多张图片：九宫格
    final screenWidth = MediaQuery.of(context).size.width;
    const outerPadding = 12.0 * 2 + 12.0 * 2;
    const spacing = 4.0;
    final columns = urls.length == 4 ? 2 : 3;
    final cellSize =
        (screenWidth - outerPadding - spacing * (columns - 1)) / columns;
    final displayCount = urls.length > 9 ? 9 : urls.length;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: List.generate(displayCount, (i) {
        return GestureDetector(
          onTap: () => context.push('/material/${moment.id}/preview'),
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
                        size: 20,
                      ),
                    ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ==================== 操作按钮 ====================

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
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: c),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: c)),
          ],
        ),
      ),
    );
  }
}
