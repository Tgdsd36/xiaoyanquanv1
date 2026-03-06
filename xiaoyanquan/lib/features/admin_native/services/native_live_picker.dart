import 'package:flutter/services.dart';

class NativeLivePickResult {
  final String imagePath;
  final String videoPath;
  final String imageName;
  final String videoName;
  final String source;

  const NativeLivePickResult({
    required this.imagePath,
    required this.videoPath,
    required this.imageName,
    required this.videoName,
    required this.source,
  });

  factory NativeLivePickResult.fromMap(Map<dynamic, dynamic> map) {
    return NativeLivePickResult(
      imagePath: (map['image_path'] ?? '').toString(),
      videoPath: (map['video_path'] ?? '').toString(),
      imageName: (map['image_name'] ?? '').toString(),
      videoName: (map['video_name'] ?? '').toString(),
      source: (map['source'] ?? 'unknown').toString(),
    );
  }

  bool get isValid => imagePath.isNotEmpty && videoPath.isNotEmpty;
}

class NativeLivePicker {
  static const MethodChannel _channel = MethodChannel('com.xiaoyanquan/live_photo');

  static Future<NativeLivePickResult?> pickLiveForUpload() async {
    final result = await _channel.invokeMethod<dynamic>('pickLiveForUpload');
    if (result == null) return null;
    if (result is Map) {
      final parsed = NativeLivePickResult.fromMap(result);
      return parsed.isValid ? parsed : null;
    }
    return null;
  }
}
