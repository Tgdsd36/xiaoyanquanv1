import 'package:dio/dio.dart';
import '../../../core/constants/api.dart';
import '../../../core/network/http_client.dart';
import '../models/category_model.dart';
import '../models/material_model.dart';

class MaterialRepository {
  final HttpClient _http = HttpClient();

  /// 获取分类列表
  Future<List<CategoryModel>> getCategories() async {
    final resp = await _http.get(Api.categories);
    if (resp.isSuccess && resp.data is List) {
      return (resp.data as List)
          .map((e) => CategoryModel.fromJson(e))
          .toList();
    }
    return [];
  }

  /// 获取素材列表
  Future<({List<MaterialListItem> list, int total, bool hasMore})>
      getMaterials({
    int page = 1,
    int pageSize = 20,
    int? categoryId,
    String? gender,
    String? type,
    String sort = 'hot',
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
      'sort': sort,
    };
    if (categoryId != null && categoryId > 0) {
      params['category_id'] = categoryId;
    }
    if (gender != null && gender.isNotEmpty) {
      params['gender'] = gender;
    }
    if (type != null && type.isNotEmpty) {
      params['type'] = type;
    }

    final resp = await _http.get(Api.materials, params: params);
    if (resp.isSuccess && resp.data != null) {
      final data = resp.data;
      final list = (data['list'] as List?)
              ?.map((e) => MaterialListItem.fromJson(e))
              .toList() ??
          [];
      return (
        list: list,
        total: (data['total'] as int?) ?? 0,
        hasMore: (data['has_more'] as bool?) ?? false,
      );
    }
    return (list: <MaterialListItem>[], total: 0, hasMore: false);
  }

  /// 获取素材详情
  Future<MaterialDetail?> getDetail(int id) async {
    final resp = await _http.get(Api.materialDetail(id));
    if (resp.isSuccess && resp.data != null) {
      return MaterialDetail.fromJson(resp.data);
    }
    return null;
  }

  /// 搜索素材
  Future<({List<MaterialListItem> list, int total, bool hasMore})> search({
    required String keyword,
    int page = 1,
    int pageSize = 20,
    String? type,
    int? categoryId,
  }) async {
    final params = <String, dynamic>{
      'keyword': keyword,
      'page': page,
      'page_size': pageSize,
    };
    if (type != null && type.isNotEmpty) params['type'] = type;
    if (categoryId != null && categoryId > 0) params['category_id'] = categoryId;
    final resp = await _http.get(Api.materialSearch, params: params);
    if (resp.isSuccess && resp.data != null) {
      final data = resp.data;
      final list = (data['list'] as List?)
              ?.map((e) => MaterialListItem.fromJson(e))
              .toList() ??
          [];
      return (
        list: list,
        total: (data['total'] as int?) ?? 0,
        hasMore: (data['has_more'] as bool?) ?? false,
      );
    }
    return (list: <MaterialListItem>[], total: 0, hasMore: false);
  }

  /// 下载素材
  Future<ApiResponse> download(int id) {
    return _http.get(Api.materialDownload(id));
  }

  /// 切换收藏状态
  /// groupId > 0: 收藏到指定分组；groupId == 0: 取消收藏（从所有分组移除）
  /// error 为 null 表示成功，非 null 表示失败原因
  Future<({bool isFavorited, int favoriteCount, String? error})> toggleFavorite({
    required String targetType,
    required int targetId,
    int groupId = 0,
  }) async {
    try {
      final resp = await _http.post(Api.favoriteToggle, data: {
        'target_type': targetType,
        'target_id': targetId,
        'group_id': groupId,
      });
      if (resp.isSuccess && resp.data != null) {
        return (
          isFavorited: resp.data['is_favorited'] as bool? ?? false,
          favoriteCount: resp.data['favorite_count'] as int? ?? 0,
          error: null,
        );
      }
      return (isFavorited: false, favoriteCount: 0, error: resp.message.isNotEmpty ? resp.message : '操作失败');
    } on DioException catch (e) {
      // 403 等业务错误，提取后端返回的 message
      final data = e.response?.data;
      if (data is Map<String, dynamic>) {
        final msg = data['message'] as String? ?? '';
        if (msg.isNotEmpty) {
          return (isFavorited: false, favoriteCount: 0, error: msg);
        }
      }
      return (isFavorited: false, favoriteCount: 0, error: '网络错误，请重试');
    } catch (_) {
      return (isFavorited: false, favoriteCount: 0, error: '操作失败，请重试');
    }
  }
}
