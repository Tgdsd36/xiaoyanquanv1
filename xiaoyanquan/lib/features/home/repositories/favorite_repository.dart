import '../../../core/constants/api.dart';
import '../../../core/network/http_client.dart';
import '../models/favorite_group_model.dart';

class FavoriteRepository {
  final HttpClient _http = HttpClient();

  /// 获取收藏分组列表
  Future<List<FavoriteGroup>> getGroups() async {
    final resp = await _http.get(Api.favoriteGroups);
    if (resp.isSuccess && resp.data is List) {
      return (resp.data as List)
          .map((e) => FavoriteGroup.fromJson(e))
          .toList();
    }
    return [];
  }

  /// 创建分组，返回新分组（null 表示失败）
  Future<({FavoriteGroup? group, String? error})> createGroup(String name) async {
    try {
      final resp = await _http.post(Api.favoriteGroups, data: {'name': name});
      if (resp.isSuccess && resp.data != null) {
        return (group: FavoriteGroup.fromJson(resp.data), error: null);
      }
      return (group: null, error: resp.message.isNotEmpty ? resp.message : '创建失败');
    } catch (_) {
      return (group: null, error: '创建失败');
    }
  }

  /// 修改分组名称
  Future<String?> updateGroup(int id, String name) async {
    try {
      final resp = await _http.put(Api.favoriteGroupDetail(id), data: {'name': name});
      if (resp.isSuccess) return null;
      return resp.message.isNotEmpty ? resp.message : '修改失败';
    } catch (_) {
      return '修改失败';
    }
  }

  /// 删除分组
  Future<String?> deleteGroup(int id) async {
    try {
      final resp = await _http.delete(Api.favoriteGroupDetail(id));
      if (resp.isSuccess) return null;
      return resp.message.isNotEmpty ? resp.message : '删除失败';
    } catch (_) {
      return '删除失败';
    }
  }
}
