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
    int? genderCategoryId,
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
    if (genderCategoryId != null && genderCategoryId > 0) {
      params['gender_category_id'] = genderCategoryId;
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
  }) async {
    final resp = await _http.get(Api.materialSearch, params: {
      'keyword': keyword,
      'page': page,
      'page_size': pageSize,
    });
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
}
