import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/colors.dart';
import '../../../app/styles.dart';
import '../../../core/constants/api.dart';
import '../../../core/network/http_client.dart';

final membershipStatusProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  try {
    final resp = await HttpClient().get(Api.membershipStatus);
    if (resp.isSuccess) return resp.data;
  } catch (_) {}
  return null;
});

class MembershipPage extends ConsumerWidget {
  const MembershipPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(membershipStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('会员中心')),
      body: statusAsync.when(
        data: (status) {
          final memberType = status?['member_type'] ?? 'free';
          final isActive = status?['is_active'] ?? false;
          final daysRemaining = status?['days_remaining'] ?? 0;
          final downloadCount = status?['monthly_download_count'] ?? 0;
          final downloadLimit = status?['monthly_download_limit'] ?? 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // 当前状态
                if (isActive == true)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: memberType == 'flagship'
                            ? [AppColors.memberFlagship, AppColors.memberFlagshipEnd]
                            : [AppColors.memberPro, AppColors.memberProEnd],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          memberType == 'flagship' ? '旗舰版会员' : '专业版会员',
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text('剩余 $daysRemaining 天  |  本月下载 $downloadCount/$downloadLimit',
                            style: const TextStyle(
                                fontSize: 13, color: Colors.white70)),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('选择套餐',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 16),
                // 专业版
                _PlanCard(
                  title: '专业版',
                  price: '¥299/月',
                  features: const [
                    '每月 5000 次下载',
                    '全部素材浏览',
                    '收藏 & 提问功能',
                  ],
                  color: Colors.blue,
                  onTap: () => _purchase(context, ref, 'pro_monthly'),
                ),
                const SizedBox(height: 12),
                // 旗舰版
                _PlanCard(
                  title: '旗舰版',
                  price: '¥499/月',
                  features: const [
                    '每月 10000 次下载',
                    '精准推荐算法',
                    '优先客服支持',
                    '全部专业版权益',
                  ],
                  color: Colors.amber,
                  isRecommended: true,
                  onTap: () => _purchase(context, ref, 'flagship_monthly'),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('加载失败')),
      ),
    );
  }

  Future<void> _purchase(
      BuildContext context, WidgetRef ref, String planType) async {
    try {
      final resp = await HttpClient().post(Api.membershipPurchase, data: {
        'plan_type': planType,
        'payment_channel': 'apple_iap',
      });
      if (resp.isSuccess && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('开通成功！')));
        ref.invalidate(membershipStatusProvider);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(resp.message)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('操作失败')));
      }
    }
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String price;
  final List<String> features;
  final Color color;
  final bool isRecommended;
  final VoidCallback onTap;

  const _PlanCard({
    required this.title,
    required this.price,
    required this.features,
    required this.color,
    this.isRecommended = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppStyles.cardShadow,
        border: isRecommended
            ? Border.all(color: color, width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color)),
              if (isRecommended) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('推荐',
                      style: TextStyle(fontSize: 10, color: color)),
                ),
              ],
              const Spacer(),
              Text(price,
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 12),
          ...features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 16, color: color),
                    const SizedBox(width: 8),
                    Text(f, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              )),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(backgroundColor: color),
              child: const Text('立即开通'),
            ),
          ),
        ],
      ),
    );
  }
}
