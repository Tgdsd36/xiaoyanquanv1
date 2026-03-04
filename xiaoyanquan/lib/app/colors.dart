import 'package:flutter/material.dart';

/// 小颜圈全局设计色 Token
class AppColors {
  AppColors._();

  // ==================== 品牌色 ====================
  static const primary = Color(0xFFFF2442);
  static const primaryLight = Color(0xFFFFF0F2); // primary 10% 背景
  static const primaryBg = Color(0xFFFFF5F6); // 更浅的品牌背景

  // ==================== 类型徽章 ====================
  static const videoBadge = Color(0xFF6C5CE7); // 视频 — 紫
  static const liveBadge = Color(0xFF00B894); // Live Photo — 绿
  static const imageBadge = Color(0xFFFF7675); // 图片 — 粉

  // ==================== 会员色 ====================
  static const memberPro = Color(0xFF42A5F5); // 专业版 — 蓝
  static const memberProEnd = Color(0xFF1565C0);
  static const memberFlagship = Color(0xFFFFD54F); // 旗舰版 — 金
  static const memberFlagshipEnd = Color(0xFFFF8F00);

  // ==================== 中性色阶（文字） ====================
  static const textPrimary = Color(0xFF1A1A1A); // 标题 / 主要文字
  static const textBody = Color(0xFF333333); // 正文
  static const textSecondary = Color(0xFF666666); // 次要文字
  static const textHint = Color(0xFF999999); // 占位 / 辅助
  static const textDisabled = Color(0xFFBBBBBB); // 禁用态

  // ==================== 表面色 ====================
  static const scaffoldBg = Colors.white; // 页面背景
  static const cardBg = Colors.white; // 卡片背景
  static const surface = Color(0xFFF5F5F5); // 输入框 / chip 默认背景
  static const surfaceVariant = Color(0xFFF0F0F0); // 更深的面板色
  static const shimmer = Color(0xFFF0F0F0); // 骨架屏 / 图片占位

  // ==================== 边框 / 分割 ====================
  static const divider = Color(0xFFEEEEEE);
  static const border = Color(0xFFE8E8E8);
  static const borderLight = Color(0xFFF3F4F6);

  // ==================== 功能色 ====================
  static const success = Color(0xFF52C41A);
  static const warning = Color(0xFFFAAD14);
  static const error = Color(0xFFFF4D4F);

  // ==================== 收藏色 ====================
  static const favoriteActive = Colors.orange;
  static const favoriteHeart = Color(0xFFFF6B6B); // 红心

  // ==================== 暗色（沉浸预览/灵感页专用） ====================
  static const darkBg = Colors.black;
  static const darkOverlay30 = Color(0x4D000000); // 30% 黑
  static const darkOverlay50 = Color(0x80000000); // 50% 黑
}
