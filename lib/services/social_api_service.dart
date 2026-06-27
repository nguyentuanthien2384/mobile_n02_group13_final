import 'dart:convert';
import 'package:todoapp/class/feed_post.dart';
import 'package:todoapp/class/social_user.dart';
import 'api_service.dart';

/// Client for the /api/social/* endpoints (the social graph + feeds).
class SocialApiService {
  // ─── Feeds ────────────────────────────────────────────────
  static Future<List<FeedPost>> fetchFeed({int limit = 20}) =>
      _fetchPosts('/social/feed?limit=$limit');

  static Future<List<FeedPost>> fetchExplore({int limit = 20, String? after}) =>
      _fetchPosts('/social/explore?limit=$limit${after != null ? '&after=$after' : ''}');

  static Future<List<FeedPost>> fetchTrending({int limit = 20}) =>
      _fetchPosts('/social/trending?limit=$limit');

  static Future<List<FeedPost>> _fetchPosts(String path) async {
    try {
      final res = await ApiService.get(path);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List list = data['posts'] ?? [];
        return list.map((e) => FeedPost.fromJson(e)).toList();
      }
    } catch (e) {
      print('[SocialApiService] _fetchPosts($path) error: $e');
    }
    return [];
  }

  // ─── Follow graph ─────────────────────────────────────────
  static Future<bool> follow(String uid) async {
    try {
      final res = await ApiService.post('/social/follow/$uid', {});
      if (res.statusCode == 200) return jsonDecode(res.body)['following'] == true;
    } catch (e) {
      print('[SocialApiService] follow error: $e');
    }
    return false;
  }

  static Future<bool> unfollow(String uid) async {
    try {
      final res = await ApiService.delete('/social/follow/$uid');
      if (res.statusCode == 200) return jsonDecode(res.body)['following'] == true;
    } catch (e) {
      print('[SocialApiService] unfollow error: $e');
    }
    return false;
  }

  static Future<List<SocialUser>> following({String? uid}) =>
      _fetchUsers('/social/following${uid != null ? '?uid=$uid' : ''}');

  static Future<List<SocialUser>> followers({String? uid}) =>
      _fetchUsers('/social/followers${uid != null ? '?uid=$uid' : ''}');

  static Future<List<SocialUser>> searchUsers(String query) =>
      _fetchUsers('/social/users/search?q=${Uri.encodeQueryComponent(query)}');

  static Future<List<SocialUser>> suggestions({int limit = 10}) =>
      _fetchUsers('/social/suggestions?limit=$limit');

  static Future<List<SocialUser>> _fetchUsers(String path) async {
    try {
      final res = await ApiService.get(path);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List list = data['users'] ?? [];
        return list.map((e) => SocialUser.fromJson(e)).toList();
      }
    } catch (e) {
      print('[SocialApiService] _fetchUsers($path) error: $e');
    }
    return [];
  }

  // ─── Public profile ───────────────────────────────────────
  static Future<({SocialUser profile, List<FeedPost> posts})?> profile(String uid) async {
    try {
      final res = await ApiService.get('/social/profile/$uid');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final profile = SocialUser.fromJson(data['profile']);
        final posts = ((data['posts'] as List?) ?? [])
            .map((e) => FeedPost.fromJson(e))
            .toList();
        return (profile: profile, posts: posts);
      }
    } catch (e) {
      print('[SocialApiService] profile error: $e');
    }
    return null;
  }
}
