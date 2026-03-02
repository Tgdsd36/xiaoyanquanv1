import 'package:flutter/material.dart';

class AppTheme {
  // 小红书红
  static const _primaryColor = Color(0xFFFF2442);
  // 纯白背景
  static const _bgColor = Colors.white;
  // 浅灰背景（用于分割或卡片背景）
  static const _surfaceColor = Color(0xFFF5F5F5);
  // 主要文字色
  static const _textColor = Color(0xFF333333);
  // 次要文字色
  static const _subTextColor = Color(0xFF999999);

  static ThemeData get lightTheme => ThemeData(
        brightness: Brightness.light,
        primaryColor: _primaryColor,
        scaffoldBackgroundColor: _bgColor,
        colorScheme: const ColorScheme.light(
          primary: _primaryColor,
          secondary: _primaryColor,
          surface: Colors.white,
          onSurface: _textColor,
          error: Color(0xFFFF4D4F),
        ),
        cardColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: _bgColor,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: _textColor),
          titleTextStyle: TextStyle(
            color: _textColor,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          actionsIconTheme: IconThemeData(color: _textColor),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: _textColor, // 选中变黑（或红，看喜好，小红书选中通常是黑色加粗或红色）
          unselectedItemColor: _subTextColor,
          type: BottomNavigationBarType.fixed,
          elevation: 0, // 扁平化，用border分割
          showSelectedLabels: true,
          showUnselectedLabels: true,
          selectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          unselectedLabelStyle: TextStyle(fontSize: 10),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: _textColor,
          unselectedLabelColor: _subTextColor,
          indicatorColor: _primaryColor,
          labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal, fontSize: 16),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _surfaceColor, // 浅灰输入框背景
          hintStyle: const TextStyle(color: _subTextColor, fontSize: 14),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20), // 圆润的输入框
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: _primaryColor, width: 1),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: const Size(double.infinity, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22), // 圆润按钮
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: _textColor, // 文字按钮默认黑色
            textStyle: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: _surfaceColor,
          selectedColor: _primaryColor.withValues(alpha: 0.1),
          labelStyle: const TextStyle(color: _textColor, fontSize: 12),
          secondaryLabelStyle: const TextStyle(color: _primaryColor), // 选中文字变红
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide.none,
        ),
        dividerColor: const Color(0xFFEEEEEE),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFEEEEEE),
          thickness: 0.5,
          space: 1,
        ),
        iconTheme: const IconThemeData(color: _textColor),
      );
}
