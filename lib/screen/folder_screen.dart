import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todoapp/class/folder.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/provider/folder_provider.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/database/folder_database.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/widget/note_card.dart';
import 'package:todoapp/sync/note_sync.dart';
import 'package:todoapp/services/folder_api_service.dart';
import 'package:todoapp/screen/sticky_editor_screen.dart';
import 'package:todoapp/theme/note_palette.dart';

class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key});

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  Folder? _selectedFolder;
  List<Note> _notesInFolder = [];
  bool _isLoadingNotes = false;

  @override
  void initState() {
    super.initState();
    _fetchFolders();
  }

  Future<void> _fetchFolders() async {
    final db = await DatabaseHelper.database();
    final localFolders = await FolderDatabase.getFolders(db);
    if (mounted) {
      Provider.of<FolderProvider>(context, listen: false).setFolders(localFolders);
    }

    // Sync folders from API
    try {
      final remoteFolders = await FolderApiService.fetchFolders();
      if (remoteFolders.isNotEmpty) {
        for (final f in remoteFolders) {
          await FolderDatabase.insertFolder(db, f);
        }
        final updatedLocal = await FolderDatabase.getFolders(db);
        if (mounted) {
          Provider.of<FolderProvider>(context, listen: false).setFolders(updatedLocal);
        }
      }
    } catch (_) {}
  }

  Future<void> _loadNotesInFolder(Folder folder) async {
    setState(() {
      _isLoadingNotes = true;
    });
    final db = await DatabaseHelper.database();
    final allNotes = await NoteDatabase.getNotes(db);
    final filtered = allNotes.where((n) => n.folderId == folder.id).toList();
    if (mounted) {
      setState(() {
        _notesInFolder = filtered;
        _isLoadingNotes = false;
      });
    }
  }

  /// Hiển thị menu chọn loại ghi chú (giống mục Ghi chú): thường / nâng cao / checklist.
  void _createNoteInFolder(Folder folder) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: const Text('Ghi chú thường'),
              subtitle: const Text('Ghi chú dạng giấy nhớ, có ảnh'),
              onTap: () {
                Navigator.pop(ctx);
                _createPlainNoteInFolder(folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Ghi chú nâng cao'),
              subtitle: const Text('Định dạng chữ, chèn ảnh, ghi âm giọng nói'),
              onTap: () {
                Navigator.pop(ctx);
                _createViaRouteInFolder('/detail', folder, isChecklist: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('Checklist'),
              subtitle: const Text('Danh sách công việc có ô đánh dấu'),
              onTap: () {
                Navigator.pop(ctx);
                _createViaRouteInFolder('/todolist', folder, isChecklist: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Ghi chú thường: mở trình soạn thảo giấy nhớ (tự lưu, kèm folderId).
  Future<void> _createPlainNoteInFolder(Folder folder) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StickyEditorScreen(folderId: folder.id),
      ),
    );
    if (changed == true && mounted) {
      _loadNotesInFolder(folder);
    }
  }

  /// Ghi chú nâng cao (/detail) hoặc checklist (/todolist) qua route,
  /// đảm bảo ghi chú mới được gán vào thư mục hiện tại.
  Future<void> _createViaRouteInFolder(
    String route,
    Folder folder, {
    required bool isChecklist,
  }) async {
    final result = await Navigator.pushNamed(
      context,
      route,
      arguments: {'title': '', 'content': '', 'folderId': folder.id},
    ) as Map?;
    if (result == null) {
      if (mounted) _loadNotesInFolder(folder);
      return;
    }
    // Màn checklist tự lưu vào DB (đã kèm folderId qua arguments) → chỉ nạp lại.
    if (result['saved'] == true) {
      if (mounted) _loadNotesInFolder(folder);
      return;
    }
    // Màn ghi chú nâng cao trả về nội dung → tạo bản ghi mới kèm folderId.
    final title = (result['title'] as String?) ?? '';
    final content = (result['content'] as String?) ?? '';
    if (title.trim().isEmpty && plainTextFromContent(content).isEmpty) {
      if (mounted) _loadNotesInFolder(folder);
      return;
    }
    final db = await DatabaseHelper.database();
    final now = DateTime.now().toIso8601String();
    final id = await NoteDatabase.rawInsertNote(db, [title, content, now, now]);
    var newNote = await NoteDatabase.getNote(db, id);
    newNote = newNote.copyWith(folderId: folder.id, isChecklist: isChecklist);
    await NoteDatabase.updateNote(db, newNote);
    try {
      await NoteSyncService.pushAdded(db, newNote);
    } catch (_) {}
    if (mounted) _loadNotesInFolder(folder);
  }

  Future<void> _addFolder() async {
    final nameController = TextEditingController();
    int selectedColor = 0xFF2196F3;
    final colors = [
      0xFF2196F3, // Blue
      0xFF4CAF50, // Green
      0xFFF44336, // Red
      0xFFFF9800, // Orange
      0xFF9C27B0, // Purple
      0xFFE91E63, // Pink
    ];

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Thêm thư mục mới', style: TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      hintText: 'Tên thư mục',
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Chọn màu sắc:', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: colors.map((c) {
                      final isSelected = selectedColor == c;
                      return GestureDetector(
                        onTap: () {
                          setDialogState(() {
                            selectedColor = c;
                          });
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: Colors.white, width: 3)
                                : null,
                            boxShadow: isSelected
                                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)]
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) return;
                    Navigator.pop(context);
                    
                    final newFolder = Folder(
                      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                      name: nameController.text.trim(),
                      color: selectedColor,
                      createdAt: DateTime.now(),
                    );

                    final db = await DatabaseHelper.database();
                    await FolderDatabase.insertFolder(db, newFolder);
                    
                    if (mounted) {
                      Provider.of<FolderProvider>(context, listen: false).addFolder(newFolder);
                    }

                    // Push to API
                    try {
                      final createdRemote = await FolderApiService.createFolder(newFolder);
                      if (createdRemote != null) {
                        await FolderDatabase.insertFolder(db, createdRemote);
                        _fetchFolders();
                      }
                    } catch (_) {}
                  },
                  child: const Text('Tạo'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteFolder(Folder folder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa thư mục?'),
        content: const Text('Các ghi chú trong thư mục này sẽ không bị xóa, chỉ được đưa ra ngoài thư mục.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = await DatabaseHelper.database();
      await FolderDatabase.deleteFolder(db, folder.id);
      
      if (mounted) {
        Provider.of<FolderProvider>(context, listen: false).removeFolder(folder.id);
        setState(() {
          if (_selectedFolder?.id == folder.id) {
            _selectedFolder = null;
            _notesInFolder = [];
          }
        });
      }

      if (folder.remoteId != null) {
        try {
          await FolderApiService.deleteFolder(folder.remoteId!);
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folderProvider = Provider.of<FolderProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedFolder != null ? _selectedFolder!.name : 'Thư mục',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: _selectedFolder != null ? Color(_selectedFolder!.color) : theme.colorScheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: _selectedFolder != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _selectedFolder = null;
                    _notesInFolder = [];
                  });
                },
              )
            : null,
        actions: [
          if (_selectedFolder != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteFolder(_selectedFolder!),
            ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _addFolder,
          ),
        ],
      ),
      body: _selectedFolder == null
          ? _buildFolderGrid(folderProvider.folders)
          : _buildFolderNotesView(),
      floatingActionButton: _selectedFolder != null
          ? FloatingActionButton.extended(
              backgroundColor: Color(_selectedFolder!.color),
              foregroundColor: Colors.white,
              onPressed: () => _createNoteInFolder(_selectedFolder!),
              icon: const Icon(Icons.add),
              label: const Text('Thêm ghi chú'),
            )
          : null,
    );
  }

  Widget _buildFolderGrid(List<Folder> folders) {
    if (folders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open_outlined, size: 80, color: Colors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text(
              'Chưa có thư mục nào',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _addFolder,
              icon: const Icon(Icons.add),
              label: const Text('Tạo thư mục đầu tiên'),
            )
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.2,
      ),
      itemCount: folders.length,
      itemBuilder: (context, index) {
        final f = folders[index];
        final folderColor = Color(f.color);
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedFolder = f;
              });
              _loadNotesInFolder(f);
            },
            onLongPress: () => _deleteFolder(f),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: folderColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.folder, color: folderColor, size: 28),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Xem ghi chú',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFolderNotesView() {
    if (_isLoadingNotes) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_notesInFolder.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sticky_note_2_outlined, size: 80, color: Colors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text(
              'Không có ghi chú nào trong thư mục này',
              style: TextStyle(color: Colors.grey, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _notesInFolder.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final note = _notesInFolder[index];
        return NoteCard(
          note: note,
          onTap: (n) async {
            final result = await Navigator.pushNamed(
              context,
              n.isChecklist ? '/todolist' : '/detail',
              arguments: {
                'id': n.id,
                'title': n.title,
                'content': n.content,
                'remoteId': n.remoteId,
                'tags': n.tagIds,
                'folderId': n.folderId,
              },
            ) as Map?;
            // checklist tự lưu (cờ 'saved'); detail trả về map để lưu tại đây.
            if (result != null && result['saved'] != true) {
              final db = await DatabaseHelper.database();
              final edited = n.copyWith(
                title: (result['title'] as String?) ?? n.title,
                content: (result['content'] as String?) ?? n.content,
                editedAt: DateTime.now(),
              );
              await NoteDatabase.updateNote(db, edited);
              try {
                await NoteSyncService.pushUpdated(edited);
              } catch (_) {}
            }
            if (mounted && _selectedFolder != null) {
              _loadNotesInFolder(_selectedFolder!);
            }
          },
          delete: (id) async {
            final db = await DatabaseHelper.database();
            await NoteDatabase.softDelete(db, id);
            await NoteSyncService.pushDeleted(note);
            _loadNotesInFolder(_selectedFolder!);
          },
        );
      },
    );
  }
}
