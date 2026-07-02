import 'package:flutter/widgets.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';

class DatabaseHelper {
  DatabaseHelper();

  static String? _currentUserId;
  static Database? _cachedDatabase;

  static Future<Database> database() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.uid;
    
    // If user changed, close old database and clear cache
    if (_currentUserId != null && _currentUserId != userId) {
      if (_cachedDatabase != null && _cachedDatabase!.isOpen) {
        await _cachedDatabase!.close();
      }
      _cachedDatabase = null;
    }
    
    _currentUserId = userId;
    
    // Return cached database if same user
    if (_cachedDatabase != null && _cachedDatabase!.isOpen) {
      return _cachedDatabase!;
    }
    
    // Create database file based on user ID or use default if no user
    final dbFileName = userId != null ? 'notes_$userId.db' : 'notes_guest.db';
    
    final database = await openDatabase(
      join(await getDatabasesPath(), dbFileName),
      onCreate: (db, version) async {
        await db.execute(
          'create table if not exists notes(id integer primary key autoincrement, title text, content text, createdAt text not null, editedAt text, pinned integer not null default 0, remoteId text, isChecklist integer not null default 0, deleted integer not null default 0, reminderAt text, color integer not null default 0, folderId integer, isFavorite integer not null default 0, noteType text not null default \'note\', price text, imagePath text)'
        );
        await db.execute(
          'create table if not exists tags(id integer primary key autoincrement, name text not null, createdAt text not null, remoteId text)'
        );
        await db.execute(
          'create table if not exists note_tags(noteId integer not null, tagId integer not null, unique(noteId, tagId) on conflict ignore)'
        );
        await db.execute(
          'create table if not exists folders(id integer primary key autoincrement, name text not null, color integer not null, icon text not null, createdAt text not null, remoteId text)'
        );
        await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_remoteId ON tags(remoteId)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_note_tags_noteId ON note_tags(noteId)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_note_tags_tagId ON note_tags(tagId)');
        await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_folders_remoteId ON folders(remoteId)');
      },
      onOpen: (db) async {
        // Migration: if old table `dogs` exists and `notes` doesn't, rename it
        final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
        final hasDogs = tables.any((t) => (t['name'] as String?) == 'dogs');
        final hasNotes = tables.any((t) => (t['name'] as String?) == 'notes');
        if (hasDogs && !hasNotes) {
          await db.execute('ALTER TABLE dogs RENAME TO notes');
        }
        // Read existing columns once to avoid exception-driven migrations every launch.
        final noteColumns = await db.rawQuery('PRAGMA table_info(notes)');
        final existing = {
          for (final col in noteColumns) (col['name'] as String?) ?? '',
        };
        Future<void> addColumnIfMissing(String name, String sqlTypeAndDefault) async {
          if (existing.contains(name)) return;
          await db.execute('ALTER TABLE notes ADD COLUMN $name $sqlTypeAndDefault');
          existing.add(name);
        }

        await addColumnIfMissing('pinned', 'integer not null default 0');
        await addColumnIfMissing('remoteId', 'text');
        await addColumnIfMissing('isChecklist', 'integer not null default 0');
        await addColumnIfMissing('deleted', 'integer not null default 0');
        await addColumnIfMissing('reminderAt', 'text');
        await addColumnIfMissing('color', 'integer not null default 0');
        await addColumnIfMissing('folderId', 'integer');
        await addColumnIfMissing('isFavorite', 'integer not null default 0');
        await addColumnIfMissing('noteType', 'text not null default \'note\'');
        await addColumnIfMissing('price', 'text');
        await addColumnIfMissing('imagePath', 'text');

        await db.execute(
          'CREATE TABLE IF NOT EXISTS tags(id integer primary key autoincrement, name text not null, createdAt text not null, remoteId text)'
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS note_tags(noteId integer not null, tagId integer not null, unique(noteId, tagId) on conflict ignore)'
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS folders(id integer primary key autoincrement, name text not null, color integer not null, icon text not null, createdAt text not null, remoteId text)'
        );
        await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_remoteId ON tags(remoteId)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_note_tags_noteId ON note_tags(noteId)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_note_tags_tagId ON note_tags(tagId)');
        await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_folders_remoteId ON folders(remoteId)');
        // Add unique index to prevent duplicate rows per remoteId
        await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_notes_remoteId ON notes(remoteId)');
      },
      version: 1,
    );

    _cachedDatabase = database;
    return database;
  }

  // Clear cache only (don't delete database files)
  static Future<void> clearCache() async {
    if (_cachedDatabase != null && _cachedDatabase!.isOpen) {
      await _cachedDatabase!.close();
    }
    _cachedDatabase = null;
    _currentUserId = null;
  }

  // Clear all data for current user (clear cache and optionally delete database file)
  static Future<void> clearUserData({bool deleteFile = false}) async {
    final userId = _currentUserId;
    
    // Clear cache
    await clearCache();
    
    // Optionally delete database file for current user
    if (deleteFile && userId != null) {
      await clearDataForUser(userId);
    }
  }

  // Clear data for specific user
  static Future<void> clearDataForUser(String userId) async {
    final dbPath = await getDatabasesPath();
    final dbFile = File(join(dbPath, 'notes_$userId.db'));
    if (await dbFile.exists()) {
      try {
        await dbFile.delete();
      } catch (_) {
        // Ignore errors
      }
    }
    
    // If this is the current user, close and clear cache
    if (_currentUserId == userId) {
      if (_cachedDatabase != null && _cachedDatabase!.isOpen) {
        await _cachedDatabase!.close();
      }
      _cachedDatabase = null;
      _currentUserId = null;
    }
  }
}
