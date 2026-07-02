import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/theme/note_palette.dart';

/// Trình soạn ghi chú nền tối, có bảng chọn màu – giống thiết kế mẫu.
/// Dùng chung cho 3 loại: note / reminder / shopping.
class StickyEditorScreen extends StatefulWidget {
  final Note? note; // null = tạo mới
  final String noteType; // 'note' | 'reminder' | 'shopping'

  const StickyEditorScreen({super.key, this.note, this.noteType = 'note'});

  @override
  State<StickyEditorScreen> createState() => _StickyEditorScreenState();
}

class _StickyEditorScreenState extends State<StickyEditorScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _price = TextEditingController();
  late String _type;
  late Color _color;
  String? _imagePath;
  Database? _db;


  @override
  void initState() {
    super.initState();
    _type = widget.note?.noteType ?? widget.noteType;
    _title.text = widget.note?.title ?? '';
    _body.text = plainTextFromContent(widget.note?.content);
    _price.text = widget.note?.price ?? '';
    _imagePath = widget.note?.imagePath;
    final defColor = _type == 'reminder'
        ? const Color(0xFFA7E26C)
        : _type == 'shopping'
            ? NotePalette.shoppingPaper
            : NotePalette.cardColors[1];
    _color = (widget.note != null && widget.note!.color != 0)
        ? Color(widget.note!.color)
        : defColor;
    DatabaseHelper.database().then((d) => setState(() => _db = d));
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (picked != null) setState(() => _imagePath = picked.path);
    } catch (_) {}
  }

  Future<void> _delete() async {
    final db = _db;
    final note = widget.note;
    if (db == null || note == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa ghi chú?'),
        content: Text(
          (note.title ?? '').trim().isEmpty
              ? 'Ghi chú này sẽ được chuyển vào thùng rác.'
              : '"${note.title}" sẽ được chuyển vào thùng rác.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await NoteDatabase.softDelete(db, note.id);
    final notes = await NoteDatabase.getNotes(db);
    if (!mounted) return;
    Provider.of<NoteProvider>(context, listen: false).setNotes(notes);
    Navigator.pop(context, true);
  }

  Future<void> _save() async {
    final db = _db;
    if (db == null) return;
    final title = _title.text.trim();
    if (title.isEmpty && _body.text.trim().isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    final now = DateTime.now();
    if (widget.note == null) {
      final note = Note(
        id: 0,
        title: title,
        content: _body.text.trim(),
        createdAt: now,
        editedAt: now,
        color: _color.toARGB32(),
        noteType: _type,
        price: _type == 'shopping' ? _price.text.trim() : null,
        imagePath: _type == 'note' ? _imagePath : null,
      );
      await NoteDatabase.insertNote(db, note);
    } else {
      final updated = widget.note!.copyWith(
        title: title,
        content: _body.text.trim(),
        editedAt: now,
        color: _color.toARGB32(),
        noteType: _type,
        price: _type == 'shopping' ? _price.text.trim() : null,
        imagePath: _type == 'note' ? _imagePath : null,
      );
      await NoteDatabase.updateNote(db, updated);
    }
    // Đồng bộ lại provider để các màn khác cập nhật.
    final notes = await NoteDatabase.getNotes(db);
    if (mounted) {
      Provider.of<NoteProvider>(context, listen: false).setNotes(notes);
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF6E6E6E),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        actions: [
          if (widget.note != null)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Xóa ghi chú',
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _save,
              style: TextButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              ),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 14),
              Text(
                formatVietnameseDate(widget.note?.createdAt ?? DateTime.now()),
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              // Tiêu đề
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: _title,
                  autofocus: widget.note == null,
                  textInputAction: TextInputAction.next,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    hintText: 'Note Title',
                    hintStyle: TextStyle(color: Colors.white60),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (_type == 'note') _buildNoteBody() else _buildStickyBody(),
              const SizedBox(height: 28),
              Text('Click me',
                  style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              _buildColorPicker(),
              const SizedBox(height: 16),
              if (_type == 'note') _buildAddImage(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // Thân ghi chú thường: vùng nhập + 2 thanh màu dọc 2 bên
  Widget _buildNoteBody() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _verticalBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  if (_imagePath != null && _imagePath!.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(File(_imagePath!), height: 160, width: double.infinity, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _body,
                    autofocus: widget.note != null,
                    maxLines: 10,
                    minLines: 6,
                    style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                    decoration: const InputDecoration(
                      hintText: 'Type your note here...',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _verticalBar(),
        ],
      ),
    );
  }

  Widget _verticalBar() => Container(width: 5, height: 220,
      decoration: BoxDecoration(color: _color, borderRadius: BorderRadius.circular(4)));

  // Thân reminder/shopping: ô giấy nhớ màu (có ghim với reminder), kèm giá nếu shopping
  Widget _buildStickyBody() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 230),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _color,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(2, 5))],
        ),
        child: Column(
          children: [
            if (_type == 'reminder') const Text('📌', style: TextStyle(fontSize: 30)),
            const SizedBox(height: 8),
            if (_type == 'shopping')
              TextField(
                controller: _price,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Giá (vd: 30k)',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
              ),
            TextField(
              controller: _body,
              autofocus: widget.note != null && _type != 'shopping',
              textAlign: TextAlign.center,
              maxLines: 6,
              minLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
              decoration: InputDecoration(
                hintText: _type == 'reminder' ? 'Nội dung nhắc nhở...' : 'Ghi chú mua sắm...',
                hintStyle: const TextStyle(color: Colors.white70),
                border: InputBorder.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorPicker() {
    final colors = _type == 'note'
        ? NotePalette.cardColors
        : const [Color(0xFFF28B82), Color(0xFFFDD663), Color(0xFFA7E26C), Color(0xFF7FE0D4)];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ...colors.map((c) => GestureDetector(
              onTap: () => setState(() => _color = c),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _color.toARGB32() == c.toARGB32() ? Colors.white : Colors.transparent, width: 2),
                ),
                child: _color.toARGB32() == c.toARGB32()
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            )),
        const SizedBox(width: 8),
        Text(
          _type == 'note' ? 'Pick color' : 'Pick your\nsticky color',
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildAddImage() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: TextButton.icon(
          onPressed: _pickImage,
          icon: const Icon(Icons.image_outlined, color: Colors.white),
          label: const Text('Add image', style: TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}
