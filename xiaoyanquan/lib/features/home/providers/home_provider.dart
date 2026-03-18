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
/// 分类筛选：0=全部
final selectedCategoryProvider = StateProvider<int>((ref) => 0);
/// 性别筛选：''=不限, 'male', 'female'
final selectedGenderProvider = StateProvider<String>((ref) => '');

// ==================== 排序 ====================

final sortTypeProvider = StateProvider<String>((ref) => 'random');

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
  int _categoryId = 0;
  String _gender = '';
  String _sort = 'random';

  MaterialListNotifier() : super(const MaterialListState());

  /// 根据当前小时计算时段: 6-12 morning, 12-18 afternoon, 18-6 evening
  static String _currentTimePeriod() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 12) return 'morning';
    if (hour >= 12 && hour < 18) return 'afternoon';
    return 'evening';
  }

  void updateFilters({String? type, int? categoryId, String? gender, String? sort}) {
    if (type != null) _type = type;
    if (categoryId != null) _categoryId = categoryId;
    if (gender != null) _gender = gender;
    if (sort != null) _sort = sort;
    refresh();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _repo.getMaterials(
        page: 1,
        type: _type.isNotEmpty ? _type : null,
        categoryId: _categoryId > 0 ? _categoryId : null,
        gender: _gender.isNotEmpty ? _gender : null,
        sort: _sort,
        timePeriod: _currentTimePeriod(),
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
        categoryId: _categoryId > 0 ? _categoryId : null,
        gender: _gender.isNotEmpty ? _gender : null,
        sort: _sort,
        timePeriod: _currentTimePeriod(),
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
