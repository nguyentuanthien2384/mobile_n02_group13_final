import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/helper/sample_data.dart';
import 'package:todoapp/screen/sticky_editor_screen.dart';
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
                          : MasonryTwoColumn(
                              children: visible
                                  .map((n) => StickyNoteCard(
                                        note: n,
                                        onTap: () => _openEditor(note: n),
                                        onLongPress: () => _confirmDelete(n),
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
                onPressed: () => _openEditor(),
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
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6)],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _search,
                          decoration: const InputDecoration(
                            hintText: 'Search',
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                        ),
                      ),
                      const Icon(Icons.search, color: Colors.black54),
                    ],
                  ),
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
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8)],
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
