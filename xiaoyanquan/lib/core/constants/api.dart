class Api {
  static const String baseUrl = 'http://localhost:8080/api/v1';

  // 认证
  static const String smsSend = '/auth/sms/send';
  static const String smsLogin = '/auth/sms/login';
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String refreshToken = '/auth/refresh';
  static const String deleteAccount = '/auth/account';

  // 分类
  static const String categories = '/categories';

  // 素材
  static const String materials = '/materials';
  static String materialDetail(int id) => '/materials/$id';
  static const String materialSearch = '/materials/search';
  static String materialDownload(int id) => '/materials/$id/download';

  // 找灵感
  static const String inspirationFeed = '/inspiration/feed';
  static const String inspirationDislike = '/inspiration/dislike';

  // 朋友圈
  static const String moments = '/moments';

  // 收藏
  static const String favorites = '/favorites';
  static const String favoriteToggle = '/favorites/toggle';
  static String favoriteDelete(int id) => '/favorites/$id';

  // 收藏分组
  static const String favoriteGroups = '/favorite-groups';
  static String favoriteGroupDetail(int id) => '/favorite-groups/$id';

  // 提问
  static const String questions = '/questions';
  static String questionsByMaterial(int id) => '/questions/material/$id';

  // 用户
  static const String userProfile = '/user/profile';
  static const String userUpload = '/user/upload';
  static const String userDownloads = '/user/downloads';
  static const String userPassword = '/user/password';

  // 会员
  static const String membershipStatus = '/membership/status';
  static const String membershipPurchase = '/membership/purchase';
  static const String membershipVerify = '/membership/verify';
}
