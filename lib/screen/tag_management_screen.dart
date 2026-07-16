import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:todoapp/class/tag.dart';
import 'package:todoapp/database/tag_database.dart';
import 'package:todoapp/provider/tag_provider.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/sync/tag_sync.dart';
import 'package:todoapp/sync/note_sync.dart';

class TagManagementScreen extends StatefulWidget {
  const TagManagementScreen({super.key});

  @override
  State<TagManagementScreen> createState() => _TagManagementScreenState();
}

class _TagManagementScreenState extends State<TagManagementScreen> {
  Database? _db;
  bool _loaded = false;
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _db = args != null ? args['db'] as Database? : null;
    if (!_loaded && _db != null) {
      _loaded = true;
      _loadTags();
    }
  }

  Future<void> _loadTags() async {
    final db = _db;
    if (db == null) return;
    final tags = await TagDatabase.getTags(db);
    if (!mounted) return;
    Provider.of<TagProvider>(context, listen: false).setTags(tags);
  }

  bool _hasDuplicateName(String name, {int? exceptId}) {
    final normalized = name.trim().toLowerCase();
    return Provider.of<TagProvider>(context, listen: false).tags.any(
      (tag) =>
          tag.id != exceptId && tag.name.trim().toLowerCase() == normalized,
    );
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : null,
      ),
    );
  }

  Future<void> _createTag() async {
    final db = _db;
    if (db == null) return;
    final tagProvider = Provider.of<TagProvider>(context, listen: false);
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tạo nhãn'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'Tên nhãn, ví dụ: Học tập',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tạo'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) return;
    if (_hasDuplicateName(name)) {
      _showMessage('Nhãn này đã tồn tại.', error: true);
      return;
    }
    final createdAt = DateTime.now();
    final tagId = await TagDatabase.insertTag(
      db,
      Tag(id: 0, name: name, createdAt: createdAt),
    );
    final tag = Tag(id: tagId, name: name, createdAt: createdAt);
    tagProvider.addTag(tag);
    try {
      final remoteId = await TagSyncService.pushAdded(db, tag);
      if (remoteId != null && mounted) {
        tagProvider.setTagRemoteId(tag.id, remoteId);
      }
    } catch (_) {
      // Nhãn vẫn được lưu trên máy và sẽ được đồng bộ lại sau.
    }
    _showMessage('Đã tạo nhãn “$name”.');
  }

  Future<void> _renameTag(Tag tag) async {
    final db = _db;
    if (db == null) return;
    final controller = TextEditingController(text: tag.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên nhãn'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'Tên nhãn'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final newName = controller.text.trim();
    if (newName.isEmpty || newName == tag.name) return;
    if (_hasDuplicateName(newName, exceptId: tag.id)) {
      _showMessage('Nhãn này đã tồn tại.', error: true);
      return;
    }
    final updated = tag.copyWith(name: newName);
    await TagDatabase.updateTag(db, updated);
    if (!mounted) return;
    Provider.of<TagProvider>(context, listen: false).updateTag(updated);
    try {
      await TagSyncService.pushUpdated(updated);
    } catch (_) {
      // Cập nhật cục bộ vẫn hợp lệ khi đang ngoại tuyến.
    }
    _showMessage('Đã đổi tên nhãn.');
  }

  Future<void> _deleteTag(Tag tag) async {
    final db = _db;
    if (db == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa nhãn?'),
        content: Text(
          'Nhãn “${tag.name}” sẽ được gỡ khỏi các ghi chú. Các ghi chú không bị xóa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    final noteProvider = Provider.of<NoteProvider>(context, listen: false);
    final tagProvider = Provider.of<TagProvider>(context, listen: false);
    final affectedNoteIds = List<int>.from(tag.noteIds);

    await TagDatabase.deleteTag(db, tag.id);
    tagProvider.removeTag(tag.id);
    for (final noteId in affectedNoteIds) {
      noteProvider.removeTagFromNote(noteId, tag.id);
      try {
        await NoteSyncService.pushNoteTags(db, noteId);
      } catch (_) {}
    }
    try {
      await TagSyncService.pushDeleted(tag);
    } catch (_) {}
    _showMessage('Đã xóa nhãn “${tag.name}”.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final db = _db;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Quản lý nhãn',
          style: TextStyle(color: Colors.white),
        ),
      ),
      floatingActionButton: db == null
          ? null
          : FloatingActionButton(
              onPressed: _createTag,
              child: const Icon(Icons.add),
            ),
      body: Consumer<TagProvider>(
        builder: (context, tagProvider, _) {
          final tags =
              tagProvider.tags
                  .where((tag) => tag.name.toLowerCase().contains(_query))
                  .toList()
                ..sort((a, b) => a.name.compareTo(b.name));
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            // Giữ ô tìm kiếm trên màn hình kể cả khi chưa có kết quả, để
            // người dùng có thể tiếp tục nhập hoặc xóa từ khóa.
            itemCount: tags.isEmpty ? 2 : tags.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                return TextField(
                  controller: _searchController,
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Tìm nhãn',
                    border: const OutlineInputBorder(),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Xóa từ khóa',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                );
              }
              if (tags.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 80),
                  child: Text(
                    db == null
                        ? 'Không thể mở cơ sở dữ liệu.'
                        : _query.isEmpty
                        ? 'Chưa có nhãn nào. Nhấn + để tạo nhãn đầu tiên.'
                        : 'Không tìm thấy nhãn phù hợp.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                );
              }
              final tag = tags[index - 1];
              final noteCount = tag.noteIds.length;
              return Material(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  title: Text(
                    tag.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text('$noteCount ghi chú'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Đổi tên',
                        onPressed: () => _renameTag(tag),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        tooltip: 'Xóa',
                        onPressed: () => _deleteTag(tag),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
