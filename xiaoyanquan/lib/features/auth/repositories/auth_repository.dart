import '../../../core/constants/api.dart';
import '../../../core/network/http_client.dart';

class AuthRepository {
  final HttpClient _http = HttpClient();

  /// 发送短信验证码
  Future<ApiResponse> sendSMS(String phone) {
    return _http.post(Api.smsSend, data: {'phone': phone});
  }

  /// 短信验证码登录（自动注册）
  Future<ApiResponse> smsLogin({
    required String phone,
    required String code,
  }) {
    return _http.post(Api.smsLogin, data: {
      'phone': phone,
      'code': code,
    });
  }

  /// 密码登录
  Future<ApiResponse> passwordLogin({
    required String phone,
    required String password,
  }) {
    return _http.post(Api.login, data: {
      'phone': phone,
      'password': password,
    });
  }

  /// 注册
  Future<ApiResponse> register({
    required String phone,
    required String code,
    required String password,
    String? nickname,
  }) {
    return _http.post(Api.register, data: {
      'phone': phone,
      'code': code,
      'password': password,
      if (nickname != null && nickname.isNotEmpty) 'nickname': nickname,
    });
  }
}
