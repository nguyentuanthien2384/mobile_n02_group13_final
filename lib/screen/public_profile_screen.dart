import 'package:flutter/material.dart';
import 'package:todoapp/class/feed_post.dart';
import 'package:todoapp/class/social_user.dart';
import 'package:todoapp/services/social_api_service.dart';
import 'package:todoapp/widget/post_card.dart';
import 'package:todoapp/screen/post_detail_screen.dart';

/// Another user's public profile: header, follow button, their published posts.
class PublicProfileScreen extends StatefulWidget {
  final String uid;
  const PublicProfileScreen({super.key, required this.uid});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  SocialUser? _profile;
  List<FeedPost> _posts = [];
  bool _loading = true;
  bool _busyFollow = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await SocialApiService.profile(widget.uid);
    if (!mounted) return;
    setState(() {
      _profile = result?.profile;
      _posts = result?.posts ?? [];
      _loading = false;
    });
  }

  Future<void> _toggleFollow() async {
    final p = _profile;
    if (p == null || _busyFollow) return;
    final wasFollowing = p.isFollowing;
    setState(() {
      _busyFollow = true;
      p.isFollowing = !wasFollowing; // optimistic
    });
    if (wasFollowing) {
      await SocialApiService.unfollow(p.uid);
    } else {
      await SocialApiService.follow(p.uid);
    }
    await _load(); // re-sync counts + state from server
    if (mounted) setState(() => _busyFollow = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = _profile;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(p?.displayName ?? 'Hồ sơ'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : p == null
              ? const Center(child: Text('Không tải được hồ sơ'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 44,
                              backgroundColor: theme.colorScheme.primaryContainer,
                              backgroundImage:
                                  p.photoURL.isNotEmpty ? NetworkImage(p.photoURL) : null,
                              child: p.photoURL.isEmpty
                                  ? Text(
                                      p.displayName.isNotEmpty
                                          ? p.displayName[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(fontSize: 32),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            Text(p.displayName, style: theme.textTheme.titleLarge),
                            if (p.bio.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(p.bio,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: theme.colorScheme.outline)),
                            ],
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _stat('Bài viết', p.publishedCount),
                                _stat('Người theo dõi', p.followersCount),
                                _stat('Đang theo dõi', p.followingCount),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (!p.isMe)
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.tonal(
                                  onPressed: _busyFollow ? null : _toggleFollow,
                                  style: p.isFollowing
                                      ? null
                                      : FilledButton.styleFrom(
                                          backgroundColor: theme.colorScheme.primary,
                                          foregroundColor: theme.colorScheme.onPrimary,
                                        ),
                                  child: Text(p.isFollowing
                                      ? 'Đang theo dõi'
                                      : (p.followsMe ? 'Theo dõi lại' : 'Theo dõi')),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Divider(),
                      if (_posts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                            child: Text('Chưa có bài viết công khai',
                                style: TextStyle(color: theme.colorScheme.outline)),
                          ),
                        )
                      else
                        ..._posts.map((post) => PostCard(
                              post: post,
                              onTapPost: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => PostDetailScreen(post: post)),
                              ),
                            )),
                    ],
                  ),
                ),
    );
  }

  Widget _stat(String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Text('$value',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
