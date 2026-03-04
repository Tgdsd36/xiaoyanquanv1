import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../app/colors.dart';
import '../../../core/constants/api.dart';
import '../../../core/network/http_client.dart';
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
      final resp = await _http.get(Api.favorites, params: {
        'page': 1,
        'group_id': widget.groupId,
      });
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
      final resp = await _http.get(Api.favorites, params: {
        'page': _page + 1,
        'group_id': widget.groupId,
      });
      if (resp.isSuccess && resp.data != null) {
        setState(() {
          _items.addAll(
              List<Map<String, dynamic>>.from(resp.data['list'] ?? []));
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  Future<void> _deleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isEditing
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
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename') {
                setState(() => _isEditing = true);
              } else if (value == 'delete') {
                _deleteGroup();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 18,
                        color: AppColors.textSecondary),
                    SizedBox(width: 8),
                    Text('重命名'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18,
                        color: AppColors.error),
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
          ? const Center(
              child: CircularProgressIndicator(strokeWidth: 2))
          : _items.isEmpty
              ? const Center(
                  child: Text('暂无收藏',
                      style: TextStyle(color: AppColors.textHint)))
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
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return _FavoriteItemTile(item: item);
                      },
                    ),
                  ),
                ),
    );
  }
}

class _FavoriteItemTile extends StatelessWidget {
  final Map<String, dynamic> item;
  const _FavoriteItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 50,
          height: 50,
          child: item['thumbnail'] != null &&
                  (item['thumbnail'] as String).isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: item['thumbnail'],
                  fit: BoxFit.cover,
                )
              : Container(
                  color: AppColors.shimmer,
                  child: const Icon(Icons.image,
                      color: AppColors.textDisabled)),
        ),
      ),
      title: Text(item['title'] ?? '未知素材', maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: Text(item['created_at'] ?? '',
          style:
              const TextStyle(fontSize: 12, color: AppColors.textHint)),
      trailing:
          const Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
      onTap: () {
        final targetId = item['target_id'];
        if (targetId != null) {
          context.push('/material/$targetId/preview');
        }
      },
      tileColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8)),
    );
  }
}
