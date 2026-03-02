import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/api.dart';
import '../../../core/network/http_client.dart';

enum MyListType { favorites, downloads, questions }

class MyListPage extends StatefulWidget {
  final MyListType type;
  const MyListPage({super.key, required this.type});

  @override
  State<MyListPage> createState() => _MyListPageState();
}

class _MyListPageState extends State<MyListPage> {
  final HttpClient _http = HttpClient();
  List<Map<String, dynamic>> _items = [];
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
      final resp = await _http.get(_apiPath, params: {'page': _page});
      if (resp.isSuccess && resp.data != null) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(resp.data['list'] ?? []);
          _isLoading = false;
        });
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Text('暂无数据', style: TextStyle(color: Colors.grey)))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    switch (widget.type) {
                      case MyListType.favorites:
                        return _FavoriteItem(item);
                      case MyListType.downloads:
                        return _DownloadItem(item);
                      case MyListType.questions:
                        return _QuestionListItem(item);
                    }
                  },
                ),
    );
  }
}

class _FavoriteItem extends StatelessWidget {
  final Map<String, dynamic> item;
  const _FavoriteItem(this.item);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 50,
          height: 50,
          child: item['thumbnail'] != null && (item['thumbnail'] as String).isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: item['thumbnail'],
                  fit: BoxFit.cover,
                )
              : Container(
                  color: Colors.grey[800],
                  child: const Icon(Icons.image, color: Colors.grey)),
        ),
      ),
      title: Text(item['title'] ?? '未知素材', maxLines: 1),
      subtitle: Text(item['created_at'] ?? '',
          style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () {
        final targetId = item['target_id'];
        if (targetId != null) {
          context.push('/material/$targetId');
        }
      },
      tileColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

class _DownloadItem extends StatelessWidget {
  final Map<String, dynamic> item;
  const _DownloadItem(this.item);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 50,
          height: 50,
          child: item['thumbnail_url'] != null &&
                  (item['thumbnail_url'] as String).isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: item['thumbnail_url'],
                  fit: BoxFit.cover,
                )
              : Container(
                  color: Colors.grey[800],
                  child: const Icon(Icons.image, color: Colors.grey)),
        ),
      ),
      title: Text(item['title'] ?? '未知素材', maxLines: 1),
      subtitle: Text(item['downloaded_at'] ?? '',
          style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () {
        final materialId = item['material_id'];
        if (materialId != null) {
          context.push('/material/$materialId');
        }
      },
      tileColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

class _QuestionListItem extends StatelessWidget {
  final Map<String, dynamic> item;
  const _QuestionListItem(this.item);

  @override
  Widget build(BuildContext context) {
    final status = item['status'] ?? 'pending';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: status == 'replied'
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  status == 'replied' ? '已回复' : '待回复',
                  style: TextStyle(
                    fontSize: 11,
                    color: status == 'replied' ? Colors.green : Colors.orange,
                  ),
                ),
              ),
              const Spacer(),
              Text(item['created_at'] ?? '',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ),
          const SizedBox(height: 8),
          Text(item['question_text'] ?? '',
              style: const TextStyle(fontSize: 14)),
          if ((item['reply_text'] ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.reply, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(item['reply_text'],
                        style:
                            TextStyle(fontSize: 13, color: Colors.grey[300])),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
