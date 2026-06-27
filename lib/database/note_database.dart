import 'package:sqflite/sqflite.dart';
import 'package:todoapp/class/note.dart';

class NoteDatabase {
  static Future<int> insertNote(Database db, Note note) async {
    final id = await db.insert(
      'notes',
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (note.tagIds.isNotEmpty) {
      final batch = db.batch();
      for (final tagId in note.tagIds) {
        batch.insert(
          'note_tags',
          {'noteId': id, 'tagId': tagId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    }
    return id;
  }

  static Future<int> rawInsertNote(Database db, List<Object?>? list) async {
    return await db.rawInsert(
      'insert into notes (title, content, createdAt, editedAt) values(?, ?, ?, ?)',
      list,
    );
  }

  static Note _fromRow(Map<String, Object?> e, Map<int, List<int>> noteTagMap) {
    return Note(
      id: e['id'] as int,
      title: e['title'] as String?,
      content: e['content'] as String?,
      createdAt: DateTime.parse(e['createdAt'] as String),
      editedAt: (e['editedAt'] == null) ? null : DateTime.tryParse(e['editedAt'] as String),
      pinned: ((e['pinned'] ?? 0) as int) == 1,
      remoteId: e['remoteId'] as String?,
      isChecklist: ((e['isChecklist'] ?? 0) as int) == 1,
      reminderAt: (e['reminderAt'] == null) ? null : DateTime.tryParse(e['reminderAt'] as String),
      tagIds: noteTagMap[e['id'] as int] ?? const <int>[],
      color: (e['color'] as int?) ?? 0,
      folderId: e['folderId'] as int?,
      isFavorite: ((e['isFavorite'] ?? 0) as int) == 1,
      noteType: (e['noteType'] as String?) ?? 'note',
      price: e['price'] as String?,
      imagePath: e['imagePath'] as String?,
    );
  }

  static Future<Map<int, List<int>>> _noteTagMap(Database db) async {
    final noteTagRows = await db.query('note_tags');
    final Map<int, List<int>> noteTagMap = {};
    for (final row in noteTagRows) {
      final noteId = row['noteId'] as int;
      final tagId = row['tagId'] as int;
      noteTagMap.putIfAbsent(noteId, () => <int>[]).add(tagId);
    }
    return noteTagMap;
  }

  /// Active notes only (excludes notes moved to trash).
  static Future<List<Note>> getNotes(Database db) async {
    final noteMaps = await db.query('notes', where: 'deleted = 0');
    final noteTagMap = await _noteTagMap(db);
    return noteMaps.map((e) => _fromRow(e, noteTagMap)).toList();
  }

  /// Notes currently in the trash (soft deleted).
  static Future<List<Note>> getDeletedNotes(Database db) async {
    final noteMaps = await db.query('notes', where: 'deleted = 1');
    final noteTagMap = await _noteTagMap(db);
    return noteMaps.map((e) => _fromRow(e, noteTagMap)).toList();
  }

  static Future<Note> getNote(Database db, int id) async {
    final noteInfo = await db.rawQuery('select * from notes where id = ?', [id]);
    final tagRows = await db.query('note_tags', where: 'noteId = ?', whereArgs: [id]);
    final tagIds = tagRows.map((e) => e['tagId'] as int).toList();

    return Note(
      id: noteInfo.first['id'] as int,
      title: noteInfo.first['title'] as String?,
      content: noteInfo.first['content'] as String?,
      createdAt: DateTime.parse(noteInfo.first['createdAt'] as String),
      editedAt: (noteInfo.first['editedAt'] == null) ? null : DateTime.tryParse(noteInfo.first['editedAt'] as String),
      pinned: ((noteInfo.first['pinned'] ?? 0) as int) == 1,
      remoteId: noteInfo.first['remoteId'] as String?,
      isChecklist: ((noteInfo.first['isChecklist'] ?? 0) as int) == 1,
      reminderAt: (noteInfo.first['reminderAt'] == null) ? null : DateTime.tryParse(noteInfo.first['reminderAt'] as String),
      tagIds: tagIds,
      color: (noteInfo.first['color'] as int?) ?? 0,
      folderId: noteInfo.first['folderId'] as int?,
      isFavorite: ((noteInfo.first['isFavorite'] ?? 0) as int) == 1,
      noteType: (noteInfo.first['noteType'] as String?) ?? 'note',
      price: noteInfo.first['price'] as String?,
      imagePath: noteInfo.first['imagePath'] as String?,
    );
  }

  static Future<int> updateNote(Database db, Note note) async {
    return await db.update(
      'notes',
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  static Future<int> deleteNote(Database db, int id) async {
    await db.delete('note_tags', where: 'noteId = ?', whereArgs: [id]);
    return await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  /// Move a note to trash. We also detach the remoteId so the remote/realtime
  /// sync no longer tracks it (the caller deletes the remote doc separately).
  static Future<void> softDelete(Database db, int id) async {
    await db.update(
      'notes',
      {'deleted': 1, 'remoteId': null, 'reminderAt': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Restore a trashed note back to the active list.
  static Future<void> restore(Database db, int id) async {
    await db.update(
      'notes',
      {'deleted': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> setReminder(Database db, int id, DateTime? at) async {
    await db.update(
      'notes',
      {'reminderAt': at?.toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
