import 'package:flutter/material.dart';
import '../app/colors.dart';
import '../features/home/models/favorite_group_model.dart';
import '../features/home/repositories/favorite_repository.dart';

/// 收藏分组选择弹窗
/// 返回选中的 groupId（int），null 表示用户取消
class FavoriteGroupSheet extends StatefulWidget {
  const FavoriteGroupSheet({super.key});

  /// 弹出弹窗，返回选中 groupId（null = 取消）
  static Future<int?> show(BuildContext context) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FavoriteGroupSheet(),
    );
  }

  @override
  State<FavoriteGroupSheet> createState() => _FavoriteGroupSheetState();
}

class _FavoriteGroupSheetState extends State<FavoriteGroupSheet> {
  final FavoriteRepository _repo = FavoriteRepository();
  List<FavoriteGroup> _groups = [];
  bool _loading = true;

  // 新建分组
  bool _creating = false;
  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    final groups = await _repo.getGroups();
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _loading = false;
    });
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _submitting = true);
    final result = await _repo.createGroup(name);
    if (!mounted) return;

    if (result.group != null) {
      setState(() {
        _groups.add(result.group!);
        _creating = false;
        _submitting = false;
        _nameController.clear();
      });
    } else {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? '创建失败')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部拖拽条
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题行
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                const Text(
                  '收藏到分组',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                // 新建分组按钮
                TextButton.icon(
                  onPressed: () {
                    setState(() => _creating = !_creating);
                    if (_creating) {
                      Future.delayed(const Duration(milliseconds: 100), () {
                        _nameFocus.requestFocus();
                      });
                    }
                  },
                  icon: Icon(
                    _creating ? Icons.close : Icons.add,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  label: Text(
                    _creating ? '取消' : '新建分组',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 新建分组输入框
          if (_creating)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      focusNode: _nameFocus,
                      maxLength: 20,
                      decoration: InputDecoration(
                        hintText: '输入分组名称',
                        hintStyle: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 14,
                        ),
                        counterText: '',
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _createGroup(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _createGroup,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('确定', style: TextStyle(fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1, color: AppColors.divider),
          // 分组列表
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _groups.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            '暂无分组',
                            style: TextStyle(
                              color: AppColors.textHint,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.only(bottom: bottomPadding + 8),
                        itemCount: _groups.length,
                        itemBuilder: (context, index) {
                          final group = _groups[index];
                          return _GroupTile(
                            group: group,
                            onTap: () => Navigator.of(context).pop(group.id),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final FavoriteGroup group;
  final VoidCallback onTap;

  const _GroupTile({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 封面缩略图
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 44,
                height: 44,
                color: AppColors.surface,
                child: group.coverUrl.isNotEmpty
                    ? Image.network(
                        group.coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.collections_bookmark_outlined,
                          color: AppColors.textDisabled,
                          size: 20,
                        ),
                      )
                    : const Icon(
                        Icons.collections_bookmark_outlined,
                        color: AppColors.textDisabled,
                        size: 20,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (group.isDefault) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '默认',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${group.itemCount} 个收藏',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}
