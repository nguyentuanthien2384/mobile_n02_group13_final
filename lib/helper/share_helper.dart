import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/helper/note_text.dart';
import 'package:todoapp/services/note_api_service.dart';

/// Đánh dấu một ghi chú là "đã chia sẻ" (qua bất kỳ kênh nào: ứng dụng ngoài,
/// liên kết công khai...) để nó hiển thị trong tab "Tôi đã chia sẻ".
Future<void> markNoteShared(BuildContext context, Note note) async {
  if (note.id <= 0 || note.sharedExternally) return;
  try {
    final db = await DatabaseHelper.database();
    final current = await NoteDatabase.getNote(db, note.id);
    if (current.sharedExternally) return;
    final updated = current.copyWith(sharedExternally: true);
    await NoteDatabase.updateNote(db, updated);
    if (context.mounted) {
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

/// Mở khay chia sẻ của hệ thống để gửi ghi chú ra ứng dụng bên ngoài
/// (Zalo, Messenger, Gmail, sao chép...). Gửi kèm ảnh bìa nếu có, và
/// đính kèm liên kết công khai [publicLink] nếu được truyền vào.
Future<void> shareNoteExternally(
  BuildContext context,
  Note note, {
  String? publicLink,
}) async {
  final title = (note.title ?? '').trim();

  final buffer = StringBuffer(noteToShareText(note));
  if (publicLink != null && publicLink.trim().isNotEmpty) {
    if (buffer.isNotEmpty) buffer.write('\n\n');
    buffer.write(publicLink.trim());
  }
  final text = buffer.toString().trim();

  final hasImage = note.imagePath != null &&
      note.imagePath!.isNotEmpty &&
      File(note.imagePath!).existsSync();

  if (text.isEmpty && !hasImage) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ghi chú trống, không có gì để chia sẻ')),
    );
    return;
  }

  final params = ShareParams(
    text: text.isEmpty ? null : text,
    subject: title.isEmpty ? 'Ghi chú' : title,
    files: hasImage ? [XFile(note.imagePath!)] : null,
  );

  try {
    final result = await SharePlus.instance.share(params);
    // Ghi nhận là đã chia sẻ, trừ khi người dùng đóng khay mà không chọn app nào.
    if (result.status != ShareResultStatus.dismissed && context.mounted) {
      await markNoteShared(context, note);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể mở chia sẻ: $e')),
      );
    }
  }
}
