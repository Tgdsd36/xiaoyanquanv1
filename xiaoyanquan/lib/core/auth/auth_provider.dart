import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      return '网络错误，请检查网络连接';
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
      return '网络错误，请检查网络连接';
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
      return '网络错误，请检查网络连接';
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
      return '网络错误，请检查网络连接';
    }
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

  bool get isGuest => state.status == AuthStatus.guest;
  bool get isAuthenticated => state.status == AuthStatus.authenticated;
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
