class FavoriteGroup {
  final int id;
  final String name;
  final bool isDefault;
  final int itemCount;
  final String coverUrl;

  const FavoriteGroup({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.itemCount = 0,
    this.coverUrl = '',
  });

  factory FavoriteGroup.fromJson(Map<String, dynamic> json) {
    return FavoriteGroup(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      isDefault: json['is_default'] ?? false,
      itemCount: json['item_count'] ?? 0,
      coverUrl: json['cover_url'] ?? '',
    );
  }
}
