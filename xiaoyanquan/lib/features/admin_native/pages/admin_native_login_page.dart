import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../app/colors.dart';
import '../auth/admin_auth_storage.dart';
import '../network/admin_http_client.dart';

class AdminNativeLoginPage extends StatefulWidget {
  const AdminNativeLoginPage({super.key});

  @override
  State<AdminNativeLoginPage> createState() => _AdminNativeLoginPageState();
}

class _AdminNativeLoginPageState extends State<AdminNativeLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _storage = AdminAuthStorage();
  bool _submitting = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    if (_storage.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go('/admin-native/workbench');
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);
    try {
      final resp = await AdminHttpClient().dio.post('/login', data: {
        'username': _usernameController.text.trim(),
        'password': _passwordController.text,
      });
      final data = resp.data as Map<String, dynamic>;
      if ((data['code'] ?? -1) != 0) {
        if (!mounted) return;
        _showError((data['message'] ?? '登录失败').toString());
        return;
      }
      final payload = (data['data'] as Map?)?.cast<String, dynamic>() ?? {};
      final token = (payload['token'] ?? '').toString();
      final username = (payload['username'] ?? _usernameController.text.trim())
          .toString();
      final role = (payload['role'] ?? 'admin').toString();
      if (token.isEmpty) {
        if (!mounted) return;
        _showError('登录失败：未返回管理员凭证');
        return;
      }

      await _storage.saveSession(token: token, username: username, role: role);
      if (!mounted) return;
      context.go('/admin-native/workbench');
    } catch (e) {
      if (!mounted) return;
      _showError('网络异常，请检查后重试');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── 顶部渐变头区 ──
            _buildHeader(context),
            // ── 表单卡片 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: _buildFormCard(),
            ),
            const SizedBox(height: 24),
            // ── 返回按钮 ──
            TextButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_ios_new,
                  size: 14, color: AppColors.textSecondary),
              label: const Text('返回素材库',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部深色渐变区域：盾牌图标 + 品牌文案
  Widget _buildHeader(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(top: topPad + 40, bottom: 48),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield_outlined,
                size: 36, color: Colors.white),
          ),
          const SizedBox(height: 16),
          const Text('管理员工作台',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1)),
          const SizedBox(height: 6),
          Text('小颜圈 · 内容管理中心',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13)),
        ],
      ),
    );
  }

  /// 表单卡片：向上偏移与头部区域衔接
  Widget _buildFormCard() {
    return Transform.translate(
      offset: const Offset(0, -28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 账号输入 ──
              TextFormField(
                controller: _usernameController,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: '管理员账号',
                  hintStyle: const TextStyle(
                      color: AppColors.textHint, fontSize: 15),
                  prefixIcon: const Icon(Icons.person_outline,
                      color: AppColors.textHint, size: 20),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.error, width: 1),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.error, width: 1.5),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入管理员账号' : null,
              ),
              const SizedBox(height: 16),
              // ── 密码输入 ──
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: '管理员密码',
                  hintStyle: const TextStyle(
                      color: AppColors.textHint, fontSize: 15),
                  prefixIcon: const Icon(Icons.lock_outline,
                      color: AppColors.textHint, size: 20),
                  suffixIcon: GestureDetector(
                    onTap: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    child: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.textHint,
                      size: 20,
                    ),
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.error, width: 1),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.error, width: 1.5),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? '请输入管理员密码' : null,
              ),
              const SizedBox(height: 28),
              // ── 登录按钮 ──
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A2E),
                    disabledBackgroundColor:
                        const Color(0xFF1A1A2E).withValues(alpha: 0.5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('进入工作台',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
