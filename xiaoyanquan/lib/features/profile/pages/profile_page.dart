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
import '../../home/models/favorite_group_model.dart';
import '../../home/repositories/favorite_repository.dart';
import '../widgets/profile_tab_widgets.dart';

// ==================== Provider ====================

final profileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final auth = ref.watch(authProvider);
  if (auth.status != AuthStatus.authenticated) return null;
  try {
    final resp = await HttpClient().get(Api.userProfile);
    if (resp.isSuccess) return resp.data;
  } catch (_) {}
  return null;
});

// ==================== Page ====================

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  final HttpClient _http = HttpClient();
  final FavoriteRepository _groupRepo = FavoriteRepository();

  List<FavoriteGroup> _groups = [];
  bool _groupsLoading = true;

  List<Map<String, dynamic>> _downloads = [];
  bool _downloadsLoading = true;

  List<Map<String, dynamic>> _questions = [];
  bool _questionsLoading = true;
  int _questionTotal = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadGroups();
    _loadQuestions();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    final index = _tabController.index;
    if (index == 0 && _groupsLoading && _groups.isEmpty) _loadGroups();
    if (index == 1 && _downloadsLoading && _downloads.isEmpty) _loadDownloads();
    if (index == 2 && _questionsLoading && _questions.isEmpty) _loadQuestions();
  }

  Future<void> _loadGroups() async {
    setState(() => _groupsLoading = true);
    try {
      final groups = await _groupRepo.getGroups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _groupsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _groupsLoading = false);
    }
  }

  Future<void> _loadDownloads() async {
    setState(() => _downloadsLoading = true);
    try {
      final resp = await _http.get(Api.userDownloads, params: {'page': 1});
      if (!mounted) return;
      if (resp.isSuccess && resp.data != null) {
        setState(() {
          _downloads = List<Map<String, dynamic>>.from(resp.data['list'] ?? []);
          _downloadsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _downloadsLoading = false);
    }
  }

  Future<void> _loadQuestions() async {
    setState(() => _questionsLoading = true);
    try {
      final resp = await _http.get(Api.questions, params: {'page': 1});
      if (!mounted) return;
      if (resp.isSuccess && resp.data != null) {
        final list = List<Map<String, dynamic>>.from(resp.data['list'] ?? []);
        final totalRaw = resp.data['total'];
        final total =
            totalRaw is int
                ? totalRaw
                : int.tryParse(totalRaw?.toString() ?? '') ?? list.length;
        setState(() {
          _questions = list;
          _questionTotal = total;
          _questionsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _questionsLoading = false);
    }
  }

  Future<void> _createGroup() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('新建分组'),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 20,
              decoration: const InputDecoration(
                hintText: '输入分组名称',
                counterText: '',
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('创建'),
              ),
            ],
          ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final result = await _groupRepo.createGroup(name);
    if (!mounted) return;
    if (result.group != null) {
      _loadGroups();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.error ?? '创建失败')));
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
    final authState = ref.watch(authProvider);

    if (authState.status == AuthStatus.unauthenticated ||
        authState.status == AuthStatus.guest) {
      return _buildUnauthenticated();
    }

    final profileAsync = ref.watch(profileProvider);
    final profile = profileAsync.valueOrNull;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder:
            (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(child: _buildHeader(profile)),
              SliverToBoxAdapter(child: _buildQuickEntries(profile)),
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyTabBarDelegate(
                  tabBar: TabBar(
                    controller: _tabController,
                    labelColor: AppColors.textPrimary,
                    unselectedLabelColor: AppColors.textHint,
                    labelStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    unselectedLabelStyle: const TextStyle(fontSize: 15),
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 2.5,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerHeight: 0.5,
                    dividerColor: AppColors.divider,
                    tabs: const [
                      Tab(text: '收藏'),
                      Tab(text: '下载'),
                      Tab(text: '提问'),
                    ],
                  ),
                ),
              ),
            ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildFavoritesTab(),
            _buildDownloadsTab(),
            _buildQuestionsTab(),
          ],
        ),
      ),
    );
  }

  // ==================== 未登录 ====================

  Widget _buildUnauthenticated() {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_outline,
              size: 64,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 16),
            const Text('未登录', style: TextStyle(color: AppColors.textHint)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => ref.read(authProvider.notifier).logout(),
              child: const Text('去登录'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 封面头部 ====================

  Widget _buildHeader(Map<String, dynamic>? p) {
    final topPadding = MediaQuery.of(context).padding.top;
    final nickname = p?['nickname'] ?? '用户';
    final phone = p?['phone'] ?? '';
    final memberType = p?['member_type'] ?? 'free';
    final coverUrl = UrlUtils.absolute(p?['cover_url']?.toString());

    String memberLabel;
    Color memberColor;
    Color memberBgColor;
    if (memberType == 'flagship') {
      memberLabel = '专业版会员';
      memberColor = AppColors.memberFlagship;
      memberBgColor = AppColors.memberFlagship.withValues(alpha: 0.15);
    } else if (memberType == 'pro') {
      memberLabel = '标准版会员';
      memberColor = AppColors.memberPro;
      memberBgColor = AppColors.memberPro.withValues(alpha: 0.15);
    } else {
      memberLabel = '普通用户';
      memberColor = AppColors.textHint;
      memberBgColor = AppColors.surface;
    }

    final favoriteCount = _groups.fold<int>(0, (sum, g) => sum + g.itemCount);
    final downloadCount = p?['monthly_download_count'] ?? 0;

    return Container(
      height: 236 + topPadding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: AppColors.surface),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (coverUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: coverUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _buildDefaultCover(),
                  )
                else
                  _buildDefaultCover(),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.18),
                          Colors.black.withValues(alpha: 0.45),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: topPadding + 8,
                  left: 12,
                  child: GestureDetector(
                    onTap: () => _changeCover(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
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
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: topPadding + 4,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                    onPressed: _showSettingsSheet,
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 66,
                  child: Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 29,
                          backgroundColor: AppColors.primaryLight,
                          child: Text(
                            nickname.isNotEmpty ? nickname[0] : '?',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nickname,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                shadows: [
                                  Shadow(blurRadius: 6, color: Colors.black26),
                                ],
                              ),
                            ),
                            if (phone.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  phone,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: memberBgColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                memberLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: memberColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 40,
                  right: 40,
                  bottom: 18,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatItem(count: favoriteCount, label: '收藏'),
                      _StatItem(count: downloadCount as int, label: '下载'),
                      _StatItem(count: _questionTotal, label: '提问'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultCover() {
    return Image.asset(
      'assets/images/covers/default_profile_cover.png',
      fit: BoxFit.cover,
      errorBuilder:
          (_, __, ___) => Container(
            decoration: const BoxDecoration(color: AppColors.surfaceVariant),
            child: const Center(
              child: Icon(
                Icons.landscape_outlined,
                size: 44,
                color: AppColors.textDisabled,
              ),
            ),
          ),
    );
  }

  // ==================== 快捷入口卡片 ====================

  Widget _buildQuickEntries(Map<String, dynamic>? p) {
    final memberType = p?['member_type'] ?? 'free';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: _QuickEntryCard(
              icon: Icons.card_membership,
              iconColor: AppColors.memberFlagship,
              title: '会员中心',
              subtitle: memberType == 'free' ? '开通更多权益' : '管理会员',
              onTap: () async {
                await context.push('/membership');
                if (!mounted) return;
                ref.invalidate(profileProvider);
                await ref.read(authProvider.notifier).refreshUserProfile();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickEntryCard(
              icon: Icons.lock_outline,
              iconColor: AppColors.textSecondary,
              title: '修改密码',
              subtitle: '账号安全',
              onTap: () => context.push('/change-password'),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 设置弹窗 ====================

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('修改密码'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/change-password');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.phonelink_lock_outlined),
                  title: const Text('解绑当前设备'),
                  subtitle: const Text('换机登录前请先解绑'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _unbindCurrentDevice();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于小颜圈'),
                  onTap: () => Navigator.pop(ctx),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: AppColors.error),
                  title: const Text(
                    '退出登录',
                    style: TextStyle(color: AppColors.error),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(authProvider.notifier).logout();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  Future<void> _unbindCurrentDevice() async {
    final shouldUnbind = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('解绑当前设备'),
            content: const Text('解绑后需要重新登录，是否继续？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确认解绑'),
              ),
            ],
          ),
    );
    if (shouldUnbind != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在解绑设备...')));
    try {
      final resp = await _http.post(Api.authDeviceUnbind);
      messenger.hideCurrentSnackBar();
      if (resp.isSuccess) {
        await ref.read(authProvider.notifier).logout();
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(content: Text('设备解绑成功，请重新登录')));
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(resp.message.isNotEmpty ? resp.message : '设备解绑失败'),
        ),
      );
    } catch (_) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('解绑失败，请稍后重试')));
    }
  }

  // ==================== Tab 内容 ====================

  Widget _buildFavoritesTab() {
    if (_groupsLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.collections_bookmark_outlined,
              size: 48,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 12),
            const Text(
              '还没有收藏分组',
              style: TextStyle(color: AppColors.textHint, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _createGroup,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('创建分组'),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              const Text(
                '收藏分组',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _createGroup,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建分组'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemCount: _groups.length,
            itemBuilder: (context, index) {
              final group = _groups[index];
              return FavoriteGroupCard(
                group: group,
                onTap: () async {
                  final result = await context.push<bool>(
                    '/favorite-group/${group.id}',
                    extra: group.name,
                  );
                  if (result == true) _loadGroups();
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadsTab() {
    if (_downloadsLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_downloads.isEmpty) {
      return const Center(
        child: Text(
          '暂无下载记录',
          style: TextStyle(color: AppColors.textHint, fontSize: 14),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _downloads.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder:
          (context, index) => DownloadListItem(item: _downloads[index]),
    );
  }

  Widget _buildQuestionsTab() {
    if (_questionsLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_questions.isEmpty) {
      return const Center(
        child: Text(
          '暂无提问',
          style: TextStyle(color: AppColors.textHint, fontSize: 14),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _questions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder:
          (context, index) => QuestionListItem(item: _questions[index]),
    );
  }
}

// ==================== 统计数字 ====================

class _StatItem extends StatelessWidget {
  final int count;
  final String label;
  const _StatItem({required this.count, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            shadows: [Shadow(blurRadius: 6, color: Colors.black26)],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}

// ==================== 快捷入口卡片 ====================

class _QuickEntryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickEntryCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
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
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: AppColors.textHint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 粘性 TabBar Delegate ====================

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _StickyTabBarDelegate({required this.tabBar});

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: AppColors.scaffoldBg, child: tabBar);
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) => false;
}
