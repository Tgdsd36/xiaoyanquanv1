import 'package:flutter/material.dart';
import 'colors.dart';

/// 小颜圈全局复用样式
class AppStyles {
  AppStyles._();

  // ==================== 卡片 ====================

  /// 标准卡片装饰（白底 + 圆角14 + 柔和阴影）
  static BoxDecoration get cardDecoration => BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: cardShadow,
      );

  /// 标准卡片阴影
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ];

  // ==================== 类型徽章 ====================

  /// 根据素材类型返回徽章颜色
  static Color typeBadgeColor({required bool isVideo, required bool isLivePhoto}) {
    if (isVideo) return AppColors.videoBadge;
    if (isLivePhoto) return AppColors.liveBadge;
    return AppColors.imageBadge;
  }

  /// 根据素材类型返回徽章文字
  static String typeBadgeText({required bool isVideo, required bool isLivePhoto}) {
    if (isVideo) return '视频';
    if (isLivePhoto) return 'LIVE';
    return '图片';
  }

  /// 类型徽章 Widget（统一的小标签）
  static Widget typeBadge({required bool isVideo, required bool isLivePhoto, double fontSize = 10}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: typeBadgeColor(isVideo: isVideo, isLivePhoto: isLivePhoto),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        typeBadgeText(isVideo: isVideo, isLivePhoto: isLivePhoto),
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
