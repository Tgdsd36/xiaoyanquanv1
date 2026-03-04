import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/colors.dart';
import '../../../core/constants/api.dart';
import '../../../core/network/http_client.dart';
import '../../home/models/favorite_group_model.dart';
import '../../home/repositories/favorite_repository.dart';
import '../widgets/profile_tab_widgets.dart';

enum MyListType { favorites, downloads, questions }

class MyListPage extends StatefulWidget {
  final MyListType type;
  const MyListPage({super.key, required this.type});

  @override
  State<MyListPage> createState() => _MyListPageState();
}

class _MyListPageState extends State<MyListPage> {
  final HttpClient _http = HttpClient();
  final FavoriteRepository _groupRepo = FavoriteRepository();
  List<Map<String, dynamic>> _items = [];
  List<FavoriteGroup> _groups = [];
  bool _isLoading = true;
  final int _page = 1;

  String get _title {
    switch (widget.type) {
      case MyListType.favorites:
        return '我的收藏';
      case MyListType.downloads:
        return '下载记录';
      case MyListType.questions:
        return '我的提问';
    }
  }

  String get _apiPath {
    switch (widget.type) {
      case MyListType.favorites:
        return Api.favorites;
      case MyListType.downloads:
        return Api.userDownloads;
      case MyListType.questions:
        return Api.questions;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      if (widget.type == MyListType.favorites) {
        // 收藏页加载分组列表
        final groups = await _groupRepo.getGroups();
        if (!mounted) return;
        setState(() {
          _groups = groups;
          _isLoading = false;
        });
      } else {
        final resp = await _http.get(_apiPath, params: {'page': _page});
        if (resp.isSuccess && resp.data != null) {
          setState(() {
            _items = List<Map<String, dynamic>>.from(resp.data['list'] ?? []);
            _isLoading = false;
          });
        }
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createGroup() async {
    final name = await _showCreateGroupDialog();
    if (name == null || name.isEmpty) return;
    final result = await _groupRepo.createGroup(name);
    if (!mounted) return;
    if (result.group != null) {
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? '创建失败')),
      );
    }
  }

  Future<String?> _showCreateGroupDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建分组'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(
            hintText: '输入分组名称',
            counterText: '',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (widget.type == MyListType.favorites)
            IconButton(
              icon: const Icon(Icons.add, size: 24),
              tooltip: '新建分组',
              onPressed: _createGroup,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : widget.type == MyListType.favorites
              ? _buildFavoriteGroups()
              : _items.isEmpty
                  ? const Center(
                      child: Text('暂无数据',
                          style: TextStyle(color: AppColors.textHint)))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        switch (widget.type) {
                          case MyListType.favorites:
                            return const SizedBox.shrink();
                          case MyListType.downloads:
                            return DownloadListItem(item: item);
                          case MyListType.questions:
                            return QuestionListItem(item: item);
                        }
                      },
                    ),
    );
  }

  Widget _buildFavoriteGroups() {
    if (_groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.collections_bookmark_outlined,
                size: 48, color: AppColors.textDisabled),
            const SizedBox(height: 12),
            const Text('还没有收藏分组',
                style: TextStyle(color: AppColors.textHint, fontSize: 14)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _createGroup,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('创建分组'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        itemCount: _groups.length,
        itemBuilder: (context, index) {
          final group = _groups[index];
          return FavoriteGroupCard(
            group: group,
            onTap: () async {
              final result = await context.push<bool>(
                '/favorite-group/${group.id}',
                extra: group.name,
              );
              if (result == true) _load();
            },
          );
        },
      ),
    );
  }
}
