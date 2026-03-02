import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
      builder: (ctx) => AlertDialog(
        title: const Text('提示'),
        content: const Text('当前未接入验证码接口，验证码已自动输入'),
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
    final error =
        await ref.read(authProvider.notifier).passwordLogin(phone, password);
    if (error != null) _showError(error);
  }

  void _enterGuestMode() {
    ref.read(authProvider.notifier).enterGuestMode();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red[700]),
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
              Icon(Icons.camera_rounded,
                  size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text('小颜圈',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  )),
              const SizedBox(height: 8),
              Text('创作者的素材灵感库',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.grey[500])),
              const SizedBox(height: 40),
              // Tab 切换
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: '验证码登录'),
                  Tab(text: '密码登录'),
                ],
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
              onPressed: authState.isLoading ? null : _smsLogin,
              child: authState.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
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
                icon: Icon(_obscurePassword
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: authState.isLoading ? null : _passwordLogin,
              child: authState.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
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
      child: TextButton(
        onPressed: _enterGuestMode,
        child: const Text('游客浏览'),
      ),
    );
  }
}
