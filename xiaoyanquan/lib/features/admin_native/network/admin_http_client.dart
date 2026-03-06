import 'package:dio/dio.dart';
import '../../../core/constants/api.dart';
import '../auth/admin_auth_storage.dart';

class AdminHttpClient {
  static final AdminHttpClient _instance = AdminHttpClient._internal();
  factory AdminHttpClient() => _instance;

  final AdminAuthStorage _storage = AdminAuthStorage();
  late final Dio dio;

  AdminHttpClient._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: _adminBaseUrl(),
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 25),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _storage.token;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            await _storage.clear();
          }
          handler.next(error);
        },
      ),
    );
  }

  String _adminBaseUrl() {
    final userBase = Api.baseUrl.trim();
    if (userBase.isEmpty) return '/api/admin';
    if (userBase.contains('/api/v1')) {
      return userBase.replaceFirst('/api/v1', '/api/admin');
    }
    final normalized = userBase.endsWith('/')
        ? userBase.substring(0, userBase.length - 1)
        : userBase;
    return '$normalized/api/admin';
  }
}
