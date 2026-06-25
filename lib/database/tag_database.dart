import 'package:sqflite/sqflite.dart';
import 'package:todoapp/class/tag.dart';

class TagDatabase {
  static Future<int> insertTag(Database db, Tag tag) async {
    return await db.insert(
      'tags',
      {
        'name': tag.name,
        'createdAt': tag.createdAt.toIso8601String(),
        'remoteId': tag.remoteId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> updateTag(Database db, Tag tag) async {
    await db.update(
      'tags',
      {
        'name': tag.name,
        'createdAt': tag.createdAt.toIso8601String(),
        'remoteId': tag.remoteId,
      },
      where: 'id = ?',
      whereArgs: [tag.id],
    );
  }

  static Future<void> deleteTag(Database db, int id) async {
    await db.delete('note_tags', where: 'tagId = ?', whereArgs: [id]);
    await db.delete('tags', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<Tag>> getTags(Database db) async {
    final tagRows = await db.query('tags');
    final associationRows = await db.query('note_tags');
    final Map<int, Set<int>> tagToNotes = {};
    for (final row in associationRows) {
      final noteId = row['noteId'] as int;
      final tagId = row['tagId'] as int;
      tagToNotes.putIfAbsent(tagId, () => <int>{}).add(noteId);
    }
    return tagRows
        .map(
          (row) => Tag(
            id: row['id'] as int,
            name: row['name'] as String,
            createdAt: DateTime.tryParse(row['createdAt'] as String? ?? '') ?? DateTime.now(),
            remoteId: row['remoteId'] as String?,
            noteIds: tagToNotes[row['id'] as int] ?? const <int>{},
          ),
        )
        .toList();
  }

  static Future<Set<int>> getNoteTagIds(Database db, int noteId) async {
    final rows = await db.query('note_tags', where: 'noteId = ?', whereArgs: [noteId]);
    return rows.map((e) => e['tagId'] as int).toSet();
  }

  static Future<void> setTagsForNote(Database db, int noteId, Iterable<int> tagIds) async {
    await db.delete('note_tags', where: 'noteId = ?', whereArgs: [noteId]);
    if (tagIds.isEmpty) return;
    final batch = db.batch();
    for (final tagId in tagIds) {
      batch.insert(
        'note_tags',
        {'noteId': noteId, 'tagId': tagId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<void> attachTagToNote(Database db, int noteId, int tagId) async {
    await db.insert(
      'note_tags',
      {'noteId': noteId, 'tagId': tagId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> detachTagFromNote(Database db, int noteId, int tagId) async {
    await db.delete('note_tags', where: 'noteId = ? AND tagId = ?', whereArgs: [noteId, tagId]);
  }

  static Future<int?> getTagIdByRemoteId(Database db, String remoteId) async {
    final rows = await db.query('tags', where: 'remoteId = ?', whereArgs: [remoteId], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['id'] as int;
  }

  static Future<void> setTagRemoteId(Database db, int tagId, String remoteId) async {
    await db.update('tags', {'remoteId': remoteId}, where: 'id = ?', whereArgs: [tagId]);
  }
}
