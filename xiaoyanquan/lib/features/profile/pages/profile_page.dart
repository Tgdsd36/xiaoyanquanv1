import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/colors.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/constants/api.dart';
import '../../../core/network/http_client.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadGroups();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    switch (_tabController.index) {
      case 0:
        if (_groupsLoading && _groups.isEmpty) _loadGroups();
      case 1:
        if (_downloadsLoading && _downloads.isEmpty) _loadDownloads();
      case 2:
        if (_questionsLoading && _questions.isEmpty) _loadQuestions();
    }
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
          _downloads =
              List<Map<String, dynamic>>.from(resp.data['list'] ?? []);
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
        setState(() {
          _questions =
              List<Map<String, dynamic>>.from(resp.data['list'] ?? []);
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
      builder: (ctx) => AlertDialog(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? '创建失败')),
      );
    }
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
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
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
                    fontSize: 15, fontWeight: FontWeight.w600),
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
            const Icon(Icons.person_outline,
                size: 64, color: AppColors.textHint),
            const SizedBox(height: 16),
            const Text('未登录',
                style: TextStyle(color: AppColors.textHint)),
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

  // ==================== 渐变头部 ====================

  Widget _buildHeader(Map<String, dynamic>? p) {
    final topPadding = MediaQuery.of(context).padding.top;
    final nickname = p?['nickname'] ?? '用户';
    final phone = p?['phone'] ?? '';
    final memberType = p?['member_type'] ?? 'free';

    String memberLabel;
    Color memberColor;
    Color memberBgColor;
    switch (memberType) {
      case 'pro':
        memberLabel = '专业版会员';
        memberColor = AppColors.memberPro;
        memberBgColor = AppColors.memberPro.withValues(alpha: 0.15);
      case 'flagship':
        memberLabel = '旗舰版会员';
        memberColor = AppColors.memberFlagship;
        memberBgColor = AppColors.memberFlagship.withValues(alpha: 0.15);
      default:
        memberLabel = '普通用户';
        memberColor = AppColors.textHint;
        memberBgColor = AppColors.surface;
    }

    final favoriteCount = _groups.fold<int>(0, (sum, g) => sum + g.itemCount);
    final downloadCount = p?['monthly_download_count'] ?? 0;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary,       // #FF2442
            Color(0xFFFF8A9B), // 过渡粉
            Colors.white,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Column(
        children: [
          // 顶部安全区 + 设置按钮
          Padding(
            padding: EdgeInsets.only(top: topPadding + 4, right: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.settings_outlined,
                      color: Colors.white, size: 22),
                  onPressed: _showSettingsSheet,
                ),
              ],
            ),
          ),
          // 用户信息
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
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
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
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
          const SizedBox(height: 20),
          // 统计行
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(count: favoriteCount, label: '收藏'),
                _StatItem(count: downloadCount as int, label: '下载'),
                _StatItem(count: _questions.length, label: '提问'),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ==================== 快捷入口卡片 ====================

  Widget _buildQuickEntries(Map<String, dynamic>? p) {
    final memberType = p?['member_type'] ?? 'free';
    final downloadCount = p?['monthly_download_count'] ?? 0;
    final downloadLimit = p?['monthly_download_limit'] ?? 0;

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
              onTap: () => context.push('/membership'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickEntryCard(
              icon: Icons.download_outlined,
              iconColor: AppColors.memberPro,
              title: '下载额度',
              subtitle: downloadLimit > 0
                  ? '$downloadCount/$downloadLimit 本月'
                  : '开通会员解锁',
              onTap: () => context.push('/membership'),
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
      builder: (ctx) => SafeArea(
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
              leading: const Icon(Icons.info_outline),
              title: const Text('关于小颜圈'),
              onTap: () => Navigator.pop(ctx),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.error),
              title: const Text('退出登录',
                  style: TextStyle(color: AppColors.error)),
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

  // ==================== Tab 内容 ====================

  Widget _buildFavoritesTab() {
    if (_groupsLoading) {
      return const Center(
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.collections_bookmark_outlined,
                size: 48, color: AppColors.textDisabled),
            const SizedBox(height: 12),
            const Text('还没有收藏分组',
                style:
                    TextStyle(color: AppColors.textHint, fontSize: 14)),
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
    return GridView.builder(
      padding: const EdgeInsets.all(16),
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
    );
  }

  Widget _buildDownloadsTab() {
    if (_downloadsLoading) {
      return const Center(
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_downloads.isEmpty) {
      return const Center(
        child: Text('暂无下载记录',
            style: TextStyle(color: AppColors.textHint, fontSize: 14)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _downloads.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) =>
          DownloadListItem(item: _downloads[index]),
    );
  }

  Widget _buildQuestionsTab() {
    if (_questionsLoading) {
      return const Center(
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_questions.isEmpty) {
      return const Center(
        child: Text('暂无提问',
            style: TextStyle(color: AppColors.textHint, fontSize: 14)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _questions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) =>
          QuestionListItem(item: _questions[index]),
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
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.scaffoldBg,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) => false;
}
