class MaterialListItem {
  final int id;
  final String title;
  final String type;
  final String thumbnailUrl;
  final String watermarkUrl;
  final int width;
  final int height;
  final double duration;
  final double hotScore;
  final int downloadCount;
  int favoriteCount;
  final List<String> tags;
  bool isFavorited;

  MaterialListItem({
    required this.id,
    required this.title,
    required this.type,
    required this.thumbnailUrl,
    this.watermarkUrl = '',
    this.width = 0,
    this.height = 0,
    this.duration = 0,
    this.hotScore = 0,
    this.downloadCount = 0,
    this.favoriteCount = 0,
    this.tags = const [],
    this.isFavorited = false,
  });

  factory MaterialListItem.fromJson(Map<String, dynamic> json) {
    return MaterialListItem(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      type: json['type'] ?? '',
      thumbnailUrl: json['thumbnail_url'] ?? '',
      watermarkUrl: json['watermark_url'] ?? '',
      width: json['width'] ?? 0,
      height: json['height'] ?? 0,
      duration: (json['duration'] ?? 0).toDouble(),
      hotScore: (json['hot_score'] ?? 0).toDouble(),
      downloadCount: json['download_count'] ?? 0,
      favoriteCount: json['favorite_count'] ?? 0,
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      isFavorited: json['is_favorited'] ?? false,
    );
  }

  double get aspectRatio => (width > 0 && height > 0) ? width / height : 0.75;
  bool get isVideo => type == 'video';
  bool get isLivePhoto => type == 'live_photo';

  String get durationText {
    if (duration <= 0) return '';
    final m = duration ~/ 60;
    final s = (duration % 60).toInt();
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class MaterialDetail {
  final int id;
  final String title;
  final String description;
  final String type;
  final int categoryId;
  final String categoryName;
  final List<String> tags;
  final int width;
  final int height;
  final double duration;
  final int fileSize;
  final String fileSizeText;
  final String thumbnailUrl;
  final String watermarkUrl;
  final String previewMovUrl;
  final List<String> originalUrls;
  final double hotScore;
  final int downloadCount;
  final int favoriteCount;
  final int viewCount;
  final bool isFavorited;
  final String createdAt;

  const MaterialDetail({
    required this.id,
    required this.title,
    this.description = '',
    required this.type,
    this.categoryId = 0,
    this.categoryName = '',
    this.tags = const [],
    this.width = 0,
    this.height = 0,
    this.duration = 0,
    this.fileSize = 0,
    this.fileSizeText = '',
    this.thumbnailUrl = '',
    this.watermarkUrl = '',
    this.previewMovUrl = '',
    this.originalUrls = const [],
    this.hotScore = 0,
    this.downloadCount = 0,
    this.favoriteCount = 0,
    this.viewCount = 0,
    this.isFavorited = false,
    this.createdAt = '',
  });

  factory MaterialDetail.fromJson(Map<String, dynamic> json) {
    return MaterialDetail(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      type: json['type'] ?? '',
      categoryId: json['category_id'] ?? 0,
      categoryName: json['category_name'] ?? '',
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      width: json['width'] ?? 0,
      height: json['height'] ?? 0,
      duration: (json['duration'] ?? 0).toDouble(),
      fileSize: json['file_size'] ?? 0,
      fileSizeText: json['file_size_text'] ?? '',
      thumbnailUrl: json['thumbnail_url'] ?? '',
      watermarkUrl: json['watermark_url'] ?? '',
      previewMovUrl: json['preview_mov_url'] ?? '',
      originalUrls: (json['original_urls'] as List?)?.map((e) => e.toString()).toList() ?? [],
      hotScore: (json['hot_score'] ?? 0).toDouble(),
      downloadCount: json['download_count'] ?? 0,
      favoriteCount: json['favorite_count'] ?? 0,
      viewCount: json['view_count'] ?? 0,
      isFavorited: json['is_favorited'] ?? false,
      createdAt: json['created_at'] ?? '',
    );
  }

  bool get isVideo => type == 'video';
  bool get isLivePhoto => type == 'live_photo';
}
