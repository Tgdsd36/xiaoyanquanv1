import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/colors.dart';
import '../models/category_model.dart';
import '../pages/search_page.dart';

/// 分类选择弹窗（一级分类为分区标题，二级分类 4 列网格）
/// 返回选中的 categoryId（int），null 表示用户取消
class CategorySheet extends StatelessWidget {
  final List<CategoryModel> categories;
  final int selectedCategoryId;

  const CategorySheet({
    super.key,
    required this.categories,
    required this.selectedCategoryId,
  });

  /// 弹出弹窗，选中分类后跳转搜索页
  static void show(
    BuildContext context, {
    required List<CategoryModel> categories,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CategorySheet(
        categories: categories,
        selectedCategoryId: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // ── 拖拽条 ──
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // ── 标题行：居中标题 + 右侧关闭 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Center(
                  child: Text(
                    '小颜圈素材库',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        Icons.close_rounded,
                        size: 22,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── 分类列表（垂直滚动）──
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding + 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final parent in categories) ...[
                    // 一级分类标题
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 10),
                      child: Text(
                        parent.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    // 二级分类 4 列网格
                    if (parent.children.isNotEmpty)
                      _ChildGrid(
                        children: parent.children,
                        selectedId: selectedCategoryId,
                        onSelect: (id, name) {
                          Navigator.of(context).pop();
                          context.push('/search',
                              extra: SearchArgs(
                                  categoryId: id, categoryName: name));
                        },
                      )
                    else
                      // 无二级 → 一级本身可点
                      _ChildGrid(
                        children: [parent],
                        selectedId: selectedCategoryId,
                        onSelect: (id, name) {
                          Navigator.of(context).pop();
                          context.push('/search',
                              extra: SearchArgs(
                                  categoryId: id, categoryName: name));
                        },
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 4 列等宽网格
class _ChildGrid extends StatelessWidget {
  final List<CategoryModel> children;
  final int selectedId;
  final void Function(int id, String name) onSelect;

  const _ChildGrid({
    required this.children,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <List<CategoryModel>>[];
    for (var i = 0; i < children.length; i += 4) {
      rows.add(children.sublist(
        i,
        i + 4 > children.length ? children.length : i + 4,
      ));
    }

    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: i < row.length
                        ? _ChipCell(
                            label: row[i].name,
                            isSelected: row[i].id == selectedId,
                            onTap: () => onSelect(row[i].id, row[i].name),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ChipCell extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ChipCell({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.3))
              : null,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? AppColors.primary : AppColors.textBody,
          ),
        ),
      ),
    );
  }
}
