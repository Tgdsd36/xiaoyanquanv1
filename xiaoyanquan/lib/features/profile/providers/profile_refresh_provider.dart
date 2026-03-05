import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 提问数据刷新信号：
/// 提问成功后递增该值，"我的"页面监听后刷新提问列表与统计。
final profileQuestionRefreshProvider = StateProvider<int>((ref) => 0);

/// 下载数据刷新信号：
/// 下载请求成功后递增该值，"我的"页面监听后刷新下载列表与统计。
final profileDownloadRefreshProvider = StateProvider<int>((ref) => 0);
