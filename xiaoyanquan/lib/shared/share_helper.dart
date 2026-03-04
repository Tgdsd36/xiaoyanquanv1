import 'package:share_plus/share_plus.dart';

class ShareHelper {
  static const String _baseUrl = 'https://xiaoyanquan.com';

  /// 分享素材
  static Future<void> shareMaterial({
    required int id,
    required String title,
    String? thumbnailUrl,
  }) async {
    final url = '$_baseUrl/material/$id';
    await Share.share('【小颜圈】$title\n$url', subject: title);
  }

  /// 分享 App
  static Future<void> shareApp() async {
    await Share.share(
      '小颜圈 - 专业创作者素材库，海量图片视频 Live Photo 素材\n$_baseUrl',
      subject: '小颜圈',
    );
  }
}
