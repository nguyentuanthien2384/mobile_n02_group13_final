import 'package:flutter/material.dart';
import 'package:todoapp/class/comment.dart';
import 'package:todoapp/class/feed_post.dart';
import 'package:todoapp/services/note_api_service.dart';
import 'package:todoapp/screen/public_profile_screen.dart';

/// Full view of a published post with threaded, likeable comments.
class PostDetailScreen extends StatefulWidget {
  final FeedPost post;
  const PostDetailScreen({super.key, required this.post});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _commentCtrl = TextEditingController();
  List<Comment> _comments = [];
  bool _loading = true;
  bool _sending = false;
  Comment? _replyingTo;

  FeedPost get post => widget.post;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    setState(() => _loading = true);
    final list = await NoteApiService.fetchComments(post.id, ownerUid: post.authorUid);
    if (!mounted) return;
    setState(() {
      _comments = list;
      _loading = false;
    });
  }

  // Group replies under their parent for display.
  List<Comment> get _topLevel =>
      _comments.where((c) => c.parentId == null).toList();
  List<Comment> _repliesOf(String id) =>
      _comments.where((c) => c.parentId == id).toList();

  Future<void> _send() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final created = await NoteApiService.addThreadedComment(
      post.id,
      text,
      ownerUid: post.authorUid,
      parentId: _replyingTo?.id,
    );
    if (created != null && mounted) {
      _commentCtrl.clear();
      setState(() {
        _comments.add(created);
        post.commentsCount += 1;
        _replyingTo = null;
      });
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _toggleLike() async {
    final wasLiked = post.liked;
    setState(() {
      post.liked = !wasLiked;
      post.likesCount += wasLiked ? -1 : 1;
    });
    final r = await NoteApiService.toggleLike(post.id, wasLiked);
    if (r != null && mounted) {
      setState(() {
        post.liked = r.liked;
        post.likesCount = r.likesCount;
      });
    }
  }

  Future<void> _toggleCommentLike(Comment c) async {
    setState(() {
      c.liked = !c.liked;
      c.likesCount += c.liked ? 1 : -1;
    });
    final r = await NoteApiService.toggleCommentLike(post.id, c.id, ownerUid: post.authorUid);
    if (r != null && mounted) {
      setState(() {
        c.liked = r.liked;
        c.likesCount = r.likesCount;
      });
    }
  }

  Future<void> _deleteComment(Comment c) async {
    final ok = await NoteApiService.deleteComment(post.id, c.id, ownerUid: post.authorUid);
    if (ok && mounted) {
      setState(() {
        _comments.removeWhere((x) => x.id == c.id || x.parentId == c.id);
        post.commentsCount = _comments.length;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Bài viết'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // ─── Author ───
                      InkWell(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => PublicProfileScreen(uid: post.authorUid)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundImage: post.authorPhoto.isNotEmpty
                                  ? NetworkImage(post.authorPhoto)
                                  : null,
                              child: post.authorPhoto.isEmpty
                                  ? Text(post.authorName.isNotEmpty
                                      ? post.authorName[0].toUpperCase()
                                      : '?')
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Text(post.authorName,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (post.title.isNotEmpty)
                        Text(post.title, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(post.excerpt, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              post.liked ? Icons.favorite : Icons.favorite_border,
                              color: post.liked ? Colors.redAccent : null,
                            ),
                            onPressed: _toggleLike,
                          ),
                          Text('${post.likesCount}'),
                          const SizedBox(width: 16),
                          const Icon(Icons.mode_comment_outlined, size: 20),
                          const SizedBox(width: 4),
                          Text('${post.commentsCount}'),
                        ],
                      ),
                      const Divider(height: 28),
                      Text('Bình luận', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_topLevel.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text('Hãy là người đầu tiên bình luận',
                                style: TextStyle(color: theme.colorScheme.outline)),
                          ),
                        ),
                      ..._topLevel.map(_buildCommentThread),
                    ],
                  ),
          ),
          _buildComposer(theme),
        ],
      ),
    );
  }

  Widget _buildCommentThread(Comment c) {
    final replies = _repliesOf(c.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCommentTile(c),
        if (replies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Column(children: replies.map(_buildCommentTile).toList()),
          ),
      ],
    );
  }

  Widget _buildCommentTile(Comment c) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundImage: c.userPhoto.isNotEmpty ? NetworkImage(c.userPhoto) : null,
            child: c.userPhoto.isEmpty
                ? Text(c.userName.isNotEmpty ? c.userName[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 12))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.userName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(c.text),
                    ],
                  ),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => _toggleCommentLike(c),
                      child: Text(
                        c.likesCount > 0 ? 'Thích (${c.likesCount})' : 'Thích',
                        style: TextStyle(
                          fontSize: 12,
                          color: c.liked ? Colors.redAccent : theme.colorScheme.outline,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _replyingTo = c),
                      child: const Text('Trả lời', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: () => _deleteComment(c),
                      child: Text('Xóa',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer(ThemeData theme) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyingTo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Đang trả lời ${_replyingTo!.userName}',
                          style: theme.textTheme.bodySmall),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _replyingTo = null),
                      child: const Icon(Icons.close, size: 16),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentCtrl,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Viết bình luận...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ),
                IconButton(
                  icon: _sending
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  onPressed: _sending ? null : _send,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
