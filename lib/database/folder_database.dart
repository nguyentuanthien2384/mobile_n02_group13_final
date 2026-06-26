import 'package:sqflite/sqflite.dart';
import 'package:todoapp/class/folder.dart';

class FolderDatabase {
  static Future<int> insertFolder(Database db, Folder folder) async {
    return await db.insert(
      'folders',
      folder.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Folder>> getFolders(Database db) async {
    final maps = await db.query('folders', orderBy: 'createdAt DESC');
    return maps.map((e) => Folder.fromMap(e)).toList();
  }

  static Future<Folder?> getFolder(Database db, int id) async {
    final maps = await db.query('folders', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Folder.fromMap(maps.first);
  }

  static Future<int> updateFolder(Database db, Folder folder) async {
    return await db.update(
      'folders',
      folder.toMap(),
      where: 'id = ?',
      whereArgs: [folder.id],
    );
  }

  static Future<int> deleteFolder(Database db, int id) async {
    // Detach folder from all notes
    await db.update(
      'notes',
      {'folderId': null},
      where: 'folderId = ?',
      whereArgs: [id],
    );
    return await db.delete('folders', where: 'id = ?', whereArgs: [id]);
  }
}
