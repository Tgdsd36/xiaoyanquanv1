import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/colors.dart';
import '../../../core/auth/auth_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _agreedTerms = false;

  // 验证码登录
  final _smsPhoneController = TextEditingController();
  final _smsCodeController = TextEditingController();
  int _countdown = 0;
  Timer? _timer;

  // 密码登录
  final _pwdPhoneController = TextEditingController();
  final _pwdPasswordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _smsPhoneController.dispose();
    _smsCodeController.dispose();
    _pwdPhoneController.dispose();
    _pwdPasswordController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _sendSMS() async {
    final phone = _smsPhoneController.text.trim();
    if (phone.length != 11) {
      _showError('请输入正确的手机号');
      return;
    }
    // 未接入验证码接口，弹窗提示并自动填入
    final mockCode = '${1000 + Random().nextInt(9000)}';
    if (!mounted) return;
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('提示'),
            content: const Text('未开启短信发送，系统自动填写验证码，直接登录即可。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
    );
    _smsCodeController.text = mockCode;
    _startCountdown();
  }

  Future<void> _smsLogin() async {
    if (!_agreedTerms) {
      _showError('请先勾选并同意《注册协议》和《隐私条款》');
      return;
    }
    final phone = _smsPhoneController.text.trim();
    final code = _smsCodeController.text.trim();
    if (phone.length != 11) {
      _showError('请输入正确的手机号');
      return;
    }
    if (code.length != 4) {
      _showError('请输入4位验证码');
      return;
    }
    final error = await ref.read(authProvider.notifier).smsLogin(phone, code);
    if (error != null) _showError(error);
  }

  Future<void> _passwordLogin() async {
    if (!_agreedTerms) {
      _showError('请先勾选并同意《注册协议》和《隐私条款》');
      return;
    }
    final phone = _pwdPhoneController.text.trim();
    final password = _pwdPasswordController.text;
    if (phone.length != 11) {
      _showError('请输入正确的手机号');
      return;
    }
    if (password.length < 6) {
      _showError('密码不少于6位');
      return;
    }
    final error = await ref
        .read(authProvider.notifier)
        .passwordLogin(phone, password);
    if (error != null) _showError(error);
  }

  void _enterGuestMode() {
    ref.read(authProvider.notifier).enterGuestMode();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  Future<void> _openLegalDocument(String title, String content) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (ctx) => SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.8,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                      child: Text(
                        content,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.65,
                          color: AppColors.textBody,
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

  Widget _buildAgreementSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Transform.translate(
          offset: const Offset(-10, -2),
          child: Checkbox(
            value: _agreedTerms,
            onChanged: (v) => setState(() => _agreedTerms = v ?? false),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  '我已阅读并同意',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                GestureDetector(
                  onTap:
                      () => _openLegalDocument('注册协议', _AuthLegal.termsContent),
                  child: const Text(
                    '《注册协议》',
                    style: TextStyle(fontSize: 13, color: AppColors.primary),
                  ),
                ),
                const Text(
                  '和',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                GestureDetector(
                  onTap:
                      () =>
                          _openLegalDocument('隐私条款', _AuthLegal.privacyContent),
                  child: const Text(
                    '《隐私条款》',
                    style: TextStyle(fontSize: 13, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 60),
              // Logo
              Icon(
                Icons.camera_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                '小颜圈',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '创作者的素材灵感库',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textHint,
                ),
              ),
              const SizedBox(height: 40),
              // Tab 切换
              TabBar(
                controller: _tabController,
                tabs: const [Tab(text: '验证码登录'), Tab(text: '密码登录')],
              ),
              const SizedBox(height: 24),
              // Tab 内容
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildSMSLoginForm(authState),
                    _buildPasswordLoginForm(authState),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _buildAgreementSection(),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSMSLoginForm(AuthState authState) {
    return SingleChildScrollView(
      child: Column(
        children: [
          TextField(
            controller: _smsPhoneController,
            keyboardType: TextInputType.phone,
            maxLength: 11,
            decoration: const InputDecoration(
              hintText: '请输入手机号',
              prefixIcon: Icon(Icons.phone_android),
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _smsCodeController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    hintText: '请输入验证码',
                    prefixIcon: Icon(Icons.lock_outline),
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                height: 48,
                child: ElevatedButton(
                  onPressed:
                      _countdown > 0 || authState.isLoading ? null : _sendSMS,
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _countdown > 0 ? '${_countdown}s' : '获取验证码',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  (authState.isLoading || !_agreedTerms) ? null : _smsLogin,
              child:
                  authState.isLoading
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Text('登录'),
            ),
          ),
          const SizedBox(height: 16),
          _buildBottomActions(),
        ],
      ),
    );
  }

  Widget _buildPasswordLoginForm(AuthState authState) {
    return SingleChildScrollView(
      child: Column(
        children: [
          TextField(
            controller: _pwdPhoneController,
            keyboardType: TextInputType.phone,
            maxLength: 11,
            decoration: const InputDecoration(
              hintText: '请输入手机号',
              prefixIcon: Icon(Icons.phone_android),
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pwdPasswordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              hintText: '请输入密码',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed:
                    () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  (authState.isLoading || !_agreedTerms)
                      ? null
                      : _passwordLogin,
              child:
                  authState.isLoading
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Text('登录'),
            ),
          ),
          const SizedBox(height: 16),
          _buildBottomActions(),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Center(
      child: TextButton(onPressed: _enterGuestMode, child: const Text('游客浏览')),
    );
  }
}

class _AuthLegal {
  static const String termsContent = '''
《小颜圈注册协议》
生效日期：2026年3月4日

欢迎您使用小颜圈服务。为保障您的合法权益，请在注册或登录前仔细阅读本协议。您勾选“我已阅读并同意”并完成登录，即视为您已阅读、理解并接受本协议全部条款。

一、服务内容
1. 小颜圈为用户提供素材浏览、收藏、下载、提问、会员订阅等功能服务。
2. 小颜圈有权根据业务发展对功能进行调整、优化或下线，相关变更将以站内公告或页面提示方式通知。

二、账号与安全
1. 您应使用本人合法持有的手机号注册和登录，不得冒用他人身份。
2. 您应妥善保管账号及验证码/密码信息，因您保管不当造成的损失由您自行承担。
3. 如发现账号存在异常登录或安全风险，请及时联系平台处理。

三、用户行为规范
1. 您不得利用本平台从事违法违规活动，不得发布、传播侵犯他人合法权益的内容。
2. 未经授权，您不得以爬虫、批量抓取、接口滥用等方式获取平台数据。
3. 您不得对平台进行干扰、破坏、逆向工程或其他危害系统安全的行为。

四、素材使用与知识产权
1. 平台素材及相关内容的著作权、商标权等知识产权归权利人或平台依法享有。
2. 您应按照页面提示、会员权益及授权规则使用素材，不得超范围使用。
3. 如因您违规使用素材导致纠纷或损失，责任由您自行承担。

五、会员与付费
1. 会员服务为有偿服务，具体权益、价格及有效期以会员页面展示为准。
2. 会员开通后，除法律法规另有规定外，已生效的服务不支持无理由退款。
3. 因支付渠道、网络或系统故障导致异常的，平台将协助核验处理。

六、违约处理
1. 如您违反本协议或相关规则，平台有权采取限制功能、暂停服务或封禁账号等措施。
2. 因您的违规行为导致平台或第三方损失的，您应依法承担赔偿责任。

七、免责声明
1. 在法律允许范围内，平台对因不可抗力、网络故障、第三方原因导致的服务中断不承担责任。
2. 平台将尽力保障服务稳定，但不承诺服务绝对不中断或无瑕疵。

八、协议变更
1. 平台可根据业务变化对本协议进行更新。
2. 更新后协议将通过页面公示方式发布，继续使用服务即视为您接受更新后的协议。

九、联系我们
如您对本协议有疑问，可通过应用内客服入口联系小颜圈团队。
''';

  static const String privacyContent = '''
《小颜圈隐私条款》
生效日期：2026年3月4日

小颜圈非常重视您的个人信息和隐私保护。请您在使用服务前仔细阅读本条款。

一、我们收集的信息
1. 账号信息：手机号、昵称、头像等您主动提供的信息。
2. 使用信息：登录日志、浏览记录、收藏记录、下载记录、提问记录等。
3. 设备与网络信息：设备型号、系统版本、应用版本、IP地址、网络状态等。

二、信息使用目的
1. 提供账号登录、身份校验、基础功能服务。
2. 保障账号与交易安全，识别异常行为和风险。
3. 优化产品体验、进行统计分析与功能改进。
4. 按您的选择提供会员服务、消息通知与客户支持。

三、信息共享与披露
1. 我们不会向无关第三方出售您的个人信息。
2. 在以下情形下，可能进行必要共享：
   - 获得您的明确授权；
   - 为完成支付、云存储、消息推送等必要服务；
   - 依据法律法规或有权机关要求。
3. 我们会要求合作方采取不低于本条款的保护措施。

四、信息存储与保护
1. 我们采取合理的技术与管理措施保护您的信息安全。
2. 我们仅在实现目的所需期限内保存您的信息，法律法规另有要求除外。

五、您的权利
1. 您有权查询、更正、补充您的个人信息。
2. 您有权申请删除个人信息或注销账号（法律法规另有规定除外）。
3. 您可通过应用内入口管理授权、修改资料或联系我们处理相关请求。

六、未成年人保护
若您为未成年人，请在监护人指导下阅读并使用本服务。

七、条款更新
我们可能根据业务变化更新本条款，并通过页面公示。更新后继续使用即视为您接受更新内容。

八、联系我们
如对隐私条款有疑问、意见或投诉，请通过应用内客服入口联系我们。
''';
}
