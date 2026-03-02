class CategoryModel {
  final int id;
  final int? parentId;
  final String name;
  final String slug;
  final int sortOrder;
  final List<CategoryModel> children;

  const CategoryModel({
    required this.id,
    this.parentId,
    required this.name,
    required this.slug,
    this.sortOrder = 0,
    this.children = const [],
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] ?? 0,
      parentId: json['parent_id'],
      name: json['name'] ?? '',
      slug: json['slug'] ?? '',
      sortOrder: json['sort_order'] ?? 0,
      children: (json['children'] as List?)
              ?.map((e) => CategoryModel.fromJson(e))
              .toList() ??
          [],
    );
  }

  /// 是否为一级分类
  bool get isParent => parentId == null;

  /// 前置"全部"虚拟分类（id=0 表示不筛选分类）
  static const all = CategoryModel(id: 0, name: '全部', slug: 'all');

  /// 性别筛选虚拟分类（id=0 表示不限）
  static const genderAll = CategoryModel(id: 0, name: '不限', slug: 'gender_all');
}
