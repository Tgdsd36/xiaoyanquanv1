import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/constants/api.dart';
import '../../../core/network/http_client.dart';

final profileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final auth = ref.watch(authProvider);
  if (auth.status != AuthStatus.authenticated) return null;
  try {
    final resp = await HttpClient().get(Api.userProfile);
    if (resp.isSuccess) return resp.data;
  } catch (_) {}
  return null;
});

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);

    if (authState.status == AuthStatus.unauthenticated ||
        authState.status == AuthStatus.guest) {
      return Scaffold(
        appBar: AppBar(title: const Text('我的')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_outline, size: 64, color: Colors.grey[600]),
              const SizedBox(height: 16),
              Text('未登录', style: TextStyle(color: Colors.grey[500])),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  ref.read(authProvider.notifier).logout();
                },
                child: const Text('去登录'),
              ),
            ],
          ),
        ),
      );
    }

    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: profileAsync.when(
        data: (profile) => _buildContent(context, ref, profile, theme),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _buildContent(context, ref, null, theme),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, WidgetRef ref, Map<String, dynamic>? p, ThemeData theme) {
    final nickname = p?['nickname'] ?? '用户';
    final phone = p?['phone'] ?? '';
    final memberType = p?['member_type'] ?? 'free';
    final downloadCount = p?['monthly_download_count'] ?? 0;
    final downloadLimit = p?['monthly_download_limit'] ?? 0;

    String memberLabel;
    Color memberColor;
    switch (memberType) {
      case 'pro':
        memberLabel = '专业版会员';
        memberColor = Colors.blue;
      case 'flagship':
        memberLabel = '旗舰版会员';
        memberColor = Colors.amber;
      default:
        memberLabel = '普通用户';
        memberColor = Colors.grey;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 用户信息卡片
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                  child: Text(
                    nickname.isNotEmpty ? nickname[0] : '?',
                    style: TextStyle(
                        fontSize: 24, color: theme.colorScheme.primary),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nickname,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(phone,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[500])),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: memberColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(memberLabel,
                      style: TextStyle(fontSize: 12, color: memberColor)),
                ),
              ],
            ),
          ),
          // 下载额度
          if (memberType != 'free') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('本月下载', style: TextStyle(fontSize: 13)),
                      Text('$downloadCount / $downloadLimit',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[400])),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: downloadLimit > 0
                        ? (downloadCount as int) / (downloadLimit as int)
                        : 0,
                    backgroundColor: Colors.grey[800],
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          // 功能入口
          _MenuItem(Icons.card_membership, '会员中心',
              onTap: () => context.push('/membership')),
          _MenuItem(Icons.favorite_outline, '我的收藏',
              onTap: () => context.push('/my-favorites')),
          _MenuItem(Icons.download_outlined, '下载记录',
              onTap: () => context.push('/my-downloads')),
          _MenuItem(Icons.help_outline, '我的提问',
              onTap: () => context.push('/my-questions')),
          _MenuItem(Icons.lock_outline, '修改密码',
              onTap: () => context.push('/change-password')),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => ref.read(authProvider.notifier).logout(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
              child: const Text('退出登录'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _MenuItem(this.icon, this.title, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey[400]),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      trailing: Icon(Icons.chevron_right, color: Colors.grey[600]),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
