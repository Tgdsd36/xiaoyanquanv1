import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../app/colors.dart';
import '../../../core/utils/url_utils.dart';
import '../auth/admin_auth_storage.dart';
import '../network/admin_http_client.dart';
import '../services/native_live_picker.dart';

class _LiveUploadPair {
  final XFile image;
  final XFile video;
  final String baseName;
  final String source;

  const _LiveUploadPair({
    required this.image,
    required this.video,
    required this.baseName,
    required this.source,
  });
}

class AdminNativeWorkbenchPage extends StatefulWidget {
  const AdminNativeWorkbenchPage({super.key});

  @override
  State<AdminNativeWorkbenchPage> createState() =>
      _AdminNativeWorkbenchPageState();
}

class _AdminNativeWorkbenchPageState extends State<AdminNativeWorkbenchPage> {
  static const String _allFoldersValue = '__all__';
  static const String _uncategorizedFolderValue = '__uncategorized__';
  static const List<String> _tabTitles = [
    '看板',
    '上传',
    '素材库',
    '素材',
    '提问',
    '分类',
  ];
  static const List<String> _tabSubtitles = [
    '核心数据概览与快捷入口',
    '图片 / 视频 / Live 素材上传',
    '可视化浏览资源与分组',
    '发布素材并投放渠道',
    '用户提问与回复处理',
    '一级 / 二级分类管理',
  ];
  static const List<IconData> _tabIcons = [
    Icons.space_dashboard_rounded,
    Icons.upload_file_rounded,
    Icons.folder_rounded,
    Icons.photo_library_rounded,
    Icons.forum_rounded,
    Icons.account_tree_rounded,
  ];

  final _storage = AdminAuthStorage();
  final _picker = ImagePicker();

  int _index = 0;
  bool _loading = false;
  bool _uploading = false;
  Map<String, dynamic>? _dashboard;
  List<dynamic> _assets = const [];
  List<Map<String, dynamic>> _assetLivePacks = const [];
  List<dynamic> _materials = const [];
  List<dynamic> _questions = const [];
  List<Map<String, dynamic>> _assetFolders = const [];
  List<Map<String, dynamic>> _categories = const [];
  String _assetFolderFilter = _allFoldersValue;
  final TextEditingController _publishTitleController = TextEditingController();
  List<Map<String, dynamic>> _publishSourceAssets = const [];
  List<Map<String, dynamic>> _publishSourceLivePacks = const [];
  Set<int> _selectedPublishAssetIds = <int>{};
  Set<int> _selectedPublishLivePackIds = <int>{};
  int? _publishCategoryId;
  bool _publishShowInspiration = false;
  bool _publishShowMoments = false;
  bool _publishingMaterial = false;
  bool _showMaterialComposer = false;

  String _uploadMode = 'image'; // image/video/live
  String _folder = '';
  String? _uploadSelectedFolder; // null=文件夹网格, 非null=进入该分类上传
  Map<String, String> _folderThumbnails = const {};
  List<Map<String, dynamic>> _folderExistingAssets = const [];
  List<Map<String, dynamic>> _folderExistingLivePacks = const [];
  XFile? _singleVideo;
  XFile? _liveImage;
  XFile? _liveVideo;
  List<_LiveUploadPair> _livePairs = const [];
  bool _showManualLive = false;
  int _uploadCurrent = 0;
  int _uploadTotal = 0;
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

  @override
  void dispose() {
    _publishTitleController.dispose();
    super.dispose();
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
    } else if (_index == 1) {
        await _loadAssetFolders();
        await _loadFolderThumbnails();
      } else if (_index == 2) {
        await _loadAssetFolders();
        await _loadAssets();
        await _loadAssetLivePacks();
      } else if (_index == 3) {
        await _loadCategories();
        await _loadMaterials();
        await _loadPublishSourceAssets();
        await _loadPublishSourceLivePacks();
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

  Future<void> _loadAssetLivePacks() async {
    final params = <String, dynamic>{'page': 1, 'page_size': 20};
    if (_assetFolderFilter != _allFoldersValue) {
      params['folder'] = _assetFolderFilter == _uncategorizedFolderValue
          ? ''
          : _assetFolderFilter;
    }
    final resp = await AdminHttpClient().dio.get(
      '/assets/live-packs',
      queryParameters: params,
    );
    final data = resp.data as Map<String, dynamic>;
    if ((data['code'] ?? -1) != 0) return;
    final payload = (data['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final list = List<dynamic>.from(payload['list'] ?? const []);
    _assetLivePacks = list
        .map((item) => (item as Map).cast<String, dynamic>())
        .toList(growable: false);
  }

  Future<void> _loadFolderThumbnails() async {
    final resp = await AdminHttpClient().dio.get(
      '/assets',
      queryParameters: {'page': 1, 'page_size': 200},
    );
    final data = resp.data as Map<String, dynamic>;
    if ((data['code'] ?? -1) != 0) return;
    final payload = (data['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final list = List<dynamic>.from(payload['list'] ?? const []);
    final thumbs = <String, String>{};
    for (final raw in list) {
      final item = (raw as Map).cast<String, dynamic>();
      final folder = (item['folder'] ?? '').toString();
      if (thumbs.containsKey(folder)) continue;
      final url = _assetThumbUrl(item);
      if (url.isNotEmpty) thumbs[folder] = url;
    }
    _folderThumbnails = thumbs;
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
    setState(() {
      _liveImage = file;
      _livePairs = const [];
    });
  }

  Future<void> _pickLiveVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (!mounted || file == null) return;
    setState(() {
      _liveVideo = file;
      _livePairs = const [];
    });
  }

  Future<void> _pickLiveFromSystem() async {
    try {
      final results = await NativeLivePicker.pickMultipleLiveForUpload();
      if (!mounted || results.isEmpty) return;
      final newPairs = results
          .map(
            (r) => _LiveUploadPair(
              image: XFile(r.imagePath),
              video: XFile(r.videoPath),
              baseName: _normalizeLiveBatchBase(r.imageName),
              source: r.source,
            ),
          )
          .toList();
      setState(() {
        _livePairs = [..._livePairs, ...newPairs];

      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已选择 ${newPairs.length} 张 Live Photo')),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? '选择 Live Photo 失败')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择 Live Photo 失败：$e')),
      );
    }
  }

  String _fileExt(XFile file) {
    final name = _filename(file).toLowerCase();
    final idx = name.lastIndexOf('.');
    if (idx < 0 || idx >= name.length - 1) return '';
    return name.substring(idx + 1);
  }

  String _nameWithoutExt(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot <= 0) return filename;
    return filename.substring(0, dot);
  }

  String _normalizeLiveBatchBase(String filename) {
    var name = _nameWithoutExt(filename).toLowerCase().trim();
    name = name.replaceAll('（', '(').replaceAll('）', ')');
    name = name.replaceAll(RegExp(r'\s*\(\d+\)$'), '');
    name = name.replaceAll(RegExp(r'\s+\d+$'), '');
    name = name.replaceAll(
      RegExp(r'([_\-\s]+)?(image|photo|static|heic|heif)$'),
      '',
    );
    name = name.replaceAll(
      RegExp(r'([_\-\s]+)?(video|mov|motion)$'),
      '',
    );
    return name.trim();
  }

  bool _isLiveImageCandidate(XFile file) {
    final ext = _fileExt(file);
    return ext == 'heic' || ext == 'heif';
  }

  bool _isLiveVideoCandidate(XFile file) {
    final ext = _fileExt(file);
    return ext == 'mov';
  }

  Future<void> _pickLiveBatchFiles() async {
    try {
      final files = await _picker.pickMultipleMedia();
      if (!mounted || files.isEmpty) return;

      final images = <String, List<XFile>>{};
      final videos = <String, List<XFile>>{};
      var skipped = 0;

      for (final file in files) {
        final name = _filename(file);
        final base = _normalizeLiveBatchBase(name);
        if (base.isEmpty) {
          skipped += 1;
          continue;
        }
        if (_isLiveImageCandidate(file)) {
          images.putIfAbsent(base, () => <XFile>[]).add(file);
        } else if (_isLiveVideoCandidate(file)) {
          videos.putIfAbsent(base, () => <XFile>[]).add(file);
        } else {
          skipped += 1;
        }
      }

      final pairs = <_LiveUploadPair>[];
      var unpaired = 0;
      final allBases = <String>{...images.keys, ...videos.keys};
      for (final base in allBases) {
        final imgList = images[base] ?? const <XFile>[];
        final vidList = videos[base] ?? const <XFile>[];
        final pairCount = imgList.length < vidList.length ? imgList.length : vidList.length;
        for (var i = 0; i < pairCount; i++) {
          pairs.add(
            _LiveUploadPair(
              image: imgList[i],
              video: vidList[i],
              baseName: base,
              source: 'batch_gallery',
            ),
          );
        }
        unpaired += (imgList.length - pairCount).abs();
        unpaired += (vidList.length - pairCount).abs();
      }

      if (pairs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未识别到可配对的 Live（需 HEIC/HEIF + MOV）')),
        );
        return;
      }

      setState(() {
        _livePairs = pairs;
        _liveImage = pairs.first.image;
        _liveVideo = pairs.first.video;

      });

      final msg = '已识别 ${pairs.length} 套 Live'
          '${unpaired > 0 ? '，未配对 $unpaired 个文件' : ''}'
          '${skipped > 0 ? '，跳过 $skipped 个非 Live 文件' : ''}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? '批量选择 Live 失败')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('批量选择 Live 失败：$e')),
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
    final count = _uploadItemCount;
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择文件')),
      );
      return;
    }

    int total = 0;
    if (_uploadMode == 'image') {
      total = _images.length;
    } else if (_uploadMode == 'video') {
      total = 1;
    } else {
      total = _livePairs.isNotEmpty ? _livePairs.length * 2 : 2;
    }

    setState(() {
      _uploading = true;
      _uploadCurrent = 0;
      _uploadTotal = total;
    });
    try {
      if (_uploadMode == 'image') {
        for (final file in _images) {
          await _uploadOne(file);
          if (mounted) setState(() => _uploadCurrent++);
        }
      } else if (_uploadMode == 'video') {
        await _uploadOne(_singleVideo!);
        if (mounted) setState(() => _uploadCurrent++);
      } else {
        if (_livePairs.isNotEmpty) {
          for (final pair in _livePairs) {
            await _uploadOne(pair.image, liveRole: 'image');
            if (mounted) setState(() => _uploadCurrent++);
            await _uploadOne(pair.video, liveRole: 'video');
            if (mounted) setState(() => _uploadCurrent++);
          }
        } else {
          await _uploadOne(_liveImage!, liveRole: 'image');
          if (mounted) setState(() => _uploadCurrent++);
          await _uploadOne(_liveVideo!, liveRole: 'video');
          if (mounted) setState(() => _uploadCurrent++);
        }
      }
      if (!mounted) return;
      final successText = _uploadMode == 'live' && _livePairs.isNotEmpty
          ? '上传成功，已完成 ${_livePairs.length} 套 Live'
          : '上传成功';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successText)),
      );
      setState(() {
        _images = const [];
        _singleVideo = null;
        _liveImage = null;
        _liveVideo = null;

        _livePairs = const [];
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadCurrent = 0;
          _uploadTotal = 0;
        });
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

  void _switchTab(int index) {
    if (_index == index) return;
    setState(() => _index = index);
    _loadCurrent();
  }

  ButtonStyle _compactElevatedStyle() {
    return ElevatedButton.styleFrom(
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  ButtonStyle _compactOutlinedStyle() {
    return OutlinedButton.styleFrom(
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: AppColors.border),
    );
  }

  Widget _buildShellHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppColors.primary,
            ),
            alignment: Alignment.center,
            child: Icon(_tabIcons[_index], color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '超级后台管理员',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _tabTitles[_index],
                  style: const TextStyle(
                    fontSize: 19,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _tabSubtitles[_index],
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _buildHeaderAction(
            onTap: _loading ? null : _loadCurrent,
            icon: Icons.refresh_rounded,
          ),
          const SizedBox(width: 8),
          _buildHeaderAction(
            onTap: _logout,
            icon: Icons.logout_rounded,
            danger: true,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderAction({
    required VoidCallback? onTap,
    required IconData icon,
    bool danger = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Ink(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: danger
              ? AppColors.error.withValues(alpha: 0.12)
              : AppColors.surface,
          border: Border.all(
            color: danger
                ? AppColors.error.withValues(alpha: 0.25)
                : AppColors.border,
          ),
        ),
        child: Icon(
          icon,
          color: danger ? AppColors.error : AppColors.textBody,
          size: 19,
        ),
      ),
    );
  }

  Widget _glassShell({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: Colors.white.withValues(alpha: 0.92),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildFloatingNav() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: Colors.white.withValues(alpha: 0.94),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: List.generate(_tabTitles.length, (i) {
                final selected = _index == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _switchTab(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        color: selected ? AppColors.primary : Colors.transparent,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _tabIcons[i],
                            size: 18,
                            color: selected ? Colors.white : AppColors.textSecondary,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _tabTitles[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                              color: selected ? Colors.white : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildDashboard() {
    final d = _dashboard ?? {};
    const accents = [
      AppColors.memberPro,
      AppColors.videoBadge,
      AppColors.warning,
      AppColors.primary,
    ];
    final items = [
      {'title': '用户总数', 'value': '${d['user_count'] ?? '-'}', 'icon': Icons.people_alt_rounded},
      {'title': '素材总数', 'value': '${d['material_count'] ?? '-'}', 'icon': Icons.perm_media_rounded},
      {'title': '订单总数', 'value': '${d['order_count'] ?? '-'}', 'icon': Icons.receipt_long_rounded},
      {'title': '待回复提问', 'value': '${d['question_count'] ?? '-'}', 'icon': Icons.mark_chat_unread_rounded},
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: AppColors.primaryBg,
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.24)),
          ),
          child: const Row(
            children: [
              Icon(Icons.insights_rounded, color: AppColors.primary, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '今日运营总览',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '实时',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          itemCount: items.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.65,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return _kvCard(
              (item['title'] ?? '').toString(),
              (item['value'] ?? '').toString(),
              item['icon'] as IconData,
              accents[index],
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _quickActionCard(
                icon: Icons.upload_rounded,
                title: '去上传',
                subtitle: '上传素材文件',
                color: AppColors.primary,
                onTap: () => _switchTab(1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _quickActionCard(
                icon: Icons.mark_chat_unread_rounded,
                title: '处理提问',
                subtitle: '回复用户提问',
                color: AppColors.videoBadge,
                onTap: () => _switchTab(4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time_rounded, size: 14, color: AppColors.textHint),
            const SizedBox(width: 4),
            Text(
              '运营数据每次进入页面时刷新',
              style: TextStyle(fontSize: 11, color: AppColors.textHint),
            ),
          ],
        ),
      ],
    );
  }

  Widget _kvCard(String title, String value, IconData icon, Color accent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.5), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _sectionBlock({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }

  Widget _toolbarShell({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }

  Widget _emptyHint(String text) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ==================== 上传页面 UI 组件 ====================

  int get _uploadItemCount {
    switch (_uploadMode) {
      case 'image':
        return _images.length;
      case 'video':
        return _singleVideo != null ? 1 : 0;
      case 'live':
        if (_livePairs.isNotEmpty) return _livePairs.length;
        return (_liveImage != null && _liveVideo != null) ? 1 : 0;
      default:
        return 0;
    }
  }

  Widget _buildPillTabSelector({bool dark = false}) {
    const modes = [
      {'value': 'image', 'label': '图片', 'icon': Icons.image_rounded},
      {'value': 'video', 'label': '视频', 'icon': Icons.videocam_rounded},
      {'value': 'live', 'label': 'Live', 'icon': Icons.auto_awesome_rounded},
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: dark ? Colors.black.withValues(alpha: 0.3) : AppColors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: modes.map((m) {
          final value = m['value'] as String;
          final selected = _uploadMode == value;
          final unselectedColor = dark ? Colors.white70 : AppColors.textSecondary;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _uploadMode = value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      m['icon'] as IconData,
                      size: 16,
                      color: selected ? Colors.white : unselectedColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      m['label'] as String,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : unselectedColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _createUploadFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建分类'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入分类名称'),
          onSubmitted: (_) =>
              Navigator.pop(ctx, controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, controller.text.trim()),
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
        throw Exception(
            (data['message'] ?? '创建分类失败').toString());
      }
      await _loadAssetFolders();
      if (!mounted) return;
      setState(() => _folder = folderName);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('分类创建成功')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建分类失败：$e')),
      );
    }
  }

  List<Map<String, dynamic>> get _folderExistingImages =>
      _folderExistingAssets.where(_assetIsImage).toList(growable: false);

  List<Map<String, dynamic>> get _folderExistingVideos =>
      _folderExistingAssets.where(_assetIsVideo).toList(growable: false);

  Widget _buildImageGrid() {
    final existingImages = _folderExistingImages;
    final existingCount = existingImages.length;
    final localCount = _images.length;
    final total = existingCount + localCount + 1; // +1 添加按钮
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: total,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemBuilder: (context, index) {
        // 服务器已有图片
        if (index < existingCount) {
          final item = existingImages[index];
          final url = _assetThumbUrl(item);
          final isVideo = _assetIsVideo(item);
          return Stack(
            fit: StackFit.expand,
            children: [
              url.isNotEmpty
                  ? Image.network(url, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _thumbPlaceholder(isVideo))
                  : _thumbPlaceholder(isVideo),
              if (isVideo)
                Center(
                  child: Icon(Icons.play_circle_fill_rounded,
                      color: Colors.white.withValues(alpha: 0.8), size: 28),
                ),
            ],
          );
        }
        // 添加按钮
        final localIndex = index - existingCount;
        if (localIndex == localCount) {
          return GestureDetector(
            onTap: _pickImages,
            child: Container(
              color: AppColors.surface,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded, color: AppColors.textHint, size: 32),
                  SizedBox(height: 2),
                  Text(
                    '添加照片',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textHint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        // 本地新选文件
        final file = _images[localIndex];
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.file(File(file.path), fit: BoxFit.cover),
            Positioned(
              right: 4,
              top: 4,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    final list = List<XFile>.from(_images);
                    list.removeAt(localIndex);
                    _images = list;
                  });
                },
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVideoContent() {
    final existingVideos = _folderExistingVideos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 已有视频
        if (existingVideos.isNotEmpty) ...[
          ...existingVideos.map((item) {
            final name = _assetSourceName(item);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.videocam_rounded,
                        color: AppColors.textHint, size: 24),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '已上传',
                      style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
        // 本地新选 + 选择入口
        _buildVideoCard(),
      ],
    );
  }

  Widget _buildVideoCard() {
    if (_singleVideo == null) {
      return GestureDetector(
        onTap: _pickVideo,
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.video_library_outlined,
                  color: AppColors.textHint, size: 40),
              SizedBox(height: 8),
              Text(
                '选择视频',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textHint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      height: 160,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: Colors.black.withValues(alpha: 0.05),
            child: const Center(
              child: Icon(Icons.play_circle_fill_rounded,
                  color: AppColors.primary, size: 48),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _filename(_singleVideo!),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: GestureDetector(
              onTap: () => setState(() => _singleVideo = null),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(Icons.close,
                    color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveContent() {
    final existingPacks = _folderExistingLivePacks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 已有 Live 套件
        if (existingPacks.isNotEmpty) ...[
          ...existingPacks.map((pack) {
            final name = _livePackName(pack);
            final imageUrl = _livePackImageDisplayUrl(pack);
            final complete = _livePackComplete(pack);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: imageUrl.isNotEmpty
                        ? Image.network(imageUrl, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.auto_awesome, color: AppColors.textHint))
                        : const Icon(Icons.auto_awesome, color: AppColors.textHint),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          complete ? '完整套件' : '半成品',
                          style: TextStyle(
                            fontSize: 11,
                            color: complete ? AppColors.textSecondary : AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '已上传',
                      style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _pickLiveFromSystem,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            icon: const Icon(Icons.auto_awesome_rounded, size: 20),
            label: const Text(
              '从相册选择 Live',
              style:
                  TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        if (_livePairs.isNotEmpty) ...[
          const SizedBox(height: 12),
          ..._livePairs.asMap().entries.map(
                (entry) =>
                    _buildLiveListCard(entry.value, entry.key),
              ),
          const SizedBox(height: 4),
          Center(
            child: TextButton.icon(
              onPressed: _pickLiveFromSystem,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加更多 Live'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () =>
              setState(() => _showManualLive = !_showManualLive),
          child: Row(
            children: [
              Icon(
                _showManualLive
                    ? Icons.expand_less
                    : Icons.expand_more,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              const Text(
                '手动添加',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (_showManualLive) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                style: _compactOutlinedStyle(),
                onPressed: _pickLiveImage,
                icon: const Icon(Icons.image_outlined, size: 16),
                label: const Text('选择静态图 (HEIC)'),
              ),
              OutlinedButton.icon(
                style: _compactOutlinedStyle(),
                onPressed: _pickLiveVideo,
                icon: const Icon(Icons.movie_outlined, size: 16),
                label: const Text('选择动态视频 (MOV)'),
              ),
              OutlinedButton.icon(
                style: _compactOutlinedStyle(),
                onPressed: _pickLiveBatchFiles,
                icon: const Icon(
                    Icons.library_add_check_outlined,
                    size: 16),
                label: const Text('批量选择文件配对'),
              ),
            ],
          ),
          if (_liveImage != null || _liveVideo != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '静态图：${_liveImage != null ? _filename(_liveImage!) : "未选择"}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '动态视频：${_liveVideo != null ? _filename(_liveVideo!) : "未选择"}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildLiveListCard(_LiveUploadPair pair, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: AppColors.surface,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(pair.image.path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.image,
                      color: AppColors.textHint),
                ),
                Positioned(
                  left: 3,
                  bottom: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color:
                          Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pair.baseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_filename(pair.image)} + ${_filename(pair.video)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '来源：${_liveSourceLabel(pair.source)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                final list =
                    List<_LiveUploadPair>.from(_livePairs);
                list.removeAt(index);
                _livePairs = list;
              });
            },
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Icon(Icons.close,
                  size: 14, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  String _liveSourceLabel(String source) {
    switch (source) {
      case 'ios_live_photo':
        return '系统相册';
      case 'android_motion_photo':
        return 'Motion Photo';
      case 'batch_gallery':
        return '批量配对';
      default:
        return '手动选择';
    }
  }

  Widget _buildUploadBottomBar() {
    final count = _uploadItemCount;
    final hasContent = count > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _uploading ? null : _addContentForCurrentMode,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded, size: 20,
                        color: _uploading ? AppColors.textDisabled : AppColors.textPrimary),
                    const SizedBox(width: 4),
                    Text(
                      '添加素材',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _uploading ? AppColors.textDisabled : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 48,
              child: _uploading
                  ? _buildUploadProgressBtn()
                  : ElevatedButton(
                      onPressed: hasContent ? _startUpload : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.surface,
                        disabledForegroundColor: AppColors.textDisabled,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        hasContent ? '开始上传' : '请先选择',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _addContentForCurrentMode() {
    switch (_uploadMode) {
      case 'image':
        _pickImages();
        break;
      case 'video':
        _pickVideo();
        break;
      case 'live':
        _pickLiveFromSystem();
        break;
    }
  }

  Widget _buildUploadProgressBtn() {
    final progress =
        _uploadTotal > 0 ? _uploadCurrent / _uploadTotal : 0.0;
    final pct = (progress * 100).toInt();
    return Container(
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.primary.withValues(alpha: 0.12),
      ),
      child: Stack(
        children: [
          FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: AppColors.primary,
              ),
            ),
          ),
          Center(
            child: Text(
              '$_uploadCurrent/$_uploadTotal ($pct%)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: progress > 0.5
                    ? Colors.white
                    : AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadCoverHero() {
    final topInset = MediaQuery.of(context).padding.top;
    // 封面图：本地素材 / 已有素材 / 渐变占位
    Widget background;
    final hasImage = _uploadMode == 'image' && _images.isNotEmpty;
    final hasLive = _uploadMode == 'live' && _livePairs.isNotEmpty;
    final hasExisting = _folderExistingAssets.isNotEmpty;
    if (hasImage) {
      background = Image.file(
        File(_images.first.path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => Container(color: AppColors.primary),
      );
    } else if (hasLive) {
      background = Image.file(
        File(_livePairs.first.image.path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => Container(color: AppColors.primary),
      );
    } else if (hasExisting) {
      // 找第一个可渲染缩略图的素材作为封面
      var coverUrl = '';
      for (final asset in _folderExistingAssets) {
        final u = _assetThumbUrl(asset);
        if (u.isNotEmpty) { coverUrl = u; break; }
      }
      background = coverUrl.isNotEmpty
          ? Image.network(
              coverUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => Container(color: AppColors.primary),
            )
          : Container(color: AppColors.primary);
    } else {
      background = Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
    }

    final folderLabel = _folder.isEmpty ? '未分类' : _folder;
    final existingByMode = _uploadMode == 'image'
        ? _folderExistingImages.length
        : _uploadMode == 'video'
            ? _folderExistingVideos.length
            : _folderExistingLivePacks.length;
    final localCount = _uploadItemCount;
    final totalCount = existingByMode + localCount;
    final modeLabel = _uploadMode == 'image'
        ? '张照片'
        : _uploadMode == 'video'
            ? '个视频'
            : '个 Live';

    return SizedBox(
      height: 210 + topInset,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景
          background,
          // 暗色叠加
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.15),
                  Colors.black.withValues(alpha: 0.65),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          // 返回按钮
          Positioned(
            left: 10,
            top: topInset + 10,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _uploadSelectedFolder = null;
                  _folderExistingAssets = const [];
                  _folderExistingLivePacks = const [];
                  _images = const [];
                  _singleVideo = null;
                  _liveImage = null;
                  _liveVideo = null;
                  _livePairs = const [];
                });
                _loadCurrent();
              },
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),
          // 分类名 + 计数
          Positioned(
            left: 16,
            bottom: 56,
            right: 16,
            child: GestureDetector(
              onTap: _showFolderSelector,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      folderLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(blurRadius: 8, color: Colors.black38),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.edit_rounded, size: 13, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 40,
            child: Text(
              '$totalCount $modeLabel',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Pill Tab
          Positioned(
            left: 12,
            right: 12,
            bottom: 0,
            child: _buildPillTabSelector(dark: true),
          ),
        ],
      ),
    );
  }

  void _showFolderSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final folders = _assetFolders
            .where((item) => (item['folder'] ?? '').toString().isNotEmpty)
            .map((item) => (item['folder'] ?? '').toString())
            .toList();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '选择分类',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              // 未分类
              ListTile(
                leading: Icon(
                  Icons.folder_outlined,
                  color: _folder.isEmpty ? AppColors.primary : AppColors.textHint,
                ),
                title: const Text('未分类'),
                trailing: _folder.isEmpty
                    ? const Icon(Icons.check_rounded, color: AppColors.primary, size: 20)
                    : null,
                onTap: () {
                  setState(() => _folder = '');
                  Navigator.pop(ctx);
                },
              ),
              ...folders.map((name) => ListTile(
                    leading: Icon(
                      Icons.folder_rounded,
                      color: _folder == name ? AppColors.primary : AppColors.textHint,
                    ),
                    title: Text(name),
                    trailing: _folder == name
                        ? const Icon(Icons.check_rounded, color: AppColors.primary, size: 20)
                        : null,
                    onTap: () {
                      setState(() => _folder = name);
                      Navigator.pop(ctx);
                    },
                  )),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add_rounded, color: AppColors.primary),
                title: const Text('新建分类',
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(ctx);
                  _createUploadFolder();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUploadProgressBanner() {
    if (!_uploading) return const SizedBox.shrink();
    final progress = _uploadTotal > 0 ? _uploadCurrent / _uploadTotal : 0.0;
    final pct = (progress * 100).toInt();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: AppColors.primaryBg,
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: 2.5,
              color: AppColors.primary,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '正在上传，请勿锁屏或切换应用',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            '$_uploadCurrent/$_uploadTotal ($pct%)',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpload() {
    if (_uploadSelectedFolder == null) {
      return _buildUploadFolderGrid();
    }
    return _buildUploadFolderDetail();
  }

  Widget _buildUploadFolderGrid() {
    // 构建文件夹列表：有名字的分类 + 未分类
    final namedFolders = _assetFolders
        .where((item) => (item['folder'] ?? '').toString().isNotEmpty)
        .toList();
    final uncategorized = _assetFolders
        .where((item) => (item['folder'] ?? '').toString().isEmpty)
        .toList();
    final allFolders = <Map<String, dynamic>>[
      ...namedFolders,
      if (uncategorized.isNotEmpty) uncategorized.first,
    ];

    return Column(
      children: [
        // 顶部标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '我的相簿',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _createAssetFolder,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 16, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        '新建',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // 文件夹网格
        Expanded(
          child: allFolders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.photo_album_rounded,
                          color: AppColors.primary,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '还没有分类',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '点击右上角新建一个分类开始上传',
                        style: TextStyle(fontSize: 12, color: AppColors.textHint),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
                  itemCount: allFolders.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.82,
                  ),
                  itemBuilder: (context, index) {
                    final item = allFolders[index];
                    final folderName = (item['folder'] ?? '').toString();
                    final label = folderName.isEmpty ? '未分类' : folderName;
                    final count = (item['count'] as num?)?.toInt() ?? 0;
                    final thumb = _folderThumbnails[folderName] ?? '';
                    return _buildFolderCard(
                      label: label,
                      folderValue: folderName,
                      count: count,
                      thumbUrl: thumb,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFolderCard({
    required String label,
    required String folderValue,
    required int count,
    required String thumbUrl,
  }) {
    return GestureDetector(
      onTap: () => _enterUploadFolder(folderValue),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面区域
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (thumbUrl.isNotEmpty)
                    Image.network(
                      thumbUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _folderPlaceholder(),
                    )
                  else
                    _folderPlaceholder(),
                  // 右下角计数
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 分类名称
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count 项素材',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enterUploadFolder(String folderValue) async {
    setState(() {
      _uploadSelectedFolder = folderValue;
      _folder = folderValue;
      _folderExistingAssets = const [];
      _folderExistingLivePacks = const [];
      _images = const [];
      _singleVideo = null;
      _liveImage = null;
      _liveVideo = null;
      _livePairs = const [];
    });
    try {
      final resp = await AdminHttpClient().dio.get(
        '/assets',
        queryParameters: {'page': 1, 'page_size': 200, 'folder': folderValue},
      );
      final data = resp.data as Map<String, dynamic>;
      if ((data['code'] ?? -1) != 0) return;
      final payload = (data['data'] as Map?)?.cast<String, dynamic>() ?? {};
      final list = List<dynamic>.from(payload['list'] ?? const []);
      if (!mounted) return;
      setState(() {
        _folderExistingAssets = list
            .map((item) => (item as Map).cast<String, dynamic>())
            .toList(growable: false);
      });
      // 加载 Live 套件
      final liveResp = await AdminHttpClient().dio.get(
        '/assets/live-packs',
        queryParameters: {'page': 1, 'page_size': 200, 'folder': folderValue},
      );
      final liveData = liveResp.data as Map<String, dynamic>;
      if ((liveData['code'] ?? -1) == 0) {
        final livePayload = (liveData['data'] as Map?)?.cast<String, dynamic>() ?? {};
        final liveList = List<dynamic>.from(livePayload['list'] ?? const []);
        if (mounted) {
          setState(() {
            _folderExistingLivePacks = liveList
                .map((item) => (item as Map).cast<String, dynamic>())
                .toList(growable: false);
          });
        }
      }
    } catch (_) {}
  }

  Widget _folderPlaceholder() {
    return Container(
      color: AppColors.surface,
      child: const Center(
        child: Icon(
          Icons.photo_library_rounded,
          color: AppColors.textHint,
          size: 36,
        ),
      ),
    );
  }

  Widget _buildUploadFolderDetail() {
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              // 封面区
              SliverToBoxAdapter(child: _buildUploadCoverHero()),
              // 进度横幅
              SliverToBoxAdapter(child: _buildUploadProgressBanner()),
              // 内容区
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(0, 2, 0, 20),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_uploadMode == 'image') _buildImageGrid(),
              if (_uploadMode == 'video')
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: _buildVideoContent(),
                        ),
                      if (_uploadMode == 'live')
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: _buildLiveContent(),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildUploadBottomBar(),
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
    // 收集已关联到 Live 套件的散件 ID，素材文件列表不再重复展示
    final liveAssetIds = <int>{};
    for (final pack in _assetLivePacks) {
      final imgId = (pack['image_asset_id'] as num?)?.toInt();
      final vidId = (pack['video_asset_id'] as num?)?.toInt();
      if (imgId != null && imgId > 0) liveAssetIds.add(imgId);
      if (vidId != null && vidId > 0) liveAssetIds.add(vidId);
    }
    final filteredAssets = _assets.where((raw) {
      final item = (raw as Map).cast<String, dynamic>();
      final id = (item['id'] as num?)?.toInt() ?? 0;
      return !liveAssetIds.contains(id);
    }).toList();
    final assetCount = filteredAssets.length;
    final liveCount = _assetLivePacks.length;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 0, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...chips,
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: OutlinedButton.icon(
                    style: _compactOutlinedStyle(),
                    onPressed: _createAssetFolder,
                    icon: const Icon(Icons.add),
                    label: const Text('新建分类'),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Text(
                      '素材文件',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (assetCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.imageBadge.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$assetCount',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.imageBadge,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ..._buildVisualCardItems(
                filteredAssets,
                empty: '暂无素材文件',
                isMaterial: false,
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Text(
                      'Live 套件',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (liveCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.liveBadge.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$liveCount',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.liveBadge,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ..._buildLivePackCardItems(_assetLivePacks, empty: '暂无 Live 套件'),
            ],
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
      selectedColor: AppColors.primary.withValues(alpha: 0.16),
      backgroundColor: AppColors.surface,
      side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      onSelected: (_) async {
        if (_assetFolderFilter == value) return;
        setState(() => _assetFolderFilter = value);
        await _loadCurrent();
      },
    );
  }

  Future<void> _loadPublishSourceAssets() async {
    final resp = await AdminHttpClient().dio.get(
      '/assets',
      queryParameters: {'page': 1, 'page_size': 200},
    );
    final data = resp.data as Map<String, dynamic>;
    if ((data['code'] ?? -1) != 0) return;
    final payload = (data['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final list = List<dynamic>.from(payload['list'] ?? const []);
    _publishSourceAssets = list
        .map((item) => (item as Map).cast<String, dynamic>())
        .toList(growable: false);
  }

  Future<void> _loadPublishSourceLivePacks() async {
    final resp = await AdminHttpClient().dio.get(
      '/assets/live-packs',
      queryParameters: {'page': 1, 'page_size': 200},
    );
    final data = resp.data as Map<String, dynamic>;
    if ((data['code'] ?? -1) != 0) return;
    final payload = (data['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final list = List<dynamic>.from(payload['list'] ?? const []);
    _publishSourceLivePacks = list
        .map((item) => (item as Map).cast<String, dynamic>())
        .toList(growable: false);
  }

  int _assetId(Map<String, dynamic> item) => (item['id'] as num?)?.toInt() ?? 0;

  String _assetSourceName(Map<String, dynamic> item) =>
      (item['original_name'] ?? item['title'] ?? '未命名素材').toString();

  String _assetSourceUrl(Map<String, dynamic> item) => (item['url'] ?? '').toString();

  String _assetSourceType(Map<String, dynamic> item) =>
      (item['file_type'] ?? item['type'] ?? '').toString().toLowerCase();

  bool _isImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif');
  }

  bool _assetIsImage(Map<String, dynamic> item) {
    final t = _assetSourceType(item);
    if (t == 'image' ||
        t == 'heic' ||
        t == 'heif' ||
        t == 'jpg' ||
        t == 'jpeg' ||
        t == 'png' ||
        t == 'gif' ||
        t == 'webp' ||
        t == 'bmp') {
      return true;
    }
    return _isImageUrl(_assetSourceUrl(item));
  }

  bool _assetIsVideo(Map<String, dynamic> item) {
    final t = _assetSourceType(item);
    if (t == 'video' || t == 'mov' || t == 'mp4' || t == 'm4v' || t == 'webm') {
      return true;
    }
    return _isVideoUrl(_assetSourceUrl(item));
  }

  String _assetTypeLabel(Map<String, dynamic> item) {
    if (_assetIsVideo(item)) return '视频';
    if (_assetIsImage(item)) return '图片';
    return '其他';
  }

  List<Map<String, dynamic>> _selectedPublishAssets() {
    if (_selectedPublishAssetIds.isEmpty) return const [];
    return _publishSourceAssets
        .where((item) => _selectedPublishAssetIds.contains(_assetId(item)))
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _selectedPublishLivePacks() {
    if (_selectedPublishLivePackIds.isEmpty) return const [];
    return _publishSourceLivePacks
        .where((item) => _selectedPublishLivePackIds.contains(_livePackId(item)))
        .toList(growable: false);
  }

  Future<void> _openPublishAssetSelector() async {
    if (_publishSourceAssets.isEmpty || _publishSourceLivePacks.isEmpty) {
      try {
        await _loadPublishSourceAssets();
        await _loadPublishSourceLivePacks();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载素材库失败：$e')));
        return;
      }
    }
    if (!mounted) return;

    final tempSelectedAssets = Set<int>.from(_selectedPublishAssetIds);
    final tempSelectedLivePacks = Set<int>.from(_selectedPublishLivePackIds);
    var keyword = '';
    var typeFilter = 'all';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filteredAssets = _publishSourceAssets.where((item) {
            final name = _assetSourceName(item).toLowerCase();
            final hitKeyword =
                keyword.trim().isEmpty || name.contains(keyword.trim().toLowerCase());
            if (!hitKeyword) return false;
            if (typeFilter == 'live') return false;
            if (typeFilter == 'image') return _assetIsImage(item);
            if (typeFilter == 'video') return _assetIsVideo(item);
            return true;
          }).toList(growable: false);
          final filteredLivePacks = _publishSourceLivePacks.where((item) {
            final name = _livePackName(item).toLowerCase();
            final hitKeyword =
                keyword.trim().isEmpty || name.contains(keyword.trim().toLowerCase());
            if (!hitKeyword) return false;
            if (typeFilter == 'image' || typeFilter == 'video') return false;
            return true;
          }).toList(growable: false);

          return AlertDialog(
            title: const Text('从素材库选择'),
            content: SizedBox(
              width: 420,
              height: 480,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      hintText: '搜索素材名称',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) {
                      setDialogState(() => keyword = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('全部'),
                        selected: typeFilter == 'all',
                        onSelected: (_) => setDialogState(() => typeFilter = 'all'),
                      ),
                      ChoiceChip(
                        label: const Text('图片'),
                        selected: typeFilter == 'image',
                        onSelected: (_) => setDialogState(() => typeFilter = 'image'),
                      ),
                      ChoiceChip(
                        label: const Text('视频'),
                        selected: typeFilter == 'video',
                        onSelected: (_) => setDialogState(() => typeFilter = 'video'),
                      ),
                      ChoiceChip(
                        label: const Text('Live套件'),
                        selected: typeFilter == 'live',
                        onSelected: (_) => setDialogState(() => typeFilter = 'live'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: (filteredAssets.isEmpty && filteredLivePacks.isEmpty)
                        ? _emptyHint('暂无可选素材')
                        : ListView(
                            children: [
                              if (filteredAssets.isNotEmpty) ...[
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    '素材文件',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: filteredAssets.length,
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                    childAspectRatio: 0.82,
                                  ),
                                  itemBuilder: (context, index) {
                                    final item = filteredAssets[index];
                                    final id = _assetId(item);
                                    final selected = tempSelectedAssets.contains(id);
                                    final thumb = _assetThumbUrl(item);
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () {
                                        setDialogState(() {
                                          if (selected) {
                                            tempSelectedAssets.remove(id);
                                          } else if (id > 0) {
                                            tempSelectedAssets.add(id);
                                          }
                                        });
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: selected ? AppColors.primary : AppColors.border,
                                            width: selected ? 2 : 1,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            Expanded(
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  ClipRRect(
                                                    borderRadius: const BorderRadius.vertical(
                                                      top: Radius.circular(9),
                                                    ),
                                                    child: thumb.isNotEmpty
                                                        ? Image.network(
                                                            thumb,
                                                            fit: BoxFit.cover,
                                                            errorBuilder: (_, __, ___) =>
                                                                _thumbPlaceholder(
                                                              _assetIsVideo(item),
                                                            ),
                                                          )
                                                        : _thumbPlaceholder(_assetIsVideo(item)),
                                                  ),
                                                  Positioned(
                                                    left: 6,
                                                    top: 6,
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.black.withValues(alpha: 0.55),
                                                        borderRadius: BorderRadius.circular(999),
                                                      ),
                                                      child: Text(
                                                        _assetTypeLabel(item),
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  if (selected)
                                                    const Positioned(
                                                      right: 6,
                                                      top: 6,
                                                      child: Icon(
                                                        Icons.check_circle,
                                                        color: AppColors.primary,
                                                        size: 18,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                                              child: Text(
                                                _assetSourceName(item),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.textBody,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                              if (filteredLivePacks.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    'Live套件',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: filteredLivePacks.length,
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                    childAspectRatio: 1.12,
                                  ),
                                  itemBuilder: (context, index) {
                                    final pack = filteredLivePacks[index];
                                    final id = _livePackId(pack);
                                    final selected = tempSelectedLivePacks.contains(id);
                                    final complete = _livePackComplete(pack);
                                    final imageUrl = _livePackImageDisplayUrl(pack);
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () {
                                        if (!complete) return;
                                        setDialogState(() {
                                          if (selected) {
                                            tempSelectedLivePacks.remove(id);
                                          } else if (id > 0) {
                                            tempSelectedLivePacks.add(id);
                                          }
                                        });
                                      },
                                      child: Opacity(
                                        opacity: complete ? 1 : 0.55,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: selected ? AppColors.primary : AppColors.border,
                                              width: selected ? 2 : 1,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Expanded(
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    ClipRRect(
                                                      borderRadius: const BorderRadius.vertical(
                                                        top: Radius.circular(9),
                                                      ),
                                                      child: imageUrl.isNotEmpty
                                                          ? Image.network(
                                                              imageUrl,
                                                              fit: BoxFit.cover,
                                                              errorBuilder: (_, __, ___) =>
                                                                  _thumbPlaceholder(false),
                                                            )
                                                          : _thumbPlaceholder(false),
                                                    ),
                                                    Positioned(
                                                      left: 6,
                                                      top: 6,
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.black.withValues(alpha: 0.55),
                                                          borderRadius: BorderRadius.circular(999),
                                                        ),
                                                        child: const Text(
                                                          'Live',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    if (selected)
                                                      const Positioned(
                                                        right: 6,
                                                        top: 6,
                                                        child: Icon(
                                                          Icons.check_circle,
                                                          color: AppColors.primary,
                                                          size: 18,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                                                child: Column(
                                                  children: [
                                                    Text(
                                                      _livePackName(pack),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color: AppColors.textBody,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      complete ? '完整套件' : '半成品不可选',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: complete
                                                            ? AppColors.textSecondary
                                                            : AppColors.warning,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
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
                child: const Text('确认选择'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() {
      _selectedPublishAssetIds = tempSelectedAssets;
      _selectedPublishLivePackIds = tempSelectedLivePacks;
    });
  }

  Future<void> _publishMaterial() async {
    if (_publishingMaterial) return;
    final title = _publishTitleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入标题')),
      );
      return;
    }
    if (_publishCategoryId == null || _publishCategoryId! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择二级分类')),
      );
      return;
    }

    final selectedAssets = _selectedPublishAssets();
    final selectedLivePacks = _selectedPublishLivePacks();
    if (selectedAssets.isEmpty && selectedLivePacks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先从素材库选择素材')),
      );
      return;
    }
    if (selectedAssets.isNotEmpty && selectedLivePacks.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请勿混选普通素材和Live套件')),
      );
      return;
    }

    setState(() => _publishingMaterial = true);
    try {
      var successCount = 0;
      final failed = <String>[];

      if (selectedAssets.isNotEmpty) {
        final allImage = selectedAssets.every(_assetIsImage);
        final allVideo = selectedAssets.every(_assetIsVideo);
        if (!allImage && !allVideo) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请选择同类型素材（仅图片或仅视频）')),
          );
          return;
        }
        final originalUrls = selectedAssets
            .map(_assetSourceUrl)
            .where((u) => u.trim().isNotEmpty)
            .toList(growable: false);
        if (originalUrls.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('素材地址无效，请重新选择')),
          );
          return;
        }

        final thumb = selectedAssets
            .map(_assetThumbUrl)
            .firstWhere((u) => u.trim().isNotEmpty, orElse: () => originalUrls.first);
        final payload = <String, dynamic>{
          'title': title,
          'description': '',
          'type': allVideo ? 'video' : 'image',
          'category_id': _publishCategoryId,
          'status': 'published',
          'show_inspiration': _publishShowInspiration,
          'show_moments': _publishShowMoments,
          'original_urls': originalUrls,
          'thumbnail_url': thumb,
        };
        final resp = await AdminHttpClient().dio.post('/materials', data: payload);
        final data = resp.data as Map<String, dynamic>;
        if ((data['code'] ?? -1) != 0) {
          throw Exception((data['message'] ?? '发布失败').toString());
        }
        successCount = 1;
      } else {
        for (var i = 0; i < selectedLivePacks.length; i++) {
          final pack = selectedLivePacks[i];
          final complete = _livePackComplete(pack);
          final imageUrl = (pack['image_url'] ?? '').toString().trim();
          final previewUrl = _livePackImagePreviewRawUrl(pack).trim();
          final movUrl = _livePackVideoSourceUrl(pack).trim();
          final packName = _livePackName(pack);
          if (!complete || imageUrl.isEmpty || movUrl.isEmpty) {
            failed.add('$packName：套件不完整');
            continue;
          }
          final payload = <String, dynamic>{
            'title': selectedLivePacks.length == 1 ? title : '$title ${i + 1}',
            'description': '',
            'type': 'live_photo',
            'category_id': _publishCategoryId,
            'status': 'published',
            'show_inspiration': _publishShowInspiration,
            'show_moments': _publishShowMoments,
            'original_urls': [imageUrl],
            'thumbnail_url': previewUrl.isNotEmpty ? previewUrl : imageUrl,
            'preview_mov_url': movUrl,
          };
          try {
            final resp = await AdminHttpClient().dio.post('/materials', data: payload);
            final data = resp.data as Map<String, dynamic>;
            if ((data['code'] ?? -1) != 0) {
              throw Exception((data['message'] ?? '发布失败').toString());
            }
            successCount += 1;
          } catch (e) {
            failed.add('$packName：$e');
          }
        }
        if (successCount == 0) {
          throw Exception(failed.isEmpty ? 'Live 发布失败' : failed.first);
        }
      }

      if (failed.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功 $successCount 条，失败 ${failed.length} 条')),
        );
      }
      if (!mounted) return;
      setState(() {
        _publishTitleController.clear();
        _selectedPublishAssetIds = <int>{};
        _selectedPublishLivePackIds = <int>{};
        _publishShowInspiration = false;
        _publishShowMoments = false;
        _showMaterialComposer = false;
      });
      await _loadCurrent();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('发布成功')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发布失败：$e')),
      );
    } finally {
      if (mounted) {
        setState(() => _publishingMaterial = false);
      }
    }
  }

  void _openMaterialComposer() {
    setState(() => _showMaterialComposer = true);
  }

  void _closeMaterialComposer() {
    setState(() {
      _showMaterialComposer = false;
      _publishTitleController.clear();
      _selectedPublishAssetIds = <int>{};
      _selectedPublishLivePackIds = <int>{};
      _publishShowInspiration = false;
      _publishShowMoments = false;
      _publishCategoryId = null;
    });
  }

  Widget _buildPublishSelectedAssetsStrip() {
    final selected = _selectedPublishAssets();
    final selectedLivePacks = _selectedPublishLivePacks();
    final cards = <Widget>[
      ...selected.map(
        (item) {
          final id = _assetId(item);
          final thumb = _assetThumbUrl(item);
          return Container(
            width: 84,
            margin: const EdgeInsets.only(right: 8),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 84,
                    height: 84,
                    child: thumb.isNotEmpty
                        ? Image.network(
                            thumb,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _thumbPlaceholder(
                              _assetIsVideo(item),
                            ),
                          )
                        : _thumbPlaceholder(_assetIsVideo(item)),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: InkWell(
                    onTap: () {
                      setState(() => _selectedPublishAssetIds.remove(id));
                    },
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      ...selectedLivePacks.map(
        (pack) {
          final id = _livePackId(pack);
          final imageUrl = _livePackImageDisplayUrl(pack);
          return Container(
            width: 84,
            margin: const EdgeInsets.only(right: 8),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 84,
                    height: 84,
                    child: imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _thumbPlaceholder(false),
                          )
                        : _thumbPlaceholder(false),
                  ),
                ),
                Positioned(
                  left: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Live',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: InkWell(
                    onTap: () {
                      setState(() => _selectedPublishLivePackIds.remove(id));
                    },
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      GestureDetector(
        onTap: _openPublishAssetSelector,
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(Icons.add, color: AppColors.textHint, size: 28),
        ),
      ),
    ];
    return SizedBox(
      height: 86,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: cards,
      ),
    );
  }

  Widget _buildMaterialsVisual() {
    final secondLevel = _secondLevelCategories();
    return Column(
      children: [
        _toolbarShell(
          children: [
            if (!_showMaterialComposer)
              ElevatedButton.icon(
                style: _compactElevatedStyle(),
                onPressed: _openMaterialComposer,
                icon: const Icon(Icons.add),
                label: const Text('新增素材'),
              ),
            if (_showMaterialComposer) ...[
              ElevatedButton.icon(
                style: _compactElevatedStyle(),
                onPressed: _publishingMaterial ? null : _publishMaterial,
                icon: _publishingMaterial
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.publish_rounded),
                label: Text(_publishingMaterial ? '发布中...' : '发布'),
              ),
              OutlinedButton.icon(
                style: _compactOutlinedStyle(),
                onPressed: _publishingMaterial ? null : _closeMaterialComposer,
                icon: const Icon(Icons.close),
                label: const Text('取消新增'),
              ),
            ],
          ],
        ),
        if (_showMaterialComposer)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 4,
                    color: AppColors.primary,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.edit_note_rounded, color: AppColors.primary, size: 16),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '新增素材',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _publishTitleController,
                          maxLength: 50,
                          decoration: const InputDecoration(
                            labelText: '标题',
                            hintText: '请输入素材标题',
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '素材选择（来自素材库）',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _openPublishAssetSelector,
                              child: const Text('打开选择器'),
                            ),
                          ],
                        ),
                        _buildPublishSelectedAssetsStrip(),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<int>(
                          value: _publishCategoryId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: '二级分类'),
                          hint: const Text('请选择二级分类'),
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
                          onChanged: secondLevel.isEmpty
                              ? null
                              : (value) => setState(() => _publishCategoryId = value),
                        ),
                        if (secondLevel.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              '暂无二级分类，请先到“分类”菜单创建后再发布。',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: _publishShowInspiration,
                          title: const Text('同步投放到找灵感'),
                          onChanged: (v) => setState(() => _publishShowInspiration = v ?? false),
                        ),
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: _publishShowMoments,
                          title: const Text('同步投放到朋友圈'),
                          onChanged: (v) => setState(() => _publishShowMoments = v ?? false),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: _buildVisualCards(_materials, empty: '暂无素材数据', isMaterial: true),
        ),
      ],
    );
  }

  Widget _buildCategoryManager() {
    final createBtn = Align(
      alignment: Alignment.centerLeft,
      child: ElevatedButton.icon(
        style: _compactElevatedStyle(),
        onPressed: _createCategory,
        icon: const Icon(Icons.add),
        label: const Text('新建分类'),
      ),
    );
    if (_categories.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          createBtn,
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.videoBadge.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.folder_open_rounded,
                    color: AppColors.videoBadge,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '暂无分类数据',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '点击上方按钮创建分类',
                  style: TextStyle(fontSize: 12, color: AppColors.textHint),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        createBtn,
        const SizedBox(height: 10),
        ..._categories.map((parent) {
          final parentName = (parent['name'] ?? '未命名一级分类').toString();
          final parentId = (parent['id'] ?? '-').toString();
          final children = List<dynamic>.from(parent['children'] ?? const []);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _sectionBlock(
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  parentName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              if (children.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.videoBadge.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${children.length}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.videoBadge,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => _createCategory(
                                  parentIdPreset: (parent['id'] as num?)?.toInt(),
                                ),
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.add_rounded,
                                    size: 16,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'ID: $parentId',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textHint,
                              ),
                            ),
                          ),
                          if (children.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                '暂无二级分类',
                                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            )
                          else
                            ...children.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final node = (entry.value as Map).cast<String, dynamic>();
                              final name = (node['name'] ?? '未命名二级分类').toString();
                              final id = (node['id'] ?? '-').toString();
                              return Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: AppColors.videoBadge.withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '${idx + 1}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.videoBadge,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textBody,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'ID: $id',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textHint,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildVisualCards(
    List<dynamic> items, {
    required String empty,
    required bool isMaterial,
  }) {
    final widgets = _buildVisualCardItems(items, empty: empty, isMaterial: isMaterial);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: widgets,
    );
  }

  List<Widget> _buildVisualCardItems(
    List<dynamic> items, {
    required String empty,
    required bool isMaterial,
  }) {
    if (items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: _emptyHint(empty),
        ),
      ];
    }
    return items.map((raw) {
      final item = (raw as Map).cast<String, dynamic>();
      final title = (item['title'] ?? item['original_name'] ?? '未命名').toString();
      final type = (item['type'] ?? item['file_type'] ?? '-').toString();
      final thumbUrl = isMaterial ? _materialThumbUrl(item) : _assetThumbUrl(item);
      final isVideo = _isVideoType(type) || _isVideoUrl(thumbUrl);
      final status = (item['status'] ?? '').toString();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _sectionBlock(
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
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
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
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
    }).toList(growable: false);
  }

  int _livePackId(Map<String, dynamic> item) => (item['id'] as num?)?.toInt() ?? 0;

  String _livePackName(Map<String, dynamic> item) =>
      (item['base_name'] ?? '未命名套件').toString();

  String _livePackImageSourceUrl(Map<String, dynamic> item) =>
      (item['image_url'] ?? '').toString();

  String _livePackImagePreviewRawUrl(Map<String, dynamic> item) {
    // 1) 服务端生成的 JPG 预览（最优）
    final preview = (item['image_preview_url'] ?? '').toString().trim();
    if (preview.isNotEmpty) return preview;
    // 2) 直接使用原始 image_url（iOS 原生支持 HEIC 渲染）
    //    不再派生 _preview.jpg —— 生产服务器可能缺少 sips/ffmpeg，文件不存在会 404
    return _livePackImageSourceUrl(item).trim();
  }

  String _livePackImageDisplayUrl(Map<String, dynamic> item) =>
      UrlUtils.absolute(_livePackImagePreviewRawUrl(item));

  String _livePackVideoSourceUrl(Map<String, dynamic> item) =>
      (item['video_url'] ?? '').toString();

  bool _livePackComplete(Map<String, dynamic> item) =>
      (item['status'] ?? '').toString() == 'complete';

  List<Widget> _buildLivePackCardItems(
    List<Map<String, dynamic>> packs, {
    required String empty,
  }) {
    if (packs.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: _emptyHint(empty),
        ),
      ];
    }
    return packs.map((pack) {
      final imageUrl = _livePackImageDisplayUrl(pack);
      final videoUrl = UrlUtils.absolute(_livePackVideoSourceUrl(pack));
      // 优先使用图片缩略图，无图时 fallback 到视频占位
      final thumbUrl = imageUrl.isNotEmpty ? imageUrl : videoUrl;
      final showAsVideo = imageUrl.isEmpty && videoUrl.isNotEmpty;
      final status = (pack['status'] ?? '').toString();
      final missing = (pack['missing'] as List?)?.join(' + ') ?? '';
      final folder = (pack['folder'] ?? '未分类').toString();
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _sectionBlock(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumbView(thumbUrl: thumbUrl, isVideo: showAsVideo),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _livePackName(pack),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _miniTag('ID ${_livePackId(pack)}'),
                        _miniTag('Live'),
                        _miniTag(status == 'complete' ? '完整' : '半成品'),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '文件夹: $folder',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    if (missing.isNotEmpty)
                      Text(
                        '缺失: $missing',
                        style: const TextStyle(fontSize: 12, color: AppColors.warning),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }).toList(growable: false);
  }

  Widget _miniTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, color: AppColors.textBody),
      ),
    );
  }

  Widget _thumbView({required String thumbUrl, required bool isVideo}) {
    return Container(
      width: 86,
      height: 86,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
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
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: Icon(
        isVideo ? Icons.videocam_rounded : Icons.image_rounded,
        color: AppColors.textHint,
      ),
    );
  }

  String _assetThumbUrl(Map<String, dynamic> item) {
    final preview = (item['preview_url'] ?? '').toString();
    if (preview.isNotEmpty) return UrlUtils.absolute(preview);
    final raw = (item['url'] ?? '').toString();
    // 视频没有 preview_url 时无法用 Image 渲染
    if (_isVideoUrl(raw)) return '';
    // iOS 原生支持 HEIC/HEIF，直接使用原始 URL
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: AppColors.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '暂无提问',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '用户的提问将显示在这里',
              style: TextStyle(fontSize: 12, color: AppColors.textHint),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _questions.length,
      itemBuilder: (context, index) {
        final item = (_questions[index] as Map).cast<String, dynamic>();
        final status = (item['status'] ?? '').toString();
        final isReplied = status == 'replied' || status == '已回复';
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _sectionBlock(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.help_outline_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item['question_text'] ?? '').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            'ID: ${item['id'] ?? '-'}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isReplied
                                  ? AppColors.liveBadge.withValues(alpha: 0.12)
                                  : AppColors.warning.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isReplied ? '已回复' : '待回复',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: isReplied
                                    ? AppColors.liveBadge
                                    : AppColors.warning,
                              ),
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => _replyQuestion(item),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                '回复',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
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

  bool get _isImmersive => _index == 1 && _uploadSelectedFolder != null;

  @override
  Widget build(BuildContext context) {
    // 沉浸式：进入分类上传时全屏，隐藏顶部和底部导航
    if (_isImmersive) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _buildUploadFolderDetail(),
      );
    }

    final pages = [
      _buildDashboard(),
      _buildUpload(),
      _buildAssetsVisual(),
      _buildMaterialsVisual(),
      _buildQuestions(),
      _buildCategoryManager(),
    ];

    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primaryBg, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildShellHeader(),
              Expanded(
                child: _glassShell(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: KeyedSubtree(
                            key: ValueKey(_index),
                            child: pages[_index],
                          ),
                        ),
                      ),
                      if (_loading)
                        const Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                    ],
                  ),
                ),
              ),
              _buildFloatingNav(),
            ],
          ),
        ),
      ),
    );
  }
}
