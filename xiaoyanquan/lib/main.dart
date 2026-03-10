import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/storage/token_storage.dart';
import 'app/app.dart';
import 'shared/system_permission_bootstrap.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TokenStorage.init();
  runApp(const ProviderScope(child: XiaoYanQuanApp()));
  // 等第一帧渲染完成后再请求权限，确保 Android Activity 已就绪
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(SystemPermissionBootstrap.requestAllOnce());
  });
}
