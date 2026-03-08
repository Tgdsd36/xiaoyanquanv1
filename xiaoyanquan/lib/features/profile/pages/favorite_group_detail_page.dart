import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../app/colors.dart';
import '../../../core/constants/api.dart';
import '../../../core/network/http_client.dart';
import '../../../core/utils/url_utils.dart';
import '../../../shared/network_video_thumbnail.dart';
import '../../home/repositories/favorite_repository.dart';

/// 收藏分组详情页：展示某个分组内的收藏列表
class FavoriteGroupDetailPage extends StatefulWidget {
  final int groupId;
  final String groupName;

  const FavoriteGroupDetailPage({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<FavoriteGroupDetailPage> createState() =>
      _FavoriteGroupDetailPageState();
}

class _FavoriteGroupDetailPageState extends State<FavoriteGroupDetailPage> {
  final HttpClient _http = HttpClient();
  final FavoriteRepository _groupRepo = FavoriteRepository();
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;

  // 编辑分组
  bool _isEditing = false;
  final _nameController = TextEditingController();

  // 多选模式
  bool _isSelectMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.groupName;
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final resp = await _http.get(
        Api.favorites,
        params: {'page': 1, 'group_id': widget.groupId},
      );
      if (resp.isSuccess && resp.data != null) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(resp.data['list'] ?? []);
          _hasMore = resp.data['has_more'] ?? false;
          _page = 1;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    try {
      final resp = await _http.get(
        Api.favorites,
        params: {'page': _page + 1, 'group_id': widget.groupId},
      );
      if (resp.isSuccess && resp.data != null) {
        setState(() {
          _items.addAll(
            List<Map<String, dynamic>>.from(resp.data['list'] ?? []),
          );
          _hasMore = resp.data['has_more'] ?? false;
          _page++;
        });
      }
    } catch (_) {}
    _loadingMore = false;
  }

  Future<void> _renameGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || name == widget.groupName) {
      setState(() => _isEditing = false);
      return;
    }
    final error = await _groupRepo.updateGroup(widget.groupId, name);
    if (!mounted) return;
    if (error == null) {
      setState(() => _isEditing = false);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  void _enterSelectMode(int firstId) {
    setState(() {
      _isSelectMode = true;
      _selectedIds.add(firstId);
    });
  }

  void _exitSelectMode() {
    setState(() {
      _isSelectMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelect(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _items.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_items.map((e) => e['id'] as int));
      }
    });
  }

  Future<void> _batchDelete() async {
    if (_selectedIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量取消收藏'),
        content: Text('确定取消收藏已选的 ${_selectedIds.length} 个素材吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final resp = await _http.post(
        Api.favoriteBatchDelete,
        data: {'ids': _selectedIds.toList()},
      );
      if (!mounted) return;
      if (resp.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已取消 ${_selectedIds.length} 个收藏')),
        );
        _exitSelectMode();
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resp.message.isNotEmpty ? resp.message : '操作失败')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网络错误，请重试')),
        );
      }
    }
  }

  Future<void> _deleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('删除分组'),
            content: const Text('删除分组后，组内收藏将一并删除，确定删除吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('删除'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    final error = await _groupRepo.deleteGroup(widget.groupId);
    if (!mounted) return;
    if (error == null) {
      context.pop(true); // 返回 true 表示已删除，需要刷新
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _isSelectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectMode,
              )
            : null,
        title: _isSelectMode
            ? Text('已选 ${_selectedIds.length} 项')
            : _isEditing
                ? TextField(
                    controller: _nameController,
                    autofocus: true,
                    style: const TextStyle(fontSize: 17),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '分组名称',
                    ),
                    onSubmitted: (_) => _renameGroup(),
                  )
                : Text(_nameController.text),
        centerTitle: true,
        actions: _isSelectMode
            ? [
                TextButton(
                  onPressed: _selectAll,
                  child: Text(
                    _selectedIds.length == _items.length ? '取消全选' : '全选',
                    style: const TextStyle(color: AppColors.primary),
                  ),
                ),
              ]
            : [
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'rename') {
                      setState(() => _isEditing = true);
                    } else if (value == 'delete') {
                      _deleteGroup();
                    } else if (value == 'batch') {
                      setState(() => _isSelectMode = true);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'batch',
                      child: Row(
                        children: [
                          Icon(
                            Icons.checklist_rounded,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                          SizedBox(width: 8),
                          Text('批量管理'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                          SizedBox(width: 8),
                          Text('重命名'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: AppColors.error,
                          ),
                          SizedBox(width: 8),
                          Text('删除分组',
                              style: TextStyle(color: AppColors.error)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _items.isEmpty
              ? const Center(
                  child: Text('暂无收藏',
                      style: TextStyle(color: AppColors.textHint)),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.pixels >=
                        notification.metrics.maxScrollExtent - 200) {
                      _loadMore();
                    }
                    return false;
                  },
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                          12, 12, 12, _isSelectMode ? 80 : 12),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        final favId = item['id'] as int;
                        return _FavoriteItemTile(
                          item: item,
                          isSelectMode: _isSelectMode,
                          isSelected: _selectedIds.contains(favId),
                          onTap: () {
                            if (_isSelectMode) {
                              _toggleSelect(favId);
                            } else {
                              final targetId = item['target_id'];
                              if (targetId != null) {
                                context.push('/material/$targetId/preview');
                              }
                            }
                          },
                          onLongPress: () {
                            if (!_isSelectMode) _enterSelectMode(favId);
                          },
                        );
                      },
                    ),
                  ),
                ),
      bottomSheet: _isSelectMode
          ? Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: _selectedIds.isEmpty ? null : _batchDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(
                      _selectedIds.isEmpty
                          ? '取消收藏'
                          : '取消收藏 (${_selectedIds.length})',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error,
                      disabledBackgroundColor: AppColors.border,
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

class _FavoriteItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isSelectMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FavoriteItemTile({
    required this.item,
    required this.isSelectMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = UrlUtils.absolute(
      (item['thumbnail_url'] ?? item['thumbnail'])?.toString(),
    );
    final canShowImage =
        thumbnailUrl.isNotEmpty && !UrlUtils.isVideoUrl(thumbnailUrl);
    final createdAt =
        (item['created_at'] ?? item['favorited_at'])?.toString() ?? '';

    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSelectMode) ...[
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              color: isSelected ? AppColors.primary : AppColors.textHint,
              size: 22,
            ),
            const SizedBox(width: 8),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 50,
              height: 50,
              child: canShowImage
                  ? CachedNetworkImage(
                      imageUrl: thumbnailUrl,
                      fit: BoxFit.cover,
                    )
                  : (thumbnailUrl.isNotEmpty &&
                          UrlUtils.isVideoUrl(thumbnailUrl))
                      ? NetworkVideoThumbnail(
                          videoUrl: thumbnailUrl,
                          fit: BoxFit.cover,
                          placeholder: Container(
                            color: AppColors.shimmer,
                            child: const Icon(
                              Icons.play_circle_outline_rounded,
                              color: AppColors.textDisabled,
                            ),
                          ),
                          errorWidget: Container(
                            color: AppColors.shimmer,
                            child: const Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.textDisabled,
                            ),
                          ),
                        )
                      : Container(
                          color: AppColors.shimmer,
                          child: Icon(
                            thumbnailUrl.isNotEmpty
                                ? Icons.play_circle_outline_rounded
                                : Icons.image,
                            color: AppColors.textDisabled,
                          ),
                        ),
            ),
          ),
        ],
      ),
      title: Text(
        item['title'] ?? '未知素材',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        createdAt,
        style: const TextStyle(fontSize: 12, color: AppColors.textHint),
      ),
      trailing: isSelectMode
          ? null
          : const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textHint,
            ),
      onTap: onTap,
      onLongPress: onLongPress,
      tileColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
