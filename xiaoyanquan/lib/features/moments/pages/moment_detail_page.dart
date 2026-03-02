import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/constants/api.dart';
import '../../../core/network/http_client.dart';
import '../../../shared/share_helper.dart';
import 'moments_page.dart';

final momentDetailProvider =
    FutureProvider.family<MomentItem?, int>((ref, id) async {
  final http = HttpClient();
  final resp = await http.get(Api.momentDetail(id));
  if (resp.isSuccess && resp.data != null) {
    return MomentItem.fromJson(resp.data);
  }
  return null;
});

class MomentDetailPage extends ConsumerStatefulWidget {
  final int momentId;
  const MomentDetailPage({super.key, required this.momentId});

  @override
  ConsumerState<MomentDetailPage> createState() => _MomentDetailPageState();
}

class _MomentDetailPageState extends ConsumerState<MomentDetailPage> {
  final _questionController = TextEditingController();
  List<Map<String, dynamic>> _questions = [];
  bool _loadingQuestions = true;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    try {
      final resp = await HttpClient()
          .get(Api.momentQuestions(widget.momentId), params: {'page': 1});
      if (resp.isSuccess && resp.data != null) {
        setState(() {
          _questions =
              List<Map<String, dynamic>>.from(resp.data['list'] ?? []);
          _loadingQuestions = false;
        });
      }
    } catch (_) {
      setState(() => _loadingQuestions = false);
    }
  }

  Future<void> _submitQuestion() async {
    final text = _questionController.text.trim();
    if (text.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入至少2个字')));
      return;
    }
    try {
      final resp = await HttpClient().post(Api.questions, data: {
        'target_type': 'moment',
        'target_id': widget.momentId,
        'question_text': text,
      });
      if (resp.isSuccess) {
        _questionController.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('提问成功，等待回复')));
        }
        _loadQuestions();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(resp.message)));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('提问失败')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(momentDetailProvider(widget.momentId));
    final authState = ref.watch(authProvider);
    final isAuth = authState.status == AuthStatus.authenticated;

    return Scaffold(
      appBar: AppBar(
        title: const Text('动态详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => ShareHelper.shareMoment(
              id: widget.momentId,
              contentText: detailAsync.valueOrNull?.contentText,
            ),
          ),
        ],
      ),
      body: detailAsync.when(
        data: (moment) {
          if (moment == null) {
            return const Center(child: Text('动态不存在'));
          }
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (moment.contentText.isNotEmpty)
                        Text(moment.contentText,
                            style:
                                const TextStyle(fontSize: 15, height: 1.6)),
                      if (moment.mediaUrls.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        ...moment.mediaUrls.map((url) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: url,
                                  width: double.infinity,
                                  fit: BoxFit.fitWidth,
                                ),
                              ),
                            )),
                      ],
                      const SizedBox(height: 8),
                      Text(moment.createdAt,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500])),
                      const Divider(height: 32),
                      Text('提问 (${_questions.length})',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      if (_loadingQuestions)
                        const Center(child: CircularProgressIndicator())
                      else if (_questions.isEmpty)
                        Text('暂无提问',
                            style: TextStyle(color: Colors.grey[500]))
                      else
                        ..._questions.map((q) => _QuestionTile(q)),
                    ],
                  ),
                ),
              ),
              // 提问输入栏
              if (isAuth)
                Container(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 8,
                    bottom: MediaQuery.of(context).padding.bottom + 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                        top: BorderSide(
                            color: Colors.grey[800]!, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _questionController,
                          decoration: const InputDecoration(
                            hintText: '输入你的提问...',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.send,
                            color: Theme.of(context).colorScheme.primary),
                        onPressed: _submitQuestion,
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }
}

class _QuestionTile extends StatelessWidget {
  final Map<String, dynamic> q;
  const _QuestionTile(this.q);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              Text(q['user_nickname'] ?? '匿名',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text(q['created_at'] ?? '',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ),
          const SizedBox(height: 6),
          Text(q['question_text'] ?? '', style: const TextStyle(fontSize: 14)),
          if ((q['reply_text'] ?? '').isNotEmpty) ...[
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
                    child: Text(q['reply_text'],
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey[300])),
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
