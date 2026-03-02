import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/category_model.dart';
import '../models/material_model.dart';
import '../repositories/material_repository.dart';

// ==================== 分类 ====================

final categoriesProvider =
    FutureProvider<List<CategoryModel>>((ref) async {
  final repo = MaterialRepository();
  final list = await repo.getCategories();
  return list;
});

/// 类型筛选：''=全部, 'video', 'image', 'live_photo'
final selectedTypeProvider = StateProvider<String>((ref) => '');
final selectedGenderCategoryProvider = StateProvider<int>((ref) => 0);

// ==================== 排序 ====================

final sortTypeProvider = StateProvider<String>((ref) => 'hot');

// ==================== 素材列表 ====================

class MaterialListState {
  final List<MaterialListItem> items;
  final bool isLoading;
  final bool hasMore;
  final int page;
  final String? error;

  const MaterialListState({
    this.items = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.page = 1,
    this.error,
  });

  MaterialListState copyWith({
    List<MaterialListItem>? items,
    bool? isLoading,
    bool? hasMore,
    int? page,
    String? error,
  }) {
    return MaterialListState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      error: error,
    );
  }
}

class MaterialListNotifier extends StateNotifier<MaterialListState> {
  final MaterialRepository _repo = MaterialRepository();
  String _type = '';
  int _genderCategoryId = 0;
  String _sort = 'hot';

  MaterialListNotifier() : super(const MaterialListState());

  void updateFilters({String? type, int? genderCategoryId, String? sort}) {
    if (type != null) _type = type;
    if (genderCategoryId != null) _genderCategoryId = genderCategoryId;
    if (sort != null) _sort = sort;
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _repo.getMaterials(
        page: 1,
        type: _type.isNotEmpty ? _type : null,
        genderCategoryId: _genderCategoryId > 0 ? _genderCategoryId : null,
        sort: _sort,
      );
      state = MaterialListState(
        items: result.list,
        hasMore: result.hasMore,
        page: 1,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '加载失败');
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    state = state.copyWith(isLoading: true);
    try {
      final nextPage = state.page + 1;
      final result = await _repo.getMaterials(
        page: nextPage,
        type: _type.isNotEmpty ? _type : null,
        genderCategoryId: _genderCategoryId > 0 ? _genderCategoryId : null,
        sort: _sort,
      );
      state = state.copyWith(
        items: [...state.items, ...result.list],
        hasMore: result.hasMore,
        page: nextPage,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }
}

final materialListProvider =
    StateNotifierProvider<MaterialListNotifier, MaterialListState>(
  (ref) {
    final notifier = MaterialListNotifier();
    notifier.refresh();
    return notifier;
  },
);
