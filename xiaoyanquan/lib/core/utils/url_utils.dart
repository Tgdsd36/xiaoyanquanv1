import '../constants/api.dart';

class UrlUtils {
  UrlUtils._();

  static const Set<String> _videoExts = {
    '.mp4',
    '.mov',
    '.m4v',
    '.webm',
    '.mkv',
    '.avi',
    '.wmv',
    '.flv',
    '.mpeg',
    '.mpg',
    '.3gp',
    '.m3u8',
  };

  static const Set<String> _imageExts = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.heic',
    '.heif',
    '.avif',
  };

  /// 将接口返回的相对路径（如 /static/uploads/...）补全为绝对地址。
  static String absolute(String? rawUrl) {
    final value = rawUrl?.trim() ?? '';
    if (value.isEmpty) return '';

    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
      return value;
    }

    final apiUri = Uri.parse(Api.baseUrl);
    final origin = Uri(
      scheme: apiUri.scheme,
      host: apiUri.host,
      port: apiUri.hasPort ? apiUri.port : null,
    );
    return origin.resolve(value).toString();
  }

  static bool isVideoUrl(String? rawUrl) {
    final ext = _fileExtension(rawUrl);
    if (ext.isEmpty) return false;
    return _videoExts.contains(ext);
  }

  static bool isImageUrl(String? rawUrl) {
    final ext = _fileExtension(rawUrl);
    if (ext.isEmpty) return false;
    return _imageExts.contains(ext);
  }

  static String firstImageUrl(Iterable<String?> urls) {
    for (final raw in urls) {
      final url = absolute(raw);
      if (url.isEmpty) continue;
      if (isVideoUrl(url)) continue;
      return url;
    }
    return '';
  }

  static String firstVideoUrl(Iterable<String?> urls) {
    for (final raw in urls) {
      final url = absolute(raw);
      if (url.isEmpty) continue;
      if (isVideoUrl(url)) return url;
    }
    return '';
  }

  /// 返回所有图片 URL（去重、保序）
  static List<String> allImageUrls(Iterable<String?> urls) {
    final result = <String>[];
    final seen = <String>{};
    for (final raw in urls) {
      final url = absolute(raw);
      if (url.isEmpty || isVideoUrl(url)) continue;
      if (!isImageUrl(url)) continue;
      if (seen.add(url)) result.add(url);
    }
    return result;
  }

  /// 返回所有视频 URL（去重、保序）
  static List<String> allVideoUrls(Iterable<String?> urls) {
    final result = <String>[];
    final seen = <String>{};
    for (final raw in urls) {
      final url = absolute(raw);
      if (url.isEmpty) continue;
      if (!isVideoUrl(url)) continue;
      if (seen.add(url)) result.add(url);
    }
    return result;
  }

  static String _fileExtension(String? rawUrl) {
    final value = rawUrl?.trim() ?? '';
    if (value.isEmpty) return '';
    final absoluteUrl = absolute(value);
    final path = Uri.tryParse(absoluteUrl)?.path ?? absoluteUrl;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot >= path.length - 1) return '';
    return path.substring(dot).toLowerCase();
  }
}
