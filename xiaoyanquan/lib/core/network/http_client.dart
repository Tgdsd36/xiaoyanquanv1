import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../constants/api.dart';
import '../storage/token_storage.dart';

class HttpClient {
  static final HttpClient _instance = HttpClient._internal();
  factory HttpClient() => _instance;

  late final Dio dio;
  final TokenStorage _tokenStorage = TokenStorage();

  HttpClient._internal() {
    dio = Dio(BaseOptions(
      baseUrl: Api.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.addAll([
      _AuthInterceptor(dio, _tokenStorage),
      _RetryInterceptor(dio),
      if (kDebugMode) LogInterceptor(requestBody: true, responseBody: true),
    ]);
  }

  // GET
  Future<ApiResponse> get(String path, {Map<String, dynamic>? params}) async {
    final resp = await dio.get(path, queryParameters: params);
    return ApiResponse.fromJson(resp.data);
  }

  // POST
  Future<ApiResponse> post(String path, {dynamic data}) async {
    final resp = await dio.post(path, data: data);
    return ApiResponse.fromJson(resp.data);
  }

  // PUT
  Future<ApiResponse> put(String path, {dynamic data}) async {
    final resp = await dio.put(path, data: data);
    return ApiResponse.fromJson(resp.data);
  }

  // DELETE
  Future<ApiResponse> delete(String path) async {
    final resp = await dio.delete(path);
    return ApiResponse.fromJson(resp.data);
  }
}

// 统一响应模型
class ApiResponse {
  final int code;
  final String message;
  final dynamic data;

  ApiResponse({required this.code, required this.message, this.data});

  bool get isSuccess => code == 0;

  factory ApiResponse.fromJson(Map<String, dynamic> json) {
    return ApiResponse(
      code: json['code'] ?? -1,
      message: json['message'] ?? '',
      data: json['data'],
    );
  }
}

// 网络重试拦截器（连接超时自动重试一次）
class _RetryInterceptor extends Interceptor {
  final Dio _dio;
  _RetryInterceptor(this._dio);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (_shouldRetry(err) && (err.requestOptions.extra['retried'] != true)) {
      err.requestOptions.extra['retried'] = true;
      try {
        final resp = await _dio.fetch(err.requestOptions);
        return handler.resolve(resp);
      } catch (_) {
        // 重试也失败，继续报错
      }
    }
    handler.next(err);
  }

  bool _shouldRetry(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.connectionError;
  }
}

// JWT 自动附加 + 无感刷新拦截器
class _AuthInterceptor extends Interceptor {
  final Dio _dio;
  final TokenStorage _tokenStorage;
  bool _isRefreshing = false;
  final List<RequestOptions> _pendingRequests = [];

  _AuthInterceptor(this._dio, this._tokenStorage);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _tokenStorage.accessToken;
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && _tokenStorage.refreshToken != null) {
      if (!_isRefreshing) {
        _isRefreshing = true;
        try {
          final resp = await _dio.post(
            Api.refreshToken,
            data: {'refresh_token': _tokenStorage.refreshToken},
            options: Options(headers: {}), // 不附加旧 token
          );

          if (resp.data['code'] == 0) {
            final data = resp.data['data'];
            await _tokenStorage.saveTokens(
              data['access_token'],
              data['refresh_token'],
            );

            // 重试当前请求
            err.requestOptions.headers['Authorization'] =
                'Bearer ${data['access_token']}';
            final retryResp = await _dio.fetch(err.requestOptions);
            handler.resolve(retryResp);

            // 重试队列中的请求
            for (final req in _pendingRequests) {
              req.headers['Authorization'] = 'Bearer ${data['access_token']}';
              _dio.fetch(req);
            }
            _pendingRequests.clear();
            return;
          }
        } catch (_) {
          // 刷新失败，清除 token
          await _tokenStorage.clear();
        } finally {
          _isRefreshing = false;
        }
      } else {
        // 正在刷新中，加入队列等待
        _pendingRequests.add(err.requestOptions);
        return;
      }
    }
    handler.next(err);
  }
}
