import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Portable, account-safe JSON backup for local notes, folders, tags and links.
/// Remote ids and local image paths are intentionally excluded on import, so a
/// backup never becomes a cross-account reference when it is restored.
class BackupService {
  static const int schemaVersion = 1;

  static Future<File> exportJson(Database db) async {
    final notes = await db.query('notes');
    final folders = await db.query('folders');
    final tags = await db.query('tags');
    final noteTags = await db.query('note_tags');
    final payload = <String, Object?>{
      'schemaVersion': schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'notes': notes,
      'folders': folders,
      'tags': tags,
      'noteTags': noteTags,
    };
    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/todoapp-backup-${DateTime.now().millisecondsSinceEpoch}.json',
    );
    return file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  static Future<BackupImportResult> importJson(
    Database db,
    String source,
  ) async {
    final decoded = jsonDecode(source);
    if (decoded is! Map)
      throw const FormatException('Tệp sao lưu không hợp lệ.');
    final notes = _maps(decoded['notes']);
    final folders = _maps(decoded['folders']);
    final tags = _maps(decoded['tags']);
    final noteTags = _maps(decoded['noteTags']);
    if (notes.isEmpty && folders.isEmpty && tags.isEmpty) {
      throw const FormatException('Tệp sao lưu không có dữ liệu.');
    }

    var importedNotes = 0;
    var importedFolders = 0;
    var importedTags = 0;
    await db.transaction((txn) async {
      final folderIds = <int, int>{};
      final tagIds = <int, int>{};
      final noteIds = <int, int>{};

      for (final sourceFolder in folders) {
        final oldId = _int(sourceFolder['id']);
        final newId = await txn.insert('folders', {
          'name': sourceFolder['name']?.toString() ?? 'Thư mục đã nhập',
          'color': _int(sourceFolder['color']) ?? 0xFF2196F3,
          'icon': sourceFolder['icon']?.toString() ?? 'folder',
          'createdAt':
              sourceFolder['createdAt']?.toString() ??
              DateTime.now().toIso8601String(),
          'remoteId': null,
        });
        if (oldId != null) folderIds[oldId] = newId;
        importedFolders++;
      }

      for (final sourceTag in tags) {
        final oldId = _int(sourceTag['id']);
        final newId = await txn.insert('tags', {
          'name': sourceTag['name']?.toString() ?? 'Nhãn đã nhập',
          'createdAt':
              sourceTag['createdAt']?.toString() ??
              DateTime.now().toIso8601String(),
          'remoteId': null,
        });
        if (oldId != null) tagIds[oldId] = newId;
        importedTags++;
      }

      for (final sourceNote in notes) {
        final oldId = _int(sourceNote['id']);
        final note = Map<String, Object?>.from(sourceNote)
          ..remove('id')
          ..['remoteId'] = null
          ..['imagePath'] = null
          ..['folderId'] = folderIds[_int(sourceNote['folderId'])];
        final newId = await txn.insert('notes', note);
        if (oldId != null) noteIds[oldId] = newId;
        importedNotes++;
      }

      for (final sourceLink in noteTags) {
        final noteId = noteIds[_int(sourceLink['noteId'])];
        final tagId = tagIds[_int(sourceLink['tagId'])];
        if (noteId != null && tagId != null) {
          await txn.insert('note_tags', {'noteId': noteId, 'tagId': tagId});
        }
      }
    });
    return BackupImportResult(
      notes: importedNotes,
      folders: importedFolders,
      tags: importedTags,
    );
  }

  static List<Map<String, Object?>> _maps(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => item.map<String, Object?>(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .toList();
  }

  static int? _int(Object? value) => switch (value) {
    int value => value,
    num value => value.toInt(),
    String value => int.tryParse(value),
    _ => null,
  };
}

class BackupImportResult {
  const BackupImportResult({
    required this.notes,
    required this.folders,
    required this.tags,
  });

  final int notes;
  final int folders;
  final int tags;
}
