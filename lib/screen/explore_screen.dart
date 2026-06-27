import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todoapp/class/feed_post.dart';
import 'package:todoapp/class/social_user.dart';
import 'package:todoapp/provider/social_provider.dart';
import 'package:todoapp/services/social_api_service.dart';
import 'package:todoapp/widget/post_card.dart';
import 'package:todoapp/screen/post_detail_screen.dart';
import 'package:todoapp/screen/public_profile_screen.dart';
import 'package:todoapp/screen/notifications_screen.dart';

/// The social hub: following-feed, explore, and trending, with user search.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SocialProvider>().refreshUnread();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _openPost(FeedPost post) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)));
  }

  void _openAuthor(String uid) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: uid)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Khám phá'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Tìm người dùng',
            onPressed: () => showSearch(
              context: context,
              delegate: _UserSearchDelegate(onTapUser: _openAuthor),
            ),
          ),
          Consumer<SocialProvider>(
            builder: (context, social, _) => Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  tooltip: 'Thông báo',
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                    );
                    if (mounted) context.read<SocialProvider>().refreshUnread();
                  },
                ),
                if (social.unread > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        social.unread > 9 ? '9+' : '${social.unread}',
                        style: const TextStyle(color: Colors.white, fontSize: 9),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Đang theo dõi'),
            Tab(text: 'Khám phá'),
            Tab(text: 'Xu hướng'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _PostFeed(
            loader: () => SocialApiService.fetchFeed(),
            emptyText: 'Theo dõi mọi người để xem bài viết của họ ở đây.',
            onTapPost: _openPost,
            onTapAuthor: _openAuthor,
          ),
          _PostFeed(
            loader: () => SocialApiService.fetchExplore(),
            emptyText: 'Chưa có bài viết công khai nào.',
            onTapPost: _openPost,
            onTapAuthor: _openAuthor,
          ),
          _PostFeed(
            loader: () => SocialApiService.fetchTrending(),
            emptyText: 'Chưa có xu hướng nào.',
            onTapPost: _openPost,
            onTapAuthor: _openAuthor,
          ),
        ],
      ),
    );
  }
}

class _PostFeed extends StatefulWidget {
  final Future<List<FeedPost>> Function() loader;
  final String emptyText;
  final void Function(FeedPost) onTapPost;
  final void Function(String uid) onTapAuthor;

  const _PostFeed({
    required this.loader,
    required this.emptyText,
    required this.onTapPost,
    required this.onTapAuthor,
  });

  @override
  State<_PostFeed> createState() => _PostFeedState();
}

class _PostFeedState extends State<_PostFeed>
    with AutomaticKeepAliveClientMixin {
  late Future<List<FeedPost>> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.loader());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<FeedPost>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final posts = snap.data ?? [];
          if (posts.isEmpty) {
            return Stack(
              children: [
                ListView(), // enables pull-to-refresh on empty
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(widget.emptyText,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: posts.length,
            itemBuilder: (context, i) => PostCard(
              post: posts[i],
              onTapPost: () => widget.onTapPost(posts[i]),
              onTapAuthor: () => widget.onTapAuthor(posts[i].authorUid),
            ),
          );
        },
      ),
    );
  }
}

class _UserSearchDelegate extends SearchDelegate<void> {
  final void Function(String uid) onTapUser;
  _UserSearchDelegate({required this.onTapUser});

  @override
  String get searchFieldLabel => 'Tìm theo tên hoặc email';

  @override
  List<Widget> buildActions(BuildContext context) =>
      [if (query.isNotEmpty) IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];

  @override
  Widget buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));

  @override
  Widget buildSuggestions(BuildContext context) => _results();

  @override
  Widget buildResults(BuildContext context) => _results();

  Widget _results() {
    if (query.trim().length < 2) {
      return const Center(child: Text('Nhập ít nhất 2 ký tự để tìm'));
    }
    return FutureBuilder<List<SocialUser>>(
      future: SocialApiService.searchUsers(query.trim()),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final users = snap.data ?? [];
        if (users.isEmpty) return const Center(child: Text('Không tìm thấy người dùng'));
        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, i) {
            final u = users[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: u.photoURL.isNotEmpty ? NetworkImage(u.photoURL) : null,
                child: u.photoURL.isEmpty
                    ? Text(u.displayName.isNotEmpty ? u.displayName[0].toUpperCase() : '?')
                    : null,
              ),
              title: Text(u.displayName),
              subtitle: Text('${u.followersCount} người theo dõi · ${u.publishedCount} bài viết'),
              onTap: () {
                close(context, null);
                onTapUser(u.uid);
              },
            );
          },
        );
      },
    );
  }
}
