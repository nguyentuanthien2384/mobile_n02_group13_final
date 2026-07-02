import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todoapp/class/app_notification.dart';
import 'package:todoapp/class/feed_post.dart';
import 'package:todoapp/provider/social_provider.dart';
import 'package:todoapp/services/notification_api_service.dart';
import 'package:todoapp/screen/post_detail_screen.dart';
import 'package:todoapp/screen/public_profile_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<AppNotification>> _future;

  @override
  void initState() {
    super.initState();
    _future = NotificationApiService.fetch();
  }

  Future<void> _refresh() async {
    setState(() => _future = NotificationApiService.fetch());
    await _future;
    if (mounted) context.read<SocialProvider>().refreshUnread();
  }

  Future<void> _markAllRead() async {
    await NotificationApiService.markAllRead();
    if (mounted) {
      context.read<SocialProvider>().clear();
      _refresh();
    }
  }

  Future<void> _onTap(AppNotification n) async {
    if (!n.read) {
      await NotificationApiService.markRead(n.id);
      if (mounted) {
        setState(() => n.read = true);
        context.read<SocialProvider>().refreshUnread();
      }
    }
    if (!mounted) return;
    // Navigate based on type.
    if (n.type == 'follow') {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: n.actorUid)));
    } else if (n.noteId != null) {
      // Build a minimal FeedPost to open the post detail.
      final post = FeedPost(
        id: n.noteId!,
        authorUid: '', // current user is the owner for like/comment notifications
        authorName: '',
        title: n.noteTitle,
      );
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)));
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite;
      case 'comment':
        return Icons.mode_comment;
      case 'reply':
        return Icons.reply;
      case 'follow':
        return Icons.person_add;
      case 'share':
        return Icons.share;
      case 'mention':
        return Icons.alternate_email;
      default:
        return Icons.notifications;
    }
  }

  Color _colorFor(String type, ThemeData theme) {
    switch (type) {
      case 'like':
        return Colors.redAccent;
      case 'follow':
        return Colors.blueAccent;
      case 'mention':
        return Colors.orangeAccent;
      default:
        return theme.colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Thông báo'),
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: const Text('Đọc tất cả'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<AppNotification>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return Stack(
                children: [
                  ListView(),
                  Center(
                    child: Text('Chưa có thông báo nào',
                        style: TextStyle(color: theme.colorScheme.outline)),
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final n = items[i];
                return Container(
                  color: n.read ? null : theme.colorScheme.primaryContainer.withValues(alpha: 0.18),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _colorFor(n.type, theme).withValues(alpha: 0.15),
                      child: Icon(_iconFor(n.type), color: _colorFor(n.type, theme), size: 20),
                    ),
                    title: Text(n.message, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_relative(n.createdAt),
                        style: theme.textTheme.bodySmall),
                    trailing: n.read
                        ? null
                        : Container(
                            width: 8, height: 8,
                            decoration: const BoxDecoration(
                                color: Colors.blue, shape: BoxShape.circle),
                          ),
                    onTap: () => _onTap(n),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _relative(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    return '${t.day}/${t.month}/${t.year}';
  }
}
