import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/utils/url_utils.dart';
import '../auth/admin_auth_storage.dart';
import '../network/admin_http_client.dart';
import '../services/native_live_picker.dart';

class AdminNativeWorkbenchPage extends StatefulWidget {
  const AdminNativeWorkbenchPage({super.key});

  @override
  State<AdminNativeWorkbenchPage> createState() =>
      _AdminNativeWorkbenchPageState();
}

class _AdminNativeWorkbenchPageState extends State<AdminNativeWorkbenchPage> {
  static const String _allFoldersValue = '__all__';
  static const String _uncategorizedFolderValue = '__uncategorized__';

  final _storage = AdminAuthStorage();
  final _picker = ImagePicker();

  int _index = 0;
  bool _loading = false;
  bool _uploading = false;
  bool _creatingMaterials = false;
  Map<String, dynamic>? _dashboard;
  List<dynamic> _assets = const [];
  List<dynamic> _materials = const [];
  List<dynamic> _questions = const [];
  List<Map<String, dynamic>> _assetFolders = const [];
  List<Map<String, dynamic>> _categories = const [];
  String _assetFolderFilter = _allFoldersValue;

  String _uploadMode = 'image'; // image/video/live
  String _folder = '';
  XFile? _singleVideo;
  XFile? _liveImage;
  XFile? _liveVideo;
  String _liveSource = '';
  List<XFile> _images = const [];

  @override
  void initState() {
    super.initState();
    if (!_storage.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go('/admin-native/login');
      });
      return;
    }
    _loadCurrent();
  }

  Future<void> _logout() async {
    await _storage.clear();
    if (!mounted) return;
    context.go('/admin-native/login');
  }

  Future<void> _loadCurrent() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      if (_index == 0) {
        final resp = await AdminHttpClient().dio.get('/dashboard');
        final data = resp.data as Map<String, dynamic>;
        if ((data['code'] ?? -1) == 0) {
          _dashboard = (data['data'] as Map?)?.cast<String, dynamic>() ?? {};
        }
      } else if (_index == 2) {
        await _loadAssetFolders();
        await _loadAssets();
      } else if (_index == 3) {
        await _loadCategories();
        await _loadMaterials();
      } else if (_index == 4) {
        final resp = await AdminHttpClient()
            .dio
            .get('/questions', queryParameters: {'page': 1, 'page_size': 20});
        final data = resp.data as Map<String, dynamic>;
        if ((data['code'] ?? -1) == 0) {
          final payload = (data['data'] as Map?)?.cast<String, dynamic>() ?? {};
          _questions = List<dynamic>.from(payload['list'] ?? const []);
        }
      } else if (_index == 5) {
        await _loadCategories();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadAssetFolders() async {
    final resp = await AdminHttpClient().dio.get('/assets/folders');
    final data = resp.data as Map<String, dynamic>;
    if ((data['code'] ?? -1) != 0) return;
    final payload = (data['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final list = List<dynamic>.from(payload['folders'] ?? const []);
    _assetFolders = list
        .map(
          (item) => (item as Map).cast<String, dynamic>(),
        )
        .toList(growable: false);
  }

  Future<void> _loadAssets() async {
    final params = <String, dynamic>{'page': 1, 'page_size': 20};
    if (_assetFolderFilter != _allFoldersValue) {
      params['folder'] = _assetFolderFilter == _uncategorizedFolderValue
          ? ''
          : _assetFolderFilter;
    }
    final resp = await AdminHttpClient().dio.get(
      '/assets',
      queryParameters: params,
    );
    final data = resp.data as Map<String, dynamic>;
    if ((data['code'] ?? -1) != 0) return;
    final payload = (data['data'] as Map?)?.cast<String, dynamic>() ?? {};
    _assets = List<dynamic>.from(payload['list'] ?? const []);
  }

  Future<void> _loadMaterials() async {
    final resp = await AdminHttpClient().dio.get(
      '/materials',
      queryParameters: {'page': 1, 'page_size': 20},
    );
    final data = resp.data as Map<String, dynamic>;
    if ((data['code'] ?? -1) != 0) return;
    final payload = (data['data'] as Map?)?.cast<String, dynamic>() ?? {};
    _materials = List<dynamic>.from(payload['list'] ?? const []);
  }

  Future<void> _loadCategories() async {
    final resp = await AdminHttpClient().dio.get('/categories');
    final data = resp.data as Map<String, dynamic>;
    if ((data['code'] ?? -1) != 0) return;
    final list = List<dynamic>.from(data['data'] ?? const []);
    _categories = list
        .map(
          (item) => (item as Map).cast<String, dynamic>(),
        )
        .toList(growable: false);
  }

  Future<void> _createAssetFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建分类'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入分类名称'),
          onSubmitted: (_) => Navigator.pop(ctx, controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    final folderName = (name ?? '').trim();
    if (folderName.isEmpty) return;
    try {
      final resp = await AdminHttpClient().dio.post(
        '/assets/folders/create',
        data: {'name': folderName},
      );
      final data = resp.data as Map<String, dynamic>;
      if ((data['code'] ?? -1) != 0) {
        throw Exception((data['message'] ?? '创建分类失败').toString());
      }
      if (!mounted) return;
      setState(() => _assetFolderFilter = folderName);
      await _loadCurrent();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('分类创建成功')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('创建分类失败：$e')));
    }
  }

  List<Map<String, dynamic>> _topCategories() => _categories;

  List<Map<String, dynamic>> _secondLevelCategories() {
    final result = <Map<String, dynamic>>[];
    for (final parent in _categories) {
      final parentId = (parent['id'] as num?)?.toInt() ?? 0;
      final parentName = (parent['name'] ?? '未命名一级分类').toString();
      final children = parent['children'];
      if (children is List) {
        for (final child in children) {
          final node = (child as Map).cast<String, dynamic>();
          final childId = (node['id'] as num?)?.toInt() ?? 0;
          if (childId <= 0) continue;
          result.add({
            'id': childId,
            'name': (node['name'] ?? '未命名二级分类').toString(),
            'parent_name': parentName,
            'parent_id': parentId,
          });
        }
      }
    }
    return result;
  }

  Future<void> _createCategory({int? parentIdPreset}) async {
    await _loadCategories();
    if (!mounted) return;
    final parentOptions = _topCategories();
    final nameController = TextEditingController();
    final sortController = TextEditingController(text: '0');
    int? selectedParentId = parentIdPreset;
    bool isVisible = true;

    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新建分类'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<int?>(
                  value: selectedParentId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '归属一级分类'),
                  hint: const Text('留空=创建一级分类'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('无（一级分类）'),
                    ),
                    ...parentOptions.map(
                      (e) => DropdownMenuItem<int?>(
                        value: (e['id'] as num?)?.toInt(),
                        child: Text((e['name'] ?? '').toString()),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setDialogState(() => selectedParentId = value);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '分类名称'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: sortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '排序（默认0）'),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('是否可见'),
                  value: isVisible,
                  onChanged: (value) => setDialogState(() => isVisible = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );

    if (submitted != true) return;
    final name = nameController.text.trim();
    if (name.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('分类名称不能为空')));
      return;
    }
    final sortOrder = int.tryParse(sortController.text.trim()) ?? 0;
    try {
      final resp = await AdminHttpClient().dio.post(
        '/categories',
        data: {
          'name': name,
          'parent_id': selectedParentId,
          'sort_order': sortOrder,
          'is_visible': isVisible,
        },
      );
      final data = resp.data as Map<String, dynamic>;
      if ((data['code'] ?? -1) != 0) {
        throw Exception((data['message'] ?? '创建分类失败').toString());
      }
      await _loadCurrent();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('分类创建成功')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('创建分类失败：$e')));
    }
  }

  String _titleFromFile(XFile file) {
    final name = _filename(file);
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return name;
    return name.substring(0, dot);
  }

  Future<void> _createImageMaterialsFromPicker() async {
    if (_creatingMaterials) return;
    await _loadCategories();
    if (!mounted) return;
    final secondLevel = _secondLevelCategories();
    int? selectedCategoryId =
        secondLevel.isNotEmpty ? (secondLevel.first['id'] as int?) : null;
    bool showInspiration = false;
    bool showMoments = false;

    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('上传并发布图片素材'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (secondLevel.isNotEmpty)
                DropdownButtonFormField<int>(
                  value: selectedCategoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '二级分类'),
                  items: secondLevel
                      .map(
                        (item) => DropdownMenuItem<int>(
                          value: item['id'] as int,
                          child: Text(
                            '${item['parent_name']} / ${item['name']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    setDialogState(() => selectedCategoryId = value);
                  },
                )
              else
                const Text(
                  '当前还没有二级分类，素材将先创建为未分类。\n建议先到“分类”菜单创建一级和二级分类。',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              const SizedBox(height: 8),
              CheckboxListTile(
                dense: true,
                value: showInspiration,
                contentPadding: EdgeInsets.zero,
                title: const Text('同步投放到找灵感'),
                onChanged: (value) {
                  setDialogState(() => showInspiration = value ?? false);
                },
              ),
              CheckboxListTile(
                dense: true,
                value: showMoments,
                contentPadding: EdgeInsets.zero,
                title: const Text('同步投放到朋友圈'),
                onChanged: (value) {
                  setDialogState(() => showMoments = value ?? false);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('下一步选图'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true) return;

    final picked = await _picker.pickMultiImage();
    if (!mounted || picked.isEmpty) return;

    setState(() => _creatingMaterials = true);
    final failed = <String>[];
    var success = 0;
    try {
      for (final file in picked) {
        try {
          final asset = await _uploadOne(file);
          final rawUrl = (asset['url'] ?? '').toString();
          final previewUrl = (asset['preview_url'] ?? '').toString();
          if (rawUrl.isEmpty) {
            throw Exception('上传后未返回文件地址');
          }

          final payload = <String, dynamic>{
            'title': _titleFromFile(file),
            'description': '',
            'type': 'image',
            'status': 'published',
            'original_urls': [rawUrl],
            'thumbnail_url': previewUrl.isNotEmpty ? previewUrl : rawUrl,
            'show_inspiration': showInspiration,
            'show_moments': showMoments,
          };
          if (selectedCategoryId != null && selectedCategoryId! > 0) {
            payload['category_id'] = selectedCategoryId;
          }

          final resp = await AdminHttpClient().dio.post('/materials', data: payload);
          final data = resp.data as Map<String, dynamic>;
          if ((data['code'] ?? -1) != 0) {
            throw Exception((data['message'] ?? '创建素材失败').toString());
          }
          success += 1;
        } catch (e) {
          failed.add('${_filename(file)}：$e');
        }
      }

      await _loadCurrent();
      if (!mounted) return;
      final message = failed.isEmpty
          ? '已成功创建 $success 条图片素材'
          : '成功 $success 条，失败 ${failed.length} 条';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

      if (failed.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('部分素材创建失败'),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Text(failed.take(20).join('\n')),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _creatingMaterials = false);
      }
    }
  }

  Future<void> _pickImages() async {
    final files = await _picker.pickMultiImage();
    if (!mounted || files.isEmpty) return;
    setState(() => _images = files);
  }

  Future<void> _pickVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (!mounted || file == null) return;
    setState(() => _singleVideo = file);
  }

  Future<void> _pickLiveImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (!mounted || file == null) return;
    setState(() => _liveImage = file);
  }

  Future<void> _pickLiveVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (!mounted || file == null) return;
    setState(() => _liveVideo = file);
  }

  Future<void> _pickLiveFromSystem() async {
    try {
      final picked = await NativeLivePicker.pickLiveForUpload();
      if (!mounted || picked == null) return;
      setState(() {
        _liveImage = XFile(picked.imagePath);
        _liveVideo = XFile(picked.videoPath);
        _liveSource = picked.source;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已从系统相册识别 Live 资源')),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? '系统相册识别 Live 失败')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('系统相册识别 Live 失败：$e')),
      );
    }
  }

  String _filename(XFile file) => file.path.split(Platform.pathSeparator).last;

  Future<Map<String, dynamic>> _uploadOne(
    XFile file, {
    String? liveRole,
    String? folder,
  }) async {
    final folderText = (folder ?? _folder).trim();
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: _filename(file)),
      if (folderText.isNotEmpty) 'folder': folderText,
      if (liveRole != null) 'live_role': liveRole,
    });
    final resp = await AdminHttpClient().dio.post(
      '/assets/upload',
      data: formData,
      options: Options(headers: {'Content-Type': 'multipart/form-data'}),
    );
    final data = resp.data as Map<String, dynamic>;
    if ((data['code'] ?? -1) != 0) {
      throw Exception((data['message'] ?? '上传失败').toString());
    }
    return ((data['data'] as Map?) ?? const {}).cast<String, dynamic>();
  }

  Future<void> _startUpload() async {
    if (_uploading) return;
    if (_uploadMode == 'image' && _images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择图片')),
      );
      return;
    }
    if (_uploadMode == 'video' && _singleVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择视频')),
      );
      return;
    }
    if (_uploadMode == 'live' && (_liveImage == null || _liveVideo == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择 Live 静态图和动态视频')),
      );
      return;
    }

    setState(() => _uploading = true);
    try {
      if (_uploadMode == 'image') {
        for (final file in _images) {
          await _uploadOne(file);
        }
      } else if (_uploadMode == 'video') {
        await _uploadOne(_singleVideo!);
      } else {
        await _uploadOne(_liveImage!, liveRole: 'image');
        await _uploadOne(_liveVideo!, liveRole: 'video');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('上传成功')),
      );
      setState(() {
        _images = const [];
        _singleVideo = null;
        _liveImage = null;
        _liveVideo = null;
        _liveSource = '';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
      }
    }
  }

  Future<void> _replyQuestion(dynamic item) async {
    final id = (item['id'] ?? 0).toString();
    final controller = TextEditingController(
      text: (item['reply_text'] ?? '').toString(),
    );
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('回复提问 #$id'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(hintText: '输入回复内容'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('提交'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    try {
      final resp = await AdminHttpClient().dio.put(
        '/questions/$id/reply',
        data: {'reply_text': text},
      );
      final data = resp.data as Map<String, dynamic>;
      if ((data['code'] ?? -1) == 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('回复成功')),
        );
        await _loadCurrent();
      } else {
        throw Exception((data['message'] ?? '回复失败').toString());
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('回复失败：$e')),
      );
    }
  }

  Widget _buildDashboard() {
    final d = _dashboard ?? {};
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _kvCard('用户总数', '${d['user_count'] ?? '-'}'),
        _kvCard('素材总数', '${d['material_count'] ?? '-'}'),
        _kvCard('订单总数', '${d['order_count'] ?? '-'}'),
        _kvCard('待回复提问', '${d['question_count'] ?? '-'}'),
      ],
    );
  }

  Widget _kvCard(String title, String value) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildUpload() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '上传模式',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'image', label: Text('图片')),
                    ButtonSegment(value: 'video', label: Text('视频')),
                    ButtonSegment(value: 'live', label: Text('Live')),
                  ],
                  selected: {_uploadMode},
                  onSelectionChanged: (v) {
                    setState(() {
                      _uploadMode = v.first;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    labelText: '分类文件夹（可选）',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => _folder = v,
                ),
                const SizedBox(height: 12),
                if (_uploadMode == 'image') ...[
                  ElevatedButton(
                    onPressed: _pickImages,
                    child: const Text('选择图片（可多选）'),
                  ),
                  const SizedBox(height: 6),
                  Text('已选 ${_images.length} 张'),
                ],
                if (_uploadMode == 'video') ...[
                  ElevatedButton(
                    onPressed: _pickVideo,
                    child: const Text('选择视频'),
                  ),
                  const SizedBox(height: 6),
                  Text(_singleVideo == null ? '未选择视频' : _filename(_singleVideo!)),
                ],
                if (_uploadMode == 'live') ...[
                  ElevatedButton(
                    onPressed: _pickLiveFromSystem,
                    child: const Text('从系统相册选择 Live（推荐）'),
                  ),
                  if (_liveSource.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('识别来源：$_liveSource'),
                  ],
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _pickLiveImage,
                    child: const Text('选择 Live 静态图（HEIC/HEIF）'),
                  ),
                  const SizedBox(height: 6),
                  Text(_liveImage == null ? '未选择静态图' : _filename(_liveImage!)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _pickLiveVideo,
                    child: const Text('选择 Live 动态视频（MOV）'),
                  ),
                  const SizedBox(height: 6),
                  Text(_liveVideo == null ? '未选择动态视频' : _filename(_liveVideo!)),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _uploading ? null : _startUpload,
                    child: Text(_uploading ? '上传中...' : '开始上传'),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '说明：Live 上传会按 image/video 两个资源分别上传到现有后台配对逻辑。',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAssetsVisual() {
    final chips = <Widget>[
      _folderChip(
        value: _allFoldersValue,
        label: '全部',
        count: null,
      ),
    ];
    for (final item in _assetFolders) {
      final raw = (item['folder'] ?? '').toString();
      final count = (item['count'] as num?)?.toInt();
      chips.add(
        _folderChip(
          value: raw.isEmpty ? _uncategorizedFolderValue : raw,
          label: raw.isEmpty ? '未分类' : raw,
          count: count,
        ),
      );
    }
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...chips,
              OutlinedButton.icon(
                onPressed: _createAssetFolder,
                icon: const Icon(Icons.add),
                label: const Text('新建分类'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _buildVisualCards(
            _assets,
            empty: '暂无素材库数据',
            isMaterial: false,
          ),
        ),
      ],
    );
  }

  Widget _folderChip({
    required String value,
    required String label,
    required int? count,
  }) {
    final selected = _assetFolderFilter == value;
    final suffix = count == null ? '' : ' $count';
    return ChoiceChip(
      label: Text('$label$suffix'),
      selected: selected,
      onSelected: (_) async {
        if (_assetFolderFilter == value) return;
        setState(() => _assetFolderFilter = value);
        await _loadCurrent();
      },
    );
  }

  Widget _buildMaterialsVisual() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _creatingMaterials ? null : _createImageMaterialsFromPicker,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(_creatingMaterials ? '处理中...' : '上传图片并发布素材'),
              ),
              if (_creatingMaterials)
                const Text(
                  '正在上传并创建素材，请稍候...',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
            ],
          ),
        ),
        Expanded(
          child: _buildVisualCards(_materials, empty: '暂无素材数据', isMaterial: true),
        ),
      ],
    );
  }

  Widget _buildCategoryManager() {
    if (_categories.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: _createCategory,
              icon: const Icon(Icons.add),
              label: const Text('新建分类'),
            ),
          ),
          const SizedBox(height: 12),
          const Center(child: Text('暂无分类数据')),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton.icon(
            onPressed: _createCategory,
            icon: const Icon(Icons.add),
            label: const Text('新建分类'),
          ),
        ),
        const SizedBox(height: 10),
        ..._categories.map((parent) {
          final parentName = (parent['name'] ?? '未命名一级分类').toString();
          final parentId = (parent['id'] ?? '-').toString();
          final children = List<dynamic>.from(parent['children'] ?? const []);
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$parentName（ID: $parentId）',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _createCategory(
                          parentIdPreset: (parent['id'] as num?)?.toInt(),
                        ),
                        child: const Text('加子分类'),
                      ),
                    ],
                  ),
                  if (children.isEmpty)
                    const Text(
                      '暂无二级分类',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    )
                  else
                    ...children.map((child) {
                      final node = (child as Map).cast<String, dynamic>();
                      final name = (node['name'] ?? '未命名二级分类').toString();
                      final id = (node['id'] ?? '-').toString();
                      return Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.subdirectory_arrow_right, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '$name（ID: $id）',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildVisualCards(List<dynamic> items, {required String empty, required bool isMaterial}) {
    if (items.isEmpty) return Center(child: Text(empty));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = (items[index] as Map).cast<String, dynamic>();
        final title = (item['title'] ?? item['original_name'] ?? '未命名').toString();
        final type = (item['type'] ?? item['file_type'] ?? '-').toString();
        final thumbUrl = isMaterial ? _materialThumbUrl(item) : _assetThumbUrl(item);
        final isVideo = _isVideoType(type) || _isVideoUrl(thumbUrl);
        final status = (item['status'] ?? '').toString();
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _thumbView(thumbUrl: thumbUrl, isVideo: isVideo),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _miniTag('ID ${item['id'] ?? '-'}'),
                          _miniTag(type),
                          if (status.isNotEmpty) _miniTag(status),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isMaterial
                            ? '分类: ${(item['category_name'] ?? item['category']?['name'] ?? '-').toString()}'
                            : '文件夹: ${(item['folder'] ?? '未分类').toString()}',
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _miniTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, color: Colors.black87),
      ),
    );
  }

  Widget _thumbView({required String thumbUrl, required bool isVideo}) {
    return Container(
      width: 86,
      height: 86,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumbUrl.isNotEmpty)
            Image.network(
              thumbUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _thumbPlaceholder(isVideo),
            )
          else
            _thumbPlaceholder(isVideo),
          if (isVideo)
            const Center(
              child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 30),
            ),
        ],
      ),
    );
  }

  Widget _thumbPlaceholder(bool isVideo) {
    return Container(
      color: Colors.grey.shade300,
      alignment: Alignment.center,
      child: Icon(
        isVideo ? Icons.videocam_rounded : Icons.image_rounded,
        color: Colors.grey.shade600,
      ),
    );
  }

  String _assetThumbUrl(Map<String, dynamic> item) {
    final preview = (item['preview_url'] ?? '').toString();
    if (preview.isNotEmpty) return UrlUtils.absolute(preview);
    final raw = (item['url'] ?? '').toString();
    if (raw.toLowerCase().endsWith('.heic') || raw.toLowerCase().endsWith('.heif')) {
      final idx = raw.lastIndexOf('.');
      if (idx > 0) {
        final candidate = '${raw.substring(0, idx)}_preview.jpg';
        return UrlUtils.absolute(candidate);
      }
    }
    return UrlUtils.absolute(raw);
  }

  String _materialThumbUrl(Map<String, dynamic> item) {
    final thumb = (item['thumbnail_url'] ?? '').toString();
    if (thumb.isNotEmpty) return UrlUtils.absolute(thumb);
    final list = item['original_urls'];
    if (list is List && list.isNotEmpty) {
      final first = list.first?.toString() ?? '';
      return UrlUtils.absolute(first);
    }
    return '';
  }

  bool _isVideoType(String type) {
    final value = type.toLowerCase();
    return value == 'video' || value == 'mov' || value == 'mp4';
  }

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm');
  }

  Widget _buildQuestions() {
    if (_questions.isEmpty) {
      return const Center(child: Text('暂无提问'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _questions.length,
      itemBuilder: (context, index) {
        final item = (_questions[index] as Map).cast<String, dynamic>();
        return Card(
          child: ListTile(
            title: Text(
              (item['question_text'] ?? '').toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              'ID: ${item['id'] ?? '-'}  状态: ${(item['status'] ?? '-').toString()}',
            ),
            trailing: TextButton(
              onPressed: () => _replyQuestion(item),
              child: const Text('回复'),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildDashboard(),
      _buildUpload(),
      _buildAssetsVisual(),
      _buildMaterialsVisual(),
      _buildQuestions(),
      _buildCategoryManager(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('管理员工作台'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadCurrent,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: '退出管理员',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          _loadCurrent();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: '看板'),
          NavigationDestination(icon: Icon(Icons.upload_file_outlined), label: '上传'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), label: '素材库'),
          NavigationDestination(icon: Icon(Icons.image_outlined), label: '素材'),
          NavigationDestination(icon: Icon(Icons.question_answer_outlined), label: '提问'),
          NavigationDestination(icon: Icon(Icons.account_tree_outlined), label: '分类'),
        ],
      ),
    );
  }
}
