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

  static Future<List<Note>> getNotes(Database db) async {
    final noteMaps = await db.query('notes');
    final noteTagRows = await db.query('note_tags');
    final Map<int, List<int>> noteTagMap = {};
    for (final row in noteTagRows) {
      final noteId = row['noteId'] as int;
      final tagId = row['tagId'] as int;
      noteTagMap.putIfAbsent(noteId, () => <int>[]).add(tagId);
    }

    return noteMaps
        .map(
          (e) => Note(
            id: e['id'] as int,
            title: e['title'] as String?,
            content: e['content'] as String?,
            createdAt: DateTime.parse(e['createdAt'] as String),
            editedAt: (e['editedAt'] == null) ? null : DateTime.tryParse(e['editedAt'] as String),
            pinned: ((e['pinned'] ?? 0) as int) == 1,
            remoteId: e['remoteId'] as String?,
            isChecklist: ((e['isChecklist'] ?? 0) as int) == 1,
            tagIds: noteTagMap[e['id'] as int] ?? const <int>[],
          ),
        )
        .toList();
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
      tagIds: tagIds,
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
}
