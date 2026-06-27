/// A published note as it appears in the social feed / explore / profile.
class FeedPost {
  final String id; // == note remoteId
  final String authorUid;
  final String authorName;
  final String authorPhoto;
  final String title;
  final String excerpt;
  final int color;
  final List<String> tags;
  final String coverImage;
  int likesCount;
  int commentsCount;
  final String? publishedAt;
  final String? editedAt;
  bool liked;
  bool bookmarked;

  FeedPost({
    required this.id,
    required this.authorUid,
    required this.authorName,
    this.authorPhoto = '',
    this.title = '',
    this.excerpt = '',
    this.color = 0,
    List<String>? tags,
    this.coverImage = '',
    this.likesCount = 0,
    this.commentsCount = 0,
    this.publishedAt,
    this.editedAt,
    this.liked = false,
    this.bookmarked = false,
  }) : tags = tags ?? const [];

  factory FeedPost.fromJson(Map<String, dynamic> json) {
    return FeedPost(
      id: (json['id'] ?? json['noteId']) as String? ?? '',
      authorUid: json['authorUid'] as String? ?? '',
      authorName: json['authorName'] as String? ?? 'Người dùng',
      authorPhoto: json['authorPhoto'] as String? ?? '',
      title: json['title'] as String? ?? '',
      excerpt: json['excerpt'] as String? ?? '',
      color: json['color'] as int? ?? 0,
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      coverImage: json['coverImage'] as String? ?? '',
      likesCount: json['likesCount'] as int? ?? 0,
      commentsCount: json['commentsCount'] as int? ?? 0,
      publishedAt: json['publishedAt'] as String?,
      editedAt: json['editedAt'] as String?,
      liked: json['liked'] as bool? ?? false,
      bookmarked: json['bookmarked'] as bool? ?? false,
    );
  }
}
