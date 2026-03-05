import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/api.dart';
import '../../../core/network/http_client.dart';
import '../../../core/utils/url_utils.dart';

final membershipStatusProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  try {
    final resp = await HttpClient().get(Api.membershipStatus);
    if (resp.isSuccess && resp.data is Map<String, dynamic>) {
      return resp.data as Map<String, dynamic>;
    }
  } catch (_) {}
  return null;
});

final membershipProfileProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  try {
    final resp = await HttpClient().get(Api.userProfile);
    if (resp.isSuccess && resp.data is Map<String, dynamic>) {
      return resp.data as Map<String, dynamic>;
    }
  } catch (_) {}
  return null;
});

class MembershipPage extends ConsumerStatefulWidget {
  const MembershipPage({super.key});

  @override
  ConsumerState<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends ConsumerState<MembershipPage> {
  String? _selectedPlanId;
  bool _purchasing = false;

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(membershipStatusProvider);
    final profile = ref.watch(membershipProfileProvider).valueOrNull;

    return statusAsync.when(
      loading:
          () => _buildScaffold(
            body: const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            ),
          ),
      error:
          (_, __) => _buildScaffold(
            body: const Center(
              child: Text('加载失败', style: TextStyle(color: Colors.white70)),
            ),
          ),
      data: (status) {
        final data = status ?? <String, dynamic>{};
        final plans = _buildPlans(data);
        final selectedPlan = _resolveSelectedPlan(plans);

        final memberType = (data['member_type'] ?? 'free').toString();
        final isActive = data['is_active'] == true;
        final daysRemaining = _asInt(data['days_remaining']);

        final nickname = (profile?['nickname'] as String?)?.trim();
        final displayName =
            (nickname != null && nickname.isNotEmpty) ? nickname : '小颜圈用户';
        final avatarUrl = UrlUtils.absolute(profile?['avatar_url']?.toString());

        return _buildScaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _UserHeader(name: displayName, avatarUrl: avatarUrl),
                const SizedBox(height: 14),
                _MemberHeroCard(
                  memberType: memberType,
                  isActive: isActive,
                  daysRemaining: daysRemaining,
                ),
                const SizedBox(height: 16),
                _PlanSection(
                  plans: plans,
                  selectedPlanId: selectedPlan?.id,
                  onSelect: (plan) => setState(() => _selectedPlanId = plan.id),
                ),
                const SizedBox(height: 16),
                _BenefitSection(
                  title: '蓝金会员权益',
                  features: _buildFeatureList(selectedPlan),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          bottomBar:
              selectedPlan == null
                  ? null
                  : _BottomActionBar(
                    loading: _purchasing,
                    text:
                        '${selectedPlan.price.toStringAsFixed(2)}元${isActive ? '续费会员' : '开通会员'}',
                    onTap:
                        _purchasing ? null : () => _purchase(ref, selectedPlan),
                  ),
        );
      },
    );
  }

  Widget _buildScaffold({required Widget body, Widget? bottomBar}) {
    const background = Color(0xFF050B19);
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '会员中心',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: body,
      bottomNavigationBar: bottomBar,
    );
  }

  _MembershipPlan? _resolveSelectedPlan(List<_MembershipPlan> plans) {
    if (plans.isEmpty) return null;
    for (final plan in plans) {
      if (plan.id == _selectedPlanId) return plan;
    }
    return plans.first;
  }

  List<_MembershipPlan> _buildPlans(Map<String, dynamic> status) {
    String monthlyId = 'pro_monthly';
    String halfYearId = 'pro_half_yearly';
    String yearlyId = 'pro_yearly';

    final raw = status['plans'];
    if (raw is List && raw.isNotEmpty) {
      final rawPlans =
          raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
      monthlyId = _pickPlanId(rawPlans, const [
        'monthly',
        'month',
        'pro_monthly',
      ]);
      halfYearId = _pickPlanId(rawPlans, const [
        'half',
        'semi',
        '6m',
        'half_year',
      ]);
      yearlyId = _pickPlanId(rawPlans, const [
        'year',
        'annual',
        'yearly',
        '12m',
      ]);
      if (halfYearId.isEmpty) halfYearId = monthlyId;
      if (yearlyId.isEmpty) yearlyId = monthlyId;
    }

    return [
      _MembershipPlan(
        id: monthlyId,
        name: '蓝金会员',
        period: 'monthly',
        price: 298,
        originalPrice: 1980,
        features: ['蓝金会员权益', '无限下载', '全部素材浏览', '收藏与提问'],
      ),
      _MembershipPlan(
        id: halfYearId,
        name: '蓝金会员',
        period: 'half_yearly',
        price: 980,
        originalPrice: 2980,
        features: ['蓝金会员权益', '无限下载', '精准推荐算法', '优先客服支持'],
      ),
      _MembershipPlan(
        id: yearlyId,
        name: '蓝金会员',
        period: 'yearly',
        price: 1980,
        originalPrice: 3980,
        features: ['蓝金会员权益', '无限下载', '精准推荐算法', '优先客服支持'],
      ),
    ];
  }

  List<String> _buildFeatureList(_MembershipPlan? plan) {
    const base = <String>[
      '30万+组优质素材',
      '20万+精选文案',
      '场景分类一键触达',
      '素材高清无水印',
      '无限下载',
      '文案智能匹配',
    ];
    if (plan == null || plan.features.isEmpty) return base;
    final merged = <String>{...plan.features, ...base};
    return merged.toList();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _pickPlanId(List<Map<String, dynamic>> plans, List<String> hints) {
    for (final item in plans) {
      final id = (item['id'] ?? '').toString();
      final lower = id.toLowerCase();
      for (final hint in hints) {
        if (lower.contains(hint)) return id;
      }
    }
    return '';
  }

  Future<void> _purchase(WidgetRef ref, _MembershipPlan plan) async {
    if (_purchasing) return;
    setState(() => _purchasing = true);
    try {
      final resp = await HttpClient().post(
        Api.membershipPurchase,
        data: {
          'plan_id': plan.id,
          'plan_type': plan.id,
          'payment_channel': 'apple_iap',
        },
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      if (resp.isSuccess) {
        messenger.showSnackBar(const SnackBar(content: Text('开通成功，请完成支付确认')));
        ref.invalidate(membershipStatusProvider);
      } else {
        messenger.showSnackBar(SnackBar(content: Text(resp.message)));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('操作失败，请稍后重试')));
    } finally {
      if (mounted) {
        setState(() => _purchasing = false);
      }
    }
  }
}

class _UserHeader extends StatelessWidget {
  final String name;
  final String avatarUrl;

  const _UserHeader({required this.name, required this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF14213D),
            border: Border.all(color: Colors.white24),
            image:
                avatarUrl.isNotEmpty
                    ? DecorationImage(
                      image: NetworkImage(avatarUrl),
                      fit: BoxFit.cover,
                    )
                    : null,
          ),
          alignment: Alignment.center,
          child:
              avatarUrl.isEmpty
                  ? Text(
                    name.isNotEmpty ? name.characters.first : '友',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                  : null,
        ),
        const SizedBox(width: 10),
        Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _MemberHeroCard extends StatelessWidget {
  final String memberType;
  final bool isActive;
  final int daysRemaining;

  const _MemberHeroCard({
    required this.memberType,
    required this.isActive,
    required this.daysRemaining,
  });

  @override
  Widget build(BuildContext context) {
    const memberName = '蓝金会员';
    final desc = isActive ? '恭喜您成为尊贵的蓝金会员  剩余$daysRemaining天' : '开通蓝金会员后解锁全部权益';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF3F7FF), Color(0xFFDCE8FF)],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  memberName,
                  style: const TextStyle(
                    color: Color(0xFF3557B7),
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  desc,
                  style: const TextStyle(
                    color: Color(0xFF6B7DAA),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.85),
              border: Border.all(color: Colors.white),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x333557B7),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.diamond_rounded,
              color: Color(0xFF6B8CF6),
              size: 36,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanSection extends StatelessWidget {
  final List<_MembershipPlan> plans;
  final String? selectedPlanId;
  final ValueChanged<_MembershipPlan> onSelect;

  const _PlanSection({
    required this.plans,
    required this.selectedPlanId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: plans.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final plan = plans[index];
          final selected = plan.id == selectedPlanId;
          return _MembershipPlanCard(
            plan: plan,
            selected: selected,
            onTap: () => onSelect(plan),
          );
        },
      ),
    );
  }
}

class _MembershipPlanCard extends StatelessWidget {
  final _MembershipPlan plan;
  final bool selected;
  final VoidCallback onTap;

  const _MembershipPlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor =
        selected ? const Color(0xFFCC9958) : const Color(0xFF2A2A2A);
    final textColor =
        selected ? Colors.white : Colors.white.withValues(alpha: 0.92);
    final oldPriceColor =
        selected ? Colors.white.withValues(alpha: 0.72) : Colors.white54;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 158,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border:
              selected
                  ? Border.all(color: const Color(0xFFE8C08C), width: 1.2)
                  : Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.periodTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Text(
              '¥${plan.price.toStringAsFixed(2)}',
              style: TextStyle(
                color: textColor,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '¥${plan.originalPrice.toStringAsFixed(2)}',
              style: TextStyle(
                color: oldPriceColor,
                fontSize: 12,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitSection extends StatelessWidget {
  final String title;
  final List<String> features;

  const _BenefitSection({required this.title, required this.features});

  @override
  Widget build(BuildContext context) {
    const icons = <IconData>[
      Icons.folder_copy_outlined,
      Icons.chat_bubble_outline_rounded,
      Icons.list_alt_rounded,
      Icons.image_outlined,
      Icons.check_box_outlined,
      Icons.favorite_border_rounded,
      Icons.auto_awesome_rounded,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF091A35), Color(0xFF102A4A)],
        ),
        border: Border.all(color: const Color(0xFF233A67)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              '◆  $title  ◆',
              style: const TextStyle(
                color: Color(0xFF8FB0FF),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...features.asMap().entries.map((entry) {
            final index = entry.key;
            final text = entry.value;
            final icon = icons[index % icons.length];
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 22, color: const Color(0xFFF6DFA8)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: Color(0xFFF5E8C3),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  final bool loading;
  final String text;
  final VoidCallback? onTap;

  const _BottomActionBar({
    required this.loading,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: const Color(0xFFC08C4A),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFC8AE89),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            child:
                loading
                    ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                    : Text(
                      text,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
          ),
        ),
      ),
    );
  }
}

class _MembershipPlan {
  final String id;
  final String name;
  final String period;
  final double price;
  final double originalPrice;
  final List<String> features;

  const _MembershipPlan({
    required this.id,
    required this.name,
    required this.period,
    required this.price,
    required this.originalPrice,
    required this.features,
  });

  String get periodTitle {
    if (period == 'yearly') return '一年$name';
    if (period == 'half_yearly' || period == 'semiannual') return '半年$name';
    if (period == 'quarterly') return '三个月$name';
    return '一个月$name';
  }
}
