import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/material_repository.dart';

/// 收藏状态（按素材 ID 共享）
class FavoriteState {
  final bool isFavorited;
  final int favoriteCount;

  const FavoriteState({
    required this.isFavorited,
    required this.favoriteCount,
  });
}

class FavoriteNotifier extends StateNotifier<FavoriteState?> {
  FavoriteNotifier() : super(null);

  final MaterialRepository _repo = MaterialRepository();
  bool _toggling = false;

  /// 初始化（仅当 state 为 null 时设置，避免覆盖已有的更新）
  void init({required bool isFavorited, required int favoriteCount}) {
    state ??= FavoriteState(
      isFavorited: isFavorited,
      favoriteCount: favoriteCount,
    );
  }

  /// 强制设置（API 刷新后使用）
  void set({required bool isFavorited, required int favoriteCount}) {
    state = FavoriteState(
      isFavorited: isFavorited,
      favoriteCount: favoriteCount,
    );
  }

  /// 收藏到指定分组，返回 error message（null 表示成功）
  Future<String?> addToGroup(int materialId, int groupId) async {
    if (_toggling || state == null) return null;
    _toggling = true;
    final old = state!;

    // 乐观更新：如果之前未收藏，count+1 并标记为已收藏
    if (!old.isFavorited) {
      state = FavoriteState(
        isFavorited: true,
        favoriteCount: old.favoriteCount + 1,
      );
    }

    final result = await _repo.toggleFavorite(
      targetType: 'material',
      targetId: materialId,
      groupId: groupId,
    );

    _toggling = false;

    if (result.error == null) {
      state = FavoriteState(
        isFavorited: result.isFavorited,
        favoriteCount: result.favoriteCount,
      );
      return null;
    } else {
      state = old;
      return result.error;
    }
  }

  /// 取消收藏（从所有分组移除），返回 error message（null 表示成功）
  Future<String?> removeFavorite(int materialId) async {
    if (_toggling || state == null) return null;
    _toggling = true;
    final old = state!;

    // 乐观更新
    state = FavoriteState(
      isFavorited: false,
      favoriteCount: old.favoriteCount > 0 ? old.favoriteCount - 1 : 0,
    );

    final result = await _repo.toggleFavorite(
      targetType: 'material',
      targetId: materialId,
      groupId: 0, // 0 = 取消收藏
    );

    _toggling = false;

    if (result.error == null) {
      state = FavoriteState(
        isFavorited: result.isFavorited,
        favoriteCount: result.favoriteCount,
      );
      return null;
    } else {
      state = old;
      return result.error;
    }
  }
}

/// 按素材 ID 共享的收藏状态 Provider
final materialFavoriteProvider =
    StateNotifierProvider.family<FavoriteNotifier, FavoriteState?, int>(
  (ref, materialId) => FavoriteNotifier(),
);
