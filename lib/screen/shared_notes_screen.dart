import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todoapp/class/folder.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/database/folder_database.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/screen/folder_share_dialog.dart';
import 'package:todoapp/screen/share_dialog.dart';
import 'package:todoapp/services/folder_api_service.dart';
import 'package:todoapp/services/note_api_service.dart';
import 'package:todoapp/sync/note_sync.dart';
import 'package:todoapp/theme/note_palette.dart';
import 'package:todoapp/widget/note_card.dart';

class SharedNotesScreen extends StatefulWidget {
  const SharedNotesScreen({super.key});

  @override
  State<SharedNotesScreen> createState() => _SharedNotesScreenState();
}

class _SharedNotesScreenState extends State<SharedNotesScreen> {
  List<_SharedFolderByMe> _sharedFoldersByMe = [];
  List<Note> _sharedByMe = [];
  List<Note> _sharedWithMe = [];
  bool _loadingMine = true;
  bool _loadingReceived = true;

  @override
  void initState() {
    super.initState();
    _loadSharedByMe();
    _loadSharedWithMe();
  }

  Future<void> _loadSharedByMe() async {
    setState(() => _loadingMine = true);
    try {
      final db = await DatabaseHelper.database();
      final notes = await NoteDatabase.getNotes(db);
      final folders = await FolderDatabase.getFolders(db);
      final mine =
          notes
              .where((n) => n.collaborators.isNotEmpty || n.sharedExternally)
              .toList()
            ..sort(
              (a, b) => (b.editedAt ?? b.createdAt).compareTo(
                a.editedAt ?? a.createdAt,
              ),
            );
      final sharedFolders = <_SharedFolderByMe>[];
      for (final folder in folders.where((f) => f.remoteId != null)) {
        final shares = await FolderApiService.fetchShares(folder.remoteId!);
        if (shares.isNotEmpty) {
          sharedFolders.add(_SharedFolderByMe(folder: folder, shares: shares));
        }
      }
      if (mounted) {
        setState(() {
          _sharedFoldersByMe = sharedFolders;
          _sharedByMe = mine;
          _loadingMine = false;
        });
      }
      // Đối soát: đẩy các email đã ghi nhận cục bộ lên máy chủ để người nhận
      // thực sự xem được (đồng bộ ghi chú trước nếu chưa có remoteId).
      _reconcileShares(mine);
    } catch (_) {
      if (mounted) setState(() => _loadingMine = false);
    }
  }

  /// Gửi lại (idempotent) mọi email cộng tác lên máy chủ cho các ghi chú
  /// đã chia sẻ, đảm bảo người nhận thấy được dù trước đó chỉ lưu cục bộ.
  Future<void> _reconcileShares(List<Note> notes) async {
    for (final n in notes) {
      if (n.collaborators.isEmpty) continue;
      try {
        String? remoteId = n.remoteId;
        if (remoteId == null && n.id > 0) {
          final db = await DatabaseHelper.database();
          final fresh = await NoteDatabase.getNote(db, n.id);
          if (fresh.remoteId == null) {
            await NoteSyncService.pushAdded(db, fresh);
          }
          final after = await NoteDatabase.getNote(db, n.id);
          remoteId = after.remoteId;
        }
        if (remoteId == null) continue;
        for (final email in n.collaborators) {
          await NoteApiService.shareNote(
            remoteId: remoteId,
            email: email,
            permission: 'view',
          );
        }
      } catch (_) {}
    }
  }

  Future<void> _loadSharedWithMe() async {
    setState(() => _loadingReceived = true);
    try {
      final res = await NoteApiService.fetchSharedNotes();
      if (mounted) {
        setState(() {
          _sharedWithMe = res;
          _loadingReceived = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingReceived = false);
    }
  }

  Future<void> _stopSharing(Note note) async {
    final db = await DatabaseHelper.database();
    final updated = note.copyWith(
      collaborators: <String>[],
      sharedExternally: false,
      editedAt: DateTime.now(),
    );
    await NoteDatabase.updateNote(db, updated);
    if (!mounted) return;
    Provider.of<NoteProvider>(context, listen: false).updateNote(updated);
    _loadSharedByMe();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã dừng chia sẻ ghi chú')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Chia sẻ',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: theme.colorScheme.primary,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _loadSharedByMe();
                _loadSharedWithMe();
              },
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Tôi đã chia sẻ'),
              Tab(text: 'Được chia sẻ với tôi'),
            ],
          ),
        ),
        body: TabBarView(children: [_buildSharedByMe(), _buildSharedWithMe()]),
      ),
    );
  }

  Widget _buildSharedByMe() {
    if (_loadingMine) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sharedFoldersByMe.isEmpty && _sharedByMe.isEmpty) {
      return _emptyState(
        icon: Icons.ios_share,
        text:
            'Bạn chưa chia sẻ ghi chú hoặc thư mục nào.\nMọi thứ bạn chia sẻ qua email, liên kết công khai hoặc ứng dụng ngoài sẽ hiện ở đây.',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadSharedByMe,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _sharedFoldersByMe.length + _sharedByMe.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index < _sharedFoldersByMe.length) {
            return _buildSharedFolderByMeCard(_sharedFoldersByMe[index]);
          }
          final note = _sharedByMe[index - _sharedFoldersByMe.length];
          final snippet = plainTextFromContent(note.content);
          return Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          note.title?.isNotEmpty == true
                              ? note.title!
                              : '(Không tiêu đề)',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.person_add_alt, size: 20),
                        tooltip: 'Thêm người nhận',
                        onPressed: () async {
                          await showDialog(
                            context: context,
                            builder: (_) => ShareDialog(
                              noteRemoteId: note.remoteId,
                              note: note,
                            ),
                          );
                          _loadSharedByMe();
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.link_off,
                          size: 20,
                          color: Colors.red,
                        ),
                        tooltip: 'Dừng chia sẻ',
                        onPressed: () => _stopSharing(note),
                      ),
                    ],
                  ),
                  if (snippet.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 8),
                      child: Text(
                        snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ...note.collaborators.map(
                        (e) => Chip(
                          avatar: const Icon(Icons.person, size: 16),
                          label: Text(e, style: const TextStyle(fontSize: 12)),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      if (note.sharedExternally)
                        Chip(
                          avatar: const Icon(Icons.ios_share, size: 16),
                          label: const Text(
                            'Đã chia sẻ ra ứng dụng ngoài',
                            style: TextStyle(fontSize: 12),
                          ),
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSharedFolderByMeCard(_SharedFolderByMe item) {
    final theme = Theme.of(context);
    final folder = item.folder;
    final emails = item.shares
        .map((share) => share['sharedWithEmail'] as String? ?? '')
        .where((email) => email.isNotEmpty)
        .toList();
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Color(folder.color).withValues(alpha: 0.15),
                  child: Icon(Icons.folder_shared, color: Color(folder.color)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.person_add_alt, size: 20),
                  tooltip: 'Thêm người nhận',
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      builder: (_) => FolderShareDialog(folder: folder),
                    );
                    _loadSharedByMe();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.link_off, size: 20, color: Colors.red),
                  tooltip: 'Dừng chia sẻ',
                  onPressed: () => _stopSharingFolder(item),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: emails.isEmpty
                  ? [
                      Chip(
                        avatar: const Icon(Icons.folder_shared, size: 16),
                        label: const Text(
                          'Đã chia sẻ thư mục',
                          style: TextStyle(fontSize: 12),
                        ),
                        backgroundColor: theme.colorScheme.secondaryContainer,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ]
                  : emails
                        .map(
                          (email) => Chip(
                            avatar: const Icon(Icons.person, size: 16),
                            label: Text(
                              email,
                              style: const TextStyle(fontSize: 12),
                            ),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _stopSharingFolder(_SharedFolderByMe item) async {
    final remoteId = item.folder.remoteId;
    if (remoteId == null) return;
    for (final share in item.shares) {
      final targetUid =
          share['sharedWith'] as String? ?? share['id'] as String?;
      if (targetUid == null) continue;
      await FolderApiService.revokeShare(remoteId, targetUid, item.folder.id);
    }
    if (!mounted) return;
    _loadSharedByMe();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã dừng chia sẻ thư mục')));
  }

  Widget _buildSharedWithMe() {
    if (_loadingReceived) {
      return const Center(child: CircularProgressIndicator());
    }
    final folderGroups = _sharedFolderGroups();
    final looseNotes = _sharedWithMe
        .where((note) => !note.sharedViaFolder)
        .toList();
    if (folderGroups.isEmpty && looseNotes.isEmpty) {
      return _emptyState(
        icon: Icons.people_outline,
        text:
            'Chưa có ghi chú hoặc thư mục nào được chia sẻ với bạn.\n(Cần đăng nhập và có người khác chia sẻ tới email của bạn.)',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadSharedWithMe,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: folderGroups.length + looseNotes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index < folderGroups.length) {
            return _buildSharedFolderCard(folderGroups[index]);
          }
          final note = looseNotes[index - folderGroups.length];
          return NoteCard(
            note: note,
            onTap: _openSharedNote,
            delete: (id) async {
              setState(() => _sharedWithMe.removeWhere((e) => e.id == id));
            },
          );
        },
      ),
    );
  }

  List<_SharedFolderGroup> _sharedFolderGroups() {
    final groups = <String, _SharedFolderGroup>{};
    for (final note in _sharedWithMe.where((note) => note.sharedViaFolder)) {
      final key =
          '${note.ownerUid ?? ''}:${note.sharedFolderId ?? note.sharedFolderName ?? note.folderId ?? ''}';
      final group = groups.putIfAbsent(
        key,
        () => _SharedFolderGroup(
          name: note.sharedFolderName?.isNotEmpty == true
              ? note.sharedFolderName!
              : 'Thư mục được chia sẻ',
          ownerName: note.ownerName ?? '',
          notes: [],
        ),
      );
      group.notes.add(note);
    }
    final result = groups.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final group in result) {
      group.notes.sort(
        (a, b) =>
            (b.editedAt ?? b.createdAt).compareTo(a.editedAt ?? a.createdAt),
      );
    }
    return result;
  }

  Widget _buildSharedFolderCard(_SharedFolderGroup group) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(Icons.folder_shared, color: theme.colorScheme.primary),
        ),
        title: Text(
          group.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          [
            '${group.notes.length} ghi chú',
            if (group.ownerName.isNotEmpty) 'từ ${group.ownerName}',
          ].join(' • '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openSharedFolder(group),
      ),
    );
  }

  Future<void> _openSharedFolder(_SharedFolderGroup group) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.35,
          maxChildSize: 0.95,
          builder: (context, controller) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_shared),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    itemCount: group.notes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final note = group.notes[index];
                      return NoteCard(
                        note: note,
                        onTap: _openSharedNote,
                        delete: (id) async {
                          setState(
                            () => _sharedWithMe.removeWhere((e) => e.id == id),
                          );
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    _loadSharedWithMe();
  }

  Future<void> _openSharedNote(Note note) async {
    final route = note.isChecklist ? '/todolist' : '/detail';
    await Navigator.pushNamed(
      context,
      route,
      arguments: {
        'id': note.id,
        'title': note.title,
        'content': note.content,
        'remoteId': note.remoteId,
        'tags': note.tagIds,
        'ownerUid': note.ownerUid,
      },
    );
    _loadSharedWithMe();
  }

  Widget _emptyState({required IconData icon, required String text}) {
    return Stack(
      children: [
        ListView(), // cho phép kéo để làm mới ngay cả khi trống
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 72, color: Colors.grey.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SharedFolderGroup {
  final String name;
  final String ownerName;
  final List<Note> notes;

  _SharedFolderGroup({
    required this.name,
    required this.ownerName,
    required this.notes,
  });
}

class _SharedFolderByMe {
  final Folder folder;
  final List<Map<String, dynamic>> shares;

  _SharedFolderByMe({required this.folder, required this.shares});
}
