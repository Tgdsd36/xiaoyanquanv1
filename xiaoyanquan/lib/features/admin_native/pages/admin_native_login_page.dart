import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

    setState(() => _submitting = true);
    try {
      final resp = await AdminHttpClient().dio.post('/login', data: {
        'username': _usernameController.text.trim(),
        'password': _passwordController.text,
      });
      final data = resp.data as Map<String, dynamic>;
      if ((data['code'] ?? -1) != 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((data['message'] ?? '登录失败').toString())),
        );
        return;
      }
      final payload = (data['data'] as Map?)?.cast<String, dynamic>() ?? {};
      final token = (payload['token'] ?? '').toString();
      final username = (payload['username'] ?? _usernameController.text.trim())
          .toString();
      final role = (payload['role'] ?? 'admin').toString();
      if (token.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('登录失败：未返回管理员凭证')),
        );
        return;
      }

      await _storage.saveSession(token: token, username: username, role: role);
      if (!mounted) return;
      context.go('/admin-native/workbench');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('管理员登录失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('管理员工作台登录')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Icon(Icons.admin_panel_settings_outlined, size: 52),
                const SizedBox(height: 12),
                const Text(
                  '小颜圈 · 管理员入口',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: '管理员账号',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入管理员账号' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '管理员密码',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? '请输入管理员密码' : null,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _login,
                    child: Text(_submitting ? '登录中...' : '进入管理员工作台'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
