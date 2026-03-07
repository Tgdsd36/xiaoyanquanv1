import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'colors.dart';

class MainScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  static const _tabs = [
    _TabItem(Icons.camera_outlined, Icons.camera_rounded, '素材库', false),
    _TabItem(Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, '找灵感', false),
    _TabItem(Icons.favorite_border_rounded, Icons.favorite_rounded, '朋友圈', false),
    _TabItem(Icons.person_outline_rounded, Icons.person_rounded, '我的', false),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final currentIndex = navigationShell.currentIndex;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.cardBg,
          border: Border(
            top: BorderSide(
              color: AppColors.divider,
              width: 0.5,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              children: List.generate(_tabs.length, (index) {
                final tab = _tabs[index];
                final isSelected = index == currentIndex;

                return Expanded(
                  child: GestureDetector(
                    onTap: () => navigationShell.goBranch(
                      index,
                      initialLocation: index == currentIndex,
                    ),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 选中态：图标带淡红背景 pill
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? primary.withValues(alpha: 0.1)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                isSelected ? tab.activeIcon : tab.icon,
                                size: 22,
                                color: isSelected
                                    ? primary
                                    : AppColors.textDisabled,
                              ),
                            ),
                            // 红色未读数角标
                            if (tab.showBadge)
                              Positioned(
                                right: 2,
                                top: -4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: primary,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: AppColors.cardBg,
                                      width: 1.5,
                                    ),
                                  ),
                                  constraints: const BoxConstraints(minWidth: 18),
                                  child: const Text(
                                    '99+',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          tab.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.normal,
                            color: isSelected
                                ? primary
                                : AppColors.textDisabled,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool showBadge;

  const _TabItem(this.icon, this.activeIcon, this.label, this.showBadge);
}
