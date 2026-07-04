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
  // Bố cục lấp đầy chiều cao ô lưới để các thẻ đều nhau; ngày luôn nằm đáy.
  Widget _buildNote(BuildContext context) {
    final bg = NotePalette.resolve(note.color);
    final fg = NotePalette.textOn(bg);
    final body = plainTextFromContent(note.content);
    final hasImage = note.imagePath != null && note.imagePath!.isNotEmpty;
    return _wrap(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _image(note.imagePath!),
            ),
            const SizedBox(height: 8),
          ],
          if ((note.title ?? '').isNotEmpty)
            Text(
              note.title!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                color: fg, fontSize: 15, fontWeight: FontWeight.bold, height: 1.15),
            ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                body,
                overflow: TextOverflow.ellipsis,
                maxLines: 8,
                style: TextStyle(color: fg.withValues(alpha: 0.92), fontSize: 12.5, height: 1.25),
              ),
            ),
          ] else
            const Spacer(),
          const SizedBox(height: 6),
          Text(
            formatVietnameseDate(note.editedAt ?? note.createdAt),
            style: TextStyle(color: fg.withValues(alpha: 0.8), fontSize: 10, letterSpacing: 0.2),
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
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
      return Image.network(path, fit: BoxFit.cover, width: double.infinity, height: 78,
          errorBuilder: (_, __, ___) => const SizedBox.shrink());
    }
    final f = File(path);
    return Image.file(f, fit: BoxFit.cover, width: double.infinity, height: 78,
        errorBuilder: (_, __, ___) => const SizedBox.shrink());
  }
}
