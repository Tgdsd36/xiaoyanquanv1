import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/storage/token_storage.dart';
import 'app/app.dart';
import 'shared/system_permission_bootstrap.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 增大图片内存缓存，减少上滑时缩略图重新解码导致的卡顿
  PaintingBinding.instance.imageCache.maximumSizeBytes = 200 << 20; // 200 MB
  PaintingBinding.instance.imageCache.maximumSize = 500;

  await TokenStorage.init();
  runApp(const ProviderScope(child: XiaoYanQuanApp()));
  // 等第一帧渲染完成后再请求权限，确保 Android Activity 已就绪
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(SystemPermissionBootstrap.requestAllOnce());
  });
}
