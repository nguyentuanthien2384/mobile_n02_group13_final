import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/theme/note_palette.dart';

/// Thẻ ghi chú hiển thị theo 3 phong cách: note / reminder / shopping.
class StickyNoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const StickyNoteCard({
    super.key,
    required this.note,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    switch (note.noteType) {
      case 'reminder':
        return _buildReminder(context);
      case 'shopping':
        return _buildShopping(context);
      default:
        return _buildNote(context);
    }
  }

  // ─── My Notes: thẻ màu, có thể có ảnh, tiêu đề đậm + nội dung + ngày ──
  Widget _buildNote(BuildContext context) {
    final bg = NotePalette.resolve(note.color);
    final fg = NotePalette.textOn(bg);
    final body = plainTextFromContent(note.content);
    return _wrap(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note.imagePath != null && note.imagePath!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _image(note.imagePath!),
            ),
          if (note.imagePath != null && note.imagePath!.isNotEmpty)
            const SizedBox(height: 10),
          if ((note.title ?? '').isNotEmpty)
            Text(
              note.title!,
              style: GoogleFonts.poppins(
                color: fg, fontSize: 19, fontWeight: FontWeight.bold, height: 1.15),
            ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              body,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg.withValues(alpha: 0.92), fontSize: 14, height: 1.3),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            formatVietnameseDate(note.editedAt ?? note.createdAt),
            style: TextStyle(color: fg.withValues(alpha: 0.8), fontSize: 11, letterSpacing: 0.3),
          ),
        ],
      ),
    );
  }

  // ─── Reminder: thẻ màu, ghim đỏ ở trên, tiêu đề canh giữa + ngày ──
  Widget _buildReminder(BuildContext context) {
    final bg = NotePalette.resolve(note.color, fallback: const Color(0xFFA7E26C));
    return _wrap(
      color: bg,
      minHeight: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('📌', style: TextStyle(fontSize: 26)),
          const SizedBox(height: 10),
          Text(
            note.title ?? '',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Text(
            formatVietnameseDate(note.editedAt ?? note.createdAt),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ─── Shopping: giấy nhớ cam, tên món + giá + ngày trong khung trắng ──
  Widget _buildShopping(BuildContext context) {
    final bg = NotePalette.resolve(note.color, fallback: NotePalette.shoppingPaper);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(3, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              note.title ?? '',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            if ((note.price ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(note.price!,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Colors.white,
              child: Text(
                formatVietnameseDate(note.editedAt ?? note.createdAt),
                style: const TextStyle(color: Colors.black87, fontSize: 10.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Khung chung cho note/reminder
  Widget _wrap({required Color color, required Widget child, double? minHeight}) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: minHeight != null ? BoxConstraints(minHeight: minHeight) : null,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  Widget _image(String path) {
    if (path.startsWith('http')) {
      return Image.network(path, fit: BoxFit.cover, width: double.infinity, height: 130,
          errorBuilder: (_, __, ___) => const SizedBox.shrink());
    }
    final f = File(path);
    return Image.file(f, fit: BoxFit.cover, width: double.infinity, height: 130,
        errorBuilder: (_, __, ___) => const SizedBox.shrink());
  }
}
