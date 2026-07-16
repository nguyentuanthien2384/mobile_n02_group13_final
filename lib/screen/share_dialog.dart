import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/helper/share_helper.dart';
import 'package:todoapp/services/note_api_service.dart';
import 'package:todoapp/sync/note_sync.dart';

class ShareDialog extends StatefulWidget {
  final String? noteRemoteId; // null nếu ghi chú chưa đồng bộ backend
  final Note? note; // note cục bộ (để lưu collaborators + chia sẻ ngoài)
  const ShareDialog({super.key, this.noteRemoteId, this.note});

  @override
  State<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<ShareDialog> {
  final _emailController = TextEditingController();
  String _permission = 'view';
  bool _isSharing = false;
  String? _publicLink;
  bool _isGeneratingLink = false;
  late List<String> _sharedEmails;
  String? _remoteId; // remoteId hiệu lực (có thể vừa đồng bộ xong)

  @override
  void initState() {
    super.initState();
    _sharedEmails = List<String>.from(widget.note?.collaborators ?? const []);
    _remoteId = widget.noteRemoteId;
  }

  /// Đảm bảo ghi chú đã được đồng bộ lên máy chủ (có remoteId). Nếu chưa,
  /// tự đẩy lên backend để lấy remoteId — điều kiện để người nhận xem được.
  Future<String?> _ensureSynced() async {
    if (_remoteId != null) return _remoteId;
    final localNote = widget.note;
    if (localNote == null || localNote.id <= 0) return null;
    try {
      final db = await DatabaseHelper.database();
      final fresh = await NoteDatabase.getNote(db, localNote.id);
      if (fresh.remoteId == null) {
        final uploaded = await NoteSyncService.pushAdded(db, fresh);
        if (!uploaded) return null;
      }
      final after = await NoteDatabase.getNote(db, localNote.id);
      _remoteId = after.remoteId;
    } catch (_) {}
    return _remoteId;
  }

  Future<void> _persistCollaborators() async {
    final note = widget.note;
    if (note == null || note.id <= 0) return;
    try {
      final db = await DatabaseHelper.database();
      final current = await NoteDatabase.getNote(db, note.id);
      final updated = current.copyWith(
        collaborators: _sharedEmails,
        editedAt: DateTime.now(),
      );
      await NoteDatabase.updateNote(db, updated);
      if (mounted) {
        Provider.of<NoteProvider>(context, listen: false).updateNote(updated);
      }
      // Đẩy lên máy chủ để lịch sử chia sẻ tồn tại qua đăng nhập lại / thiết bị khác.
      if (updated.remoteId != null) {
        try {
          await NoteApiService.updateNote(updated);
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _shareWithUser() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    if (!email.contains('@')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Email không hợp lệ')));
      return;
    }

    setState(() => _isSharing = true);

    // Upload the note first. A local email marker is not a successful share.
    final remoteId = await _ensureSynced();
    String message;
    bool delivered = false;
    if (remoteId == null) {
      message =
          'Chưa thể tải ghi chú lên máy chủ nên chưa gửi chia sẻ. '
          'Kiểm tra Cài đặt > Đường dẫn API và kết nối mạng, rồi thử lại.';
    } else {
      try {
        final res = await NoteApiService.shareNote(
          remoteId: remoteId,
          email: email,
          permission: _permission,
        );
        if (res != null) {
          delivered = true;
          if (widget.note != null && !_sharedEmails.contains(email)) {
            _sharedEmails.add(email);
            await _persistCollaborators();
          }
          message =
              'Đã gửi tới $email. Người nhận đăng nhập rồi mở tab "Được chia sẻ với tôi" để xem.';
        } else {
          message =
              'Chưa gửi được: người nhận cần đăng nhập ứng dụng ít nhất một lần '
              '(để hệ thống nhận diện email), hoặc kiểm tra kết nối máy chủ.';
        }
      } catch (_) {
        message = 'Lỗi kết nối máy chủ. Kiểm tra backend có đang chạy không.';
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
      );
      if (delivered) _emailController.clear();
      setState(() => _isSharing = false);
    }
  }

  Future<void> _removeCollaborator(String email) async {
    setState(() => _sharedEmails.remove(email));
    await _persistCollaborators();
  }

  Future<void> _generatePublicLink() async {
    setState(() {
      _isGeneratingLink = true;
    });

    try {
      final remoteId = await _ensureSynced();
      if (remoteId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Chưa đồng bộ được ghi chú lên máy chủ. Kiểm tra đăng nhập và máy chủ.',
              ),
            ),
          );
        }
        return;
      }
      final res = await NoteApiService.sharePublic(
        remoteId: remoteId,
        permission: 'view',
      );

      if (res != null && res['shareUrl'] != null && mounted) {
        setState(() {
          _publicLink = res['shareUrl'];
        });
        if (widget.note != null) await markNoteShared(context, widget.note!);
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingLink = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Chia sẻ ghi chú',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Chia sẻ với người dùng khác qua email:',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'Nhập email người dùng...',
                      hintStyle: const TextStyle(fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _permission,
                  items: const [
                    DropdownMenuItem(value: 'view', child: Text('Xem')),
                    DropdownMenuItem(value: 'edit', child: Text('Sửa')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _permission = val;
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSharing ? null : _shareWithUser,
                icon: _isSharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: const Text('Chia sẻ'),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            if (_sharedEmails.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Đã chia sẻ với:',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _sharedEmails
                    .map(
                      (e) => Chip(
                        label: Text(e, style: const TextStyle(fontSize: 12)),
                        onDeleted: () => _removeCollaborator(e),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                    .toList(),
              ),
            ],
            if (widget.note != null || widget.noteRemoteId != null) ...[
              const Divider(height: 32),
              const Text(
                'Liên kết chia sẻ công khai:',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              ),
              const SizedBox(height: 8),
              if (_publicLink != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _publicLink!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _publicLink!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Đã sao chép liên kết vào bộ nhớ tạm',
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isGeneratingLink ? null : _generatePublicLink,
                    icon: _isGeneratingLink
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link),
                    label: const Text('Tạo liên kết công khai'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
            ],
            if (widget.note != null) ...[
              const Divider(height: 32),
              const Text(
                'Chia sẻ ra ứng dụng khác:',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => shareNoteExternally(
                    context,
                    widget.note!,
                    publicLink: _publicLink,
                  ),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Chia sẻ (Zalo, Messenger, Gmail...)'),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
