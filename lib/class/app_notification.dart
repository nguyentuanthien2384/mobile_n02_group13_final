/// An in-app notification (like / comment / reply / follow / share / mention).
class AppNotification {
  final String id;
  final String type;
  final String actorUid;
  final String actorName;
  final String actorPhoto;
  final String? noteId;
  final String noteTitle;
  final String? commentId;
  final String text;
  bool read;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.type,
    required this.actorUid,
    required this.actorName,
    this.actorPhoto = '',
    this.noteId,
    this.noteTitle = '',
    this.commentId,
    this.text = '',
    this.read = false,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'info',
      actorUid: json['actorUid'] as String? ?? '',
      actorName: json['actorName'] as String? ?? 'Người dùng',
      actorPhoto: json['actorPhoto'] as String? ?? '',
      noteId: json['noteId'] as String?,
      noteTitle: json['noteTitle'] as String? ?? '',
      commentId: json['commentId'] as String?,
      text: json['text'] as String? ?? '',
      read: json['read'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  /// Human-readable Vietnamese summary for list rendering.
  String get message {
    switch (type) {
      case 'like':
        return '$actorName đã thích ghi chú của bạn';
      case 'comment':
        return '$actorName đã bình luận: "$text"';
      case 'reply':
        return '$actorName đã trả lời bạn: "$text"';
      case 'follow':
        return '$actorName đã bắt đầu theo dõi bạn';
      case 'share':
        return '$actorName đã chia sẻ một ghi chú với bạn';
      case 'mention':
        return '$actorName đã nhắc đến bạn: "$text"';
      default:
        return text;
    }
  }
}
