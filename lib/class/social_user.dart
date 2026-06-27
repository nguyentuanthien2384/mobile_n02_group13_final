/// A user as seen in the social layer (profiles, followers, search results).
class SocialUser {
  final String uid;
  final String displayName;
  final String photoURL;
  final String bio;
  final int followersCount;
  final int followingCount;
  final int publishedCount;
  bool isFollowing;
  final bool followsMe;
  final bool isMe;

  SocialUser({
    required this.uid,
    required this.displayName,
    this.photoURL = '',
    this.bio = '',
    this.followersCount = 0,
    this.followingCount = 0,
    this.publishedCount = 0,
    this.isFollowing = false,
    this.followsMe = false,
    this.isMe = false,
  });

  factory SocialUser.fromJson(Map<String, dynamic> json) {
    return SocialUser(
      uid: json['uid'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Người dùng',
      photoURL: json['photoURL'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      followersCount: json['followersCount'] as int? ?? 0,
      followingCount: json['followingCount'] as int? ?? 0,
      publishedCount: json['publishedCount'] as int? ?? 0,
      isFollowing: json['isFollowing'] as bool? ?? false,
      followsMe: json['followsMe'] as bool? ?? false,
      isMe: json['isMe'] as bool? ?? false,
    );
  }
}
