import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:todoapp/class/folder.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/database/folder_database.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/helper/sample_data.dart';
import 'package:todoapp/screen/sticky_editor_screen.dart';
import 'package:todoapp/screen/share_dialog.dart';
import 'package:todoapp/helper/vietnamese_telex.dart';
import 'package:todoapp/sync/note_sync.dart';
import 'package:todoapp/theme/note_palette.dart';
import 'package:todoapp/widget/masonry_grid.dart';
import 'package:todoapp/widget/sticky_note_card.dart';

/// Màn hình chính kiểu "My Notes" với 3 chế độ: Notes / Reminder / Shopping.
class NotesHomeScreen extends StatefulWidget {
  const NotesHomeScreen({super.key});

  @override
  State<NotesHomeScreen> createState() => _NotesHomeScreenState();
}

class _ModeConfig {
  final String type;
  final String title;
  final Color background;
  final Color fab;
  const _ModeConfig(this.type, this.title, this.background, this.fab);
}

class _NotesHomeScreenState extends State<NotesHomeScreen> {
  static const _modes = [
    _ModeConfig('note', 'MY NOTES', Color(0xFFE9EDCB), Color(0xFF8A8A8A)),
    _ModeConfig('reminder', 'REMINDER', Color(0xFFF3F39E), Color(0xFFE5392F)),
    _ModeConfig('shopping', 'SHOPPING\nLIST', Color(0xFFD9B7B7), Color(0xFFE5392F)),
  ];

  int _mode = 0;
  final _search = TextEditingController();
  String _query = '';
  Database? _db;
  List<Note> _all = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
    _search.addListener(() => setState(() => _query = _search.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final db = await DatabaseHelper.database();
    await SampleData.seedIfEmpty(db); // nạp dữ liệu mẫu lần đầu
    _db = db;
    await _load();
  }

  Future<void> _load() async {
    final db = _db;
    if (db == null) return;
    final notes = await NoteDatabase.getNotes(db);
    if (!mounted) return;
    setState(() {
      _all = notes;
      _loading = false;
    });
    Provider.of<NoteProvider>(context, listen: false).setNotes(notes);
  }

  List<Note> get _visible {
    final type = _modes[_mode].type;
    return _all.where((n) {
      if ((n.noteType.isEmpty ? 'note' : n.noteType) != type) return false;
      if (_query.isEmpty) return true;
      final t = (n.title ?? '').toLowerCase();
      final c = (n.content ?? '').toLowerCase();
      return t.contains(_query) || c.contains(_query);
    }).toList()
      ..sort((a, b) => (b.editedAt ?? b.createdAt).compareTo(a.editedAt ?? a.createdAt));
  }

  Future<void> _openEditor({Note? note}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => StickyEditorScreen(note: note, noteType: _modes[_mode].type),
      ),
    );
    if (changed == true) _load();
  }

  /// Kiểm tra content có phải định dạng Quill (rich text) không.
  bool _isQuillContent(String? content) {
    if (content == null) return false;
    final c = content.trim();
    if (!c.startsWith('[')) return false;
    try {
      final data = jsonDecode(c);
      if (data is List) {
        for (final op in data) {
          if (op is Map && op.containsKey('done')) return false; // checklist
          if (op is Map && op.containsKey('insert')) return true; // quill
        }
      }
    } catch (_) {}
    return false;
  }

  /// Mở ghi chú bằng đúng trình soạn thảo theo loại nội dung.
  Future<void> _openNote(Note note) async {
    if (note.isChecklist) {
      await _openViaRoute('/todolist', note);
    } else if (_isQuillContent(note.content)) {
      await _openViaRoute('/detail', note);
    } else {
      await _openEditor(note: note);
    }
  }

  /// Mở màn hình rich/checklist qua route và lưu lại thay đổi khi quay về.
  Future<void> _openViaRoute(String route, Note note) async {
    final db = _db;
    if (db == null) return;
    final result = await Navigator.pushNamed(
      context,
      route,
      arguments: {
        'title': note.title,
        'content': note.content,
        'id': note.id,
        'remoteId': note.remoteId,
        'tags': note.tagIds,
      },
    ) as Map?;
    if (result == null) return;
    // Màn checklist tự lưu vào DB (trả cờ 'saved'); chỉ cần nạp lại danh sách.
    if (result['saved'] == true) {
      await _load();
      return;
    }
    final edited = note.copyWith(
      title: (result['title'] as String?) ?? note.title,
      content: (result['content'] as String?) ?? note.content,
      editedAt: DateTime.now(),
    );
    await NoteDatabase.updateNote(db, edited);
    try {
      await NoteSyncService.pushUpdated(edited);
    } catch (_) {}
    await _load();
  }

  /// Tạo ghi chú nâng cao (rich text + ghi âm) hoặc checklist qua route.
  Future<void> _createViaRoute(String route, {required bool isChecklist}) async {
    final db = _db;
    if (db == null) return;
    final result = await Navigator.pushNamed(
      context,
      route,
      arguments: {'title': '', 'content': ''},
    ) as Map?;
    if (result == null) return;
    // Màn checklist đã tự lưu vào DB (cờ 'saved'); chỉ cần nạp lại danh sách.
    if (result['saved'] == true) {
      await _load();
      return;
    }
    final title = (result['title'] as String?) ?? '';
    final content = (result['content'] as String?) ?? '';
    if (title.trim().isEmpty && plainTextFromContent(content).isEmpty) return;
    final now = DateTime.now().toIso8601String();
    final id = await NoteDatabase.rawInsertNote(db, [title, content, now, now]);
    var newNote = await NoteDatabase.getNote(db, id);
    if (isChecklist) {
      newNote = newNote.copyWith(isChecklist: true);
      await NoteDatabase.updateNote(db, newNote);
    }
    try {
      await NoteSyncService.pushAdded(db, newNote);
    } catch (_) {}
    await _load();
  }

  void _showCreateMenu(_ModeConfig cfg) {
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
                _openEditor();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Ghi chú nâng cao'),
              subtitle: const Text('Định dạng chữ, chèn ảnh, ghi âm giọng nói'),
              onTap: () {
                Navigator.pop(ctx);
                _createViaRoute('/detail', isChecklist: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('Checklist'),
              subtitle: const Text('Danh sách công việc có ô đánh dấu'),
              onTap: () {
                Navigator.pop(ctx);
                _createViaRoute('/todolist', isChecklist: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMoreMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.checklist_rtl),
              title: const Text('Chọn & xóa nhiều'),
              onTap: () => Navigator.pop(ctx, 'select'),
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Tìm kiếm nâng cao'),
              onTap: () => Navigator.pop(ctx, 'search'),
            ),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('Quản lý nhãn (Tag)'),
              onTap: () => Navigator.pop(ctx, 'tags'),
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: const Text('Thống kê'),
              onTap: () => Navigator.pop(ctx, 'statistics'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Thùng rác'),
              onTap: () => Navigator.pop(ctx, 'trash'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'select':
        await Navigator.pushNamed(context, '/select', arguments: {'db': _db});
        break;
      case 'search':
        await Navigator.pushNamed(context, '/search', arguments: {'db': _db});
        break;
      case 'tags':
        await Navigator.pushNamed(context, '/tags', arguments: {'db': _db});
        break;
      case 'statistics':
        await Navigator.pushNamed(context, '/statistics');
        break;
      case 'trash':
        await Navigator.pushNamed(context, '/trash');
        break;
    }
    if (mounted) _load();
  }

  /// Menu hành động khi giữ lâu một ghi chú.
  Future<void> _showNoteActions(Note note) async {
    final inFolder = note.folderId != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: Text(inFolder ? 'Chuyển sang thư mục khác' : 'Đưa vào thư mục'),
              onTap: () => Navigator.pop(ctx, 'folder'),
            ),
            if (inFolder)
              ListTile(
                leading: const Icon(Icons.folder_off_outlined),
                title: const Text('Bỏ khỏi thư mục'),
                onTap: () => Navigator.pop(ctx, 'unfolder'),
              ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Chia sẻ với người khác'),
              onTap: () => Navigator.pop(ctx, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Xóa ghi chú', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'folder':
        await _moveToFolder(note);
        break;
      case 'unfolder':
        await _removeFromFolder(note);
        break;
      case 'share':
        await showDialog(
          context: context,
          builder: (_) => ShareDialog(noteRemoteId: note.remoteId, note: note),
        );
        await _load();
        break;
      case 'delete':
        await _confirmDelete(note);
        break;
    }
  }

  /// Chọn thư mục và gán ghi chú vào thư mục đó.
  Future<void> _moveToFolder(Note note) async {
    final db = _db;
    if (db == null) return;
    final folders = await FolderDatabase.getFolders(db);
    if (!mounted) return;
    if (folders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa có thư mục nào. Hãy tạo thư mục ở tab "Thư mục" trước!'),
        ),
      );
      return;
    }
    final selected = await showModalBottomSheet<Folder>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Chọn thư mục',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: folders
                    .map((f) => ListTile(
                          leading: Icon(Icons.folder, color: Color(f.color)),
                          title: Text(f.name),
                          trailing: note.folderId == f.id
                              ? const Icon(Icons.check, color: Colors.green)
                              : null,
                          onTap: () => Navigator.pop(ctx, f),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final updated = note.copyWith(folderId: selected.id, editedAt: DateTime.now());
    await NoteDatabase.updateNote(db, updated);
    try {
      await NoteSyncService.pushUpdated(updated);
    } catch (_) {}
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã đưa vào thư mục "${selected.name}"')),
    );
  }

  /// Đưa ghi chú ra khỏi thư mục hiện tại.
  Future<void> _removeFromFolder(Note note) async {
    final db = _db;
    if (db == null) return;
    final updated = note.copyWith(editedAt: DateTime.now());
    updated.folderId = null; // copyWith giữ giá trị cũ nên gán trực tiếp
    await NoteDatabase.updateNote(db, updated);
    try {
      await NoteSyncService.pushUpdated(updated);
    } catch (_) {}
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã bỏ ghi chú khỏi thư mục')),
    );
  }

  Future<void> _confirmDelete(Note note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa ghi chú?'),
        content: Text('"${note.title ?? ''}" sẽ được chuyển vào thùng rác.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok == true && _db != null) {
      await NoteDatabase.softDelete(_db!, note.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _modes[_mode];
    final visible = _visible;
    return Scaffold(
      backgroundColor: cfg.background,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(cfg),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : visible.isEmpty
                          ? _buildEmpty(cfg)
                          : cfg.type == 'note'
                              // My Notes: lưới đều 2 cột, các thẻ cùng kích thước.
                              ? GridView.builder(
                                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 96),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                    childAspectRatio: 1.28,
                                  ),
                                  itemCount: visible.length,
                                  itemBuilder: (_, i) => StickyNoteCard(
                                    note: visible[i],
                                    onTap: () => _openNote(visible[i]),
                                    onLongPress: () => _showNoteActions(visible[i]),
                                  ),
                                )
                              : MasonryTwoColumn(
                                  children: visible
                                      .map((n) => StickyNoteCard(
                                            note: n,
                                            onTap: () => _openNote(n),
                                            onLongPress: () => _showNoteActions(n),
                                          ))
                                      .toList(),
                                ),
                ),
              ],
            ),
            // Nút + nổi
            Positioned(
              right: 20,
              bottom: 86,
              child: FloatingActionButton(
                heroTag: 'notes_fab',
                backgroundColor: cfg.fab,
                onPressed: () => _showCreateMenu(cfg),
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ),
            // Thanh chuyển chế độ
            Positioned(
              left: 0, right: 0, bottom: 14,
              child: Center(child: _buildModeBar()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(_ModeConfig cfg) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cfg.title,
            style: GoogleFonts.cinzel(
              fontSize: 34, fontWeight: FontWeight.w700, color: Colors.black87, height: 1.05),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6)],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _search,
                          inputFormatters: const [VietnameseTelexFormatter()],
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.visiblePassword,
                          decoration: const InputDecoration(
                            hintText: 'Search',
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                        ),
                      ),
                      const _VietnameseToggle(),
                      const SizedBox(width: 4),
                      const Icon(Icons.search, color: Colors.black54),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _openMoreMenu,
                child: Container(
                  width: 48, height: 48,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.more_horiz, color: Colors.black54),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/profile'),
                child: Container(
                  width: 48, height: 48,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.person, color: Colors.black54),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(_ModeConfig cfg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.note_add_outlined, size: 56, color: Colors.black26),
            const SizedBox(height: 12),
            Text(
              _query.isNotEmpty ? 'Không tìm thấy kết quả' : 'Chưa có mục nào. Nhấn + để thêm.',
              style: const TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeButton(0, Icons.menu_book, 'My notes'),
          _modeButton(1, Icons.edit, 'Reminder'),
          _modeButton(2, Icons.format_list_bulleted, 'Shopping list'),
        ],
      ),
    );
  }

  Widget _modeButton(int index, IconData icon, String label) {
    final active = _mode == index;
    return GestureDetector(
      onTap: () => setState(() => _mode = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: active ? 14 : 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEDEDED) : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.black87),
            if (active) ...[
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Nút nhỏ bật/tắt gõ tiếng Việt (Telex), dùng chung cho các ô nhập.
class _VietnameseToggle extends StatelessWidget {
  const _VietnameseToggle();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: vietnameseInputEnabled,
      builder: (context, enabled, _) {
        return GestureDetector(
          onTap: () => vietnameseInputEnabled.value = !enabled,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: enabled ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              enabled ? 'VI' : 'EN',
              style: TextStyle(
                color: enabled ? Colors.white : Colors.black54,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        );
      },
    );
  }
}
