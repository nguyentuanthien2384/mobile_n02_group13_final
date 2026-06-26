import 'dart:convert';
import 'package:todoapp/class/note.dart';

/// Extracts readable plain text from a note's stored content. Supports the
/// Quill delta format (rich notes) and the checklist format (`[{text,done}]`).
String noteContentToPlainText(Note note) {
  final content = note.content;
  if (content == null || content.isEmpty) return '';
  try {
    final obj = jsonDecode(content);
    if (obj is List) {
      if (obj.isNotEmpty && obj.first is Map &&
          (obj.first as Map).containsKey('text') &&
          (obj.first as Map).containsKey('done')) {
        // Checklist note.
        final buffer = StringBuffer();
        for (final item in obj) {
          if (item is Map) {
            final done = (item['done'] as bool?) ?? false;
            final text = (item['text'] as String?) ?? '';
            buffer.writeln('${done ? '[x]' : '[ ]'} $text');
          }
        }
        return buffer.toString().trimRight();
      }
      // Quill delta as a list of ops.
      final buffer = StringBuffer();
      for (final op in obj) {
        if (op is Map) {
          final ins = op['insert'];
          if (ins is String) buffer.write(ins);
        }
      }
      return buffer.toString().trimRight();
    }
    if (obj is Map && obj['ops'] is List) {
      final buffer = StringBuffer();
      for (final op in (obj['ops'] as List)) {
        if (op is Map) {
          final ins = op['insert'];
          if (ins is String) buffer.write(ins);
        }
      }
      return buffer.toString().trimRight();
    }
  } catch (_) {}
  return content;
}

/// Builds the full text used when sharing/exporting a note.
String noteToShareText(Note note) {
  final title = (note.title ?? '').trim();
  final body = noteContentToPlainText(note);
  if (title.isEmpty) return body;
  if (body.isEmpty) return title;
  return '$title\n\n$body';
}

/// Counts checklist items as (total, done). Returns (0, 0) for non-checklist.
({int total, int done}) checklistProgress(Note note) {
  if (!note.isChecklist) return (total: 0, done: 0);
  final content = note.content;
  if (content == null || content.isEmpty) return (total: 0, done: 0);
  try {
    final obj = jsonDecode(content);
    if (obj is List) {
      int total = 0;
      int done = 0;
      for (final item in obj) {
        if (item is Map && item.containsKey('text')) {
          total++;
          if ((item['done'] as bool?) ?? false) done++;
        }
      }
      return (total: total, done: done);
    }
  } catch (_) {}
  return (total: 0, done: 0);
}
