import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../constants/api.dart';
import '../network/http_client.dart';
import '../storage/token_storage.dart';
import '../../features/auth/models/user_model.dart';
import '../../features/auth/repositories/auth_repository.dart';

enum AuthStatus { guest, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final bool isLoading;
  final String? error;

  const AuthState({
    required this.status,
    this.user,
    this.isLoading = false,
    this.error,
  });

  factory AuthState.initial() {
    final storage = TokenStorage();
    if (storage.isLoggedIn) {
      return const AuthState(status: AuthStatus.authenticated);
    }
    return const AuthState(status: AuthStatus.unauthenticated);
  }

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final TokenStorage _storage = TokenStorage();
  final AuthRepository _repo = AuthRepository();
  final HttpClient _http = HttpClient();
  static const int _errCodeDeviceBoundOther = 10007;

  AuthNotifier() : super(AuthState.initial());

  /// 处理登录/注册成功响应
  Future<void> _handleAuthResponse(Map<String, dynamic> data) async {
    await _storage.saveTokens(data['access_token'], data['refresh_token']);
    final user = UserModel.fromJson(data['user']);
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  /// 发送短信验证码
  Future<String?> sendSMS(String phone) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final resp = await _repo.sendSMS(phone);
      state = state.copyWith(isLoading: false);
      if (!resp.isSuccess) return resp.message;
      return null; // 成功
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return _mapAuthError(e);
    }
  }

  /// 短信验证码登录
  Future<String?> smsLogin(String phone, String code) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final resp = await _repo.smsLogin(phone: phone, code: code);
      if (resp.isSuccess) {
        await _handleAuthResponse(resp.data);
        return null;
      }
      state = state.copyWith(isLoading: false);
      return resp.message;
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return _mapAuthError(e);
    }
  }

  /// 密码登录
  Future<String?> passwordLogin(String phone, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final resp = await _repo.passwordLogin(phone: phone, password: password);
      if (resp.isSuccess) {
        await _handleAuthResponse(resp.data);
        return null;
      }
      state = state.copyWith(isLoading: false);
      return resp.message;
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return _mapAuthError(e);
    }
  }

  /// 注册
  Future<String?> register({
    required String phone,
    required String code,
    required String password,
    String? nickname,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final resp = await _repo.register(
        phone: phone,
        code: code,
        password: password,
        nickname: nickname,
      );
      if (resp.isSuccess) {
        await _handleAuthResponse(resp.data);
        return null;
      }
      state = state.copyWith(isLoading: false);
      return resp.message;
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return _mapAuthError(e);
    }
  }

  String _mapAuthError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final code = data['code'];
        final message = (data['message'] ?? '').toString().trim();
        if (code == _errCodeDeviceBoundOther || _isDeviceBoundMessage(message)) {
          return '该账号设备未解除，请先在旧设备解绑后再登录';
        }
        if (message.isNotEmpty) {
          return message;
        }
      }
      if (data is String) {
        final message = data.trim();
        if (message.isNotEmpty && !message.startsWith('<')) {
          if (_isDeviceBoundMessage(message)) {
            return '该账号设备未解除，请先在旧设备解绑后再登录';
          }
          return message;
        }
      }

      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return '网络错误，请检查网络连接';
      }

      if (_isDeviceBoundMessage(error.message ?? '')) {
        return '该账号设备未解除，请先在旧设备解绑后再登录';
      }

      if (error.message != null && error.message!.trim().isNotEmpty) {
        return error.message!.trim();
      }
    }

    return '网络错误，请检查网络连接';
  }

  bool _isDeviceBoundMessage(String message) {
    if (message.isEmpty) return false;
    return message.contains('绑定其他设备') ||
        message.contains('原设备解绑') ||
        message.contains('账号已绑定设备') ||
        message.contains('设备未解除');
  }

  /// 游客模式
  void enterGuestMode() {
    state = const AuthState(status: AuthStatus.guest);
  }

  /// 登出
  Future<void> logout() async {
    await _storage.clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// 拉取最新个人信息，同步会员状态（会员类型/到期时间）
  Future<void> refreshUserProfile() async {
    if (state.status != AuthStatus.authenticated) return;
    try {
      final resp = await _http.get(Api.userProfile);
      if (!resp.isSuccess || resp.data is! Map) return;
      final profile = Map<String, dynamic>.from(resp.data as Map);
      final current = state.user;

      final updated = UserModel(
        id: _toInt(profile['id']) ?? current?.id ?? 0,
        phone: (profile['phone'] ?? current?.phone ?? '').toString(),
        nickname: (profile['nickname'] ?? current?.nickname ?? '').toString(),
        avatarUrl:
            (profile['avatar_url'] ?? current?.avatarUrl ?? '').toString(),
        memberType:
            (profile['member_type'] ?? current?.memberType ?? 'free')
                .toString(),
        memberExpireAt:
            _parseDate(profile['member_expire_at']) ?? current?.memberExpireAt,
        isNewUser: current?.isNewUser ?? false,
      );

      state = state.copyWith(user: updated, error: null);
    } catch (_) {
      // 静默失败，避免影响当前页面体验
    }
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  DateTime? _parseDate(dynamic raw) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  bool get isGuest => state.status == AuthStatus.guest;
  bool get isAuthenticated => state.status == AuthStatus.authenticated;
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
