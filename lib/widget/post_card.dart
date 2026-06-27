import 'package:flutter/material.dart';
import 'package:todoapp/class/feed_post.dart';
import 'package:todoapp/services/note_api_service.dart';

/// A social-style card for a published note (feed / explore / trending).
class PostCard extends StatefulWidget {
  final FeedPost post;
  final VoidCallback? onTapAuthor;
  final VoidCallback? onTapPost;

  const PostCard({
    super.key,
    required this.post,
    this.onTapAuthor,
    this.onTapPost,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _busyLike = false;
  bool _busyBookmark = false;

  FeedPost get post => widget.post;

  Future<void> _toggleLike() async {
    if (_busyLike) return;
    setState(() => _busyLike = true);
    // optimistic update
    final wasLiked = post.liked;
    setState(() {
      post.liked = !wasLiked;
      post.likesCount += wasLiked ? -1 : 1;
    });
    final result = await NoteApiService.toggleLike(post.id, wasLiked);
    if (result != null && mounted) {
      setState(() {
        post.liked = result.liked;
        post.likesCount = result.likesCount;
      });
    }
    if (mounted) setState(() => _busyLike = false);
  }

  Future<void> _toggleBookmark() async {
    if (_busyBookmark) return;
    setState(() => _busyBookmark = true);
    final wasSaved = post.bookmarked;
    setState(() => post.bookmarked = !wasSaved);
    final ok = wasSaved
        ? await NoteApiService.removeBookmark(post.id)
        : await NoteApiService.bookmark(post.id);
    if (!ok && mounted) setState(() => post.bookmarked = wasSaved);
    if (mounted) setState(() => _busyBookmark = false);
  }

  String _relativeTime(String? iso) {
    if (iso == null) return '';
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    return '${t.day}/${t.month}/${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withOpacity(0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onTapPost,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Author header ───
              Row(
                children: [
                  GestureDetector(
                    onTap: widget.onTapAuthor,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      backgroundImage: post.authorPhoto.isNotEmpty
                          ? NetworkImage(post.authorPhoto)
                          : null,
                      child: post.authorPhoto.isEmpty
                          ? Text(
                              post.authorName.isNotEmpty
                                  ? post.authorName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(post.authorName,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(_relativeTime(post.publishedAt),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // ─── Content ───
              if (post.title.isNotEmpty)
                Text(post.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
              if (post.excerpt.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(post.excerpt,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
              if (post.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: post.tags
                      .take(4)
                      .map((t) => Chip(
                            label: Text('#$t', style: const TextStyle(fontSize: 11)),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: EdgeInsets.zero,
                          ))
                      .toList(),
                ),
              ],
              const Divider(height: 20),
              // ─── Action bar ───
              Row(
                children: [
                  _action(
                    icon: post.liked ? Icons.favorite : Icons.favorite_border,
                    color: post.liked ? Colors.redAccent : null,
                    label: '${post.likesCount}',
                    onTap: _toggleLike,
                  ),
                  const SizedBox(width: 20),
                  _action(
                    icon: Icons.mode_comment_outlined,
                    label: '${post.commentsCount}',
                    onTap: widget.onTapPost,
                  ),
                  const Spacer(),
                  _action(
                    icon: post.bookmarked ? Icons.bookmark : Icons.bookmark_border,
                    color: post.bookmarked ? theme.colorScheme.primary : null,
                    onTap: _toggleBookmark,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action({
    required IconData icon,
    String? label,
    Color? color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(label),
            ],
          ],
        ),
      ),
    );
  }
}
