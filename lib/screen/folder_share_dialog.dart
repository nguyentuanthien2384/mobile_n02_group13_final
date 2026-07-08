import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todoapp/class/folder.dart';
import 'package:todoapp/database/folder_database.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/provider/folder_provider.dart';
import 'package:todoapp/services/folder_api_service.dart';
import 'package:todoapp/sync/note_sync.dart';

class FolderShareDialog extends StatefulWidget {
  final Folder folder;

  const FolderShareDialog({super.key, required this.folder});

  @override
  State<FolderShareDialog> createState() => _FolderShareDialogState();
}

class _FolderShareDialogState extends State<FolderShareDialog> {
  final _emailController = TextEditingController();
  String _permission = 'view';
  bool _isSharing = false;
  bool _loadingShares = false;
  late Folder _folder;
  List<Map<String, dynamic>> _shares = [];

  @override
  void initState() {
    super.initState();
    _folder = widget.folder;
    _loadShares();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadShares() async {
    final remoteId = _folder.remoteId;
    if (remoteId == null) return;
    setState(() => _loadingShares = true);
    final shares = await FolderApiService.fetchShares(remoteId);
    if (mounted) {
      setState(() {
        _shares = shares;
        _loadingShares = false;
      });
    }
  }

  Future<String?> _ensureFolderSynced() async {
    if (_folder.remoteId != null) return _folder.remoteId;
    try {
      final db = await DatabaseHelper.database();
      final created = await FolderApiService.createFolder(_folder);
      if (created == null || created.remoteId == null) return null;
      await FolderDatabase.insertFolder(db, created);
      if (mounted) {
        Provider.of<FolderProvider>(
          context,
          listen: false,
        ).updateFolder(created);
      }
      _folder = created;
      return created.remoteId;
    } catch (_) {
      return null;
    }
  }

  Future<int> _ensureNotesSynced() async {
    final db = await DatabaseHelper.database();
    final notes = await NoteDatabase.getNotes(db);
    final notesInFolder = notes
        .where((note) => note.folderId == _folder.id)
        .toList();
    for (final note in notesInFolder) {
      if (note.remoteId == null) {
        await NoteSyncService.pushAdded(db, note);
      }
    }
    return notesInFolder.length;
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
    String message;
    bool delivered = false;

    final remoteId = await _ensureFolderSynced();
    if (remoteId == null) {
      message =
          'Chưa đồng bộ được thư mục lên máy chủ. Kiểm tra đăng nhập và backend.';
    } else {
      final notesCount = await _ensureNotesSynced();
      final res = await FolderApiService.shareFolder(
        remoteId: remoteId,
        localFolderId: _folder.id,
        email: email,
        permission: _permission,
      );
      if (res != null) {
        delivered = true;
        final sharedNotesCount = res['sharedNotesCount'] as int? ?? notesCount;
        message =
            'Đã chia sẻ thư mục với $email ($sharedNotesCount ghi chú). Người nhận mở tab "Được chia sẻ với tôi" để xem.';
      } else {
        message =
            'Chưa gửi được: người nhận cần đăng nhập ứng dụng ít nhất một lần hoặc kiểm tra kết nối máy chủ.';
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
    if (delivered) {
      _emailController.clear();
      await _loadShares();
    }
    if (mounted) setState(() => _isSharing = false);
  }

  Future<void> _removeShare(Map<String, dynamic> share) async {
    final targetUid = share['sharedWith'] as String? ?? share['id'] as String?;
    final remoteId = _folder.remoteId;
    if (targetUid == null || remoteId == null) return;
    final removed = await FolderApiService.revokeShare(
      remoteId,
      targetUid,
      _folder.id,
    );
    if (!mounted) return;
    if (removed) {
      setState(
        () => _shares.removeWhere(
          (item) => (item['sharedWith'] ?? item['id']) == targetUid,
        ),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã hủy chia sẻ thư mục')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_shared_outlined, color: Color(_folder.color)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Chia sẻ thư mục',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Text(
              _folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
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
                  onChanged: (value) {
                    if (value != null) setState(() => _permission = value);
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
                label: const Text('Chia sẻ thư mục'),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            if (_loadingShares) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ] else if (_shares.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Đã chia sẻ với:',
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _shares.map((share) {
                  final email = share['sharedWithEmail'] as String? ?? '';
                  return Chip(
                    label: Text(email, style: const TextStyle(fontSize: 12)),
                    onDeleted: () => _removeShare(share),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
