import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class DatabaseHelper {
  DatabaseHelper();

  static String? _currentUserId;
  static Database? _cachedDatabase;
  static const _legacyOwnerPreference = 'legacy_notes_owner_uid';
  // Opening/closing a SQLite file can overlap with an auth-state change.  Keep
  // those operations serialised so a database belonging to the previous user
  // can never become the active cache for the next user.
  static Future<void> _operationQueue = Future<void>.value();

  static Future<T> _synchronized<T>(Future<T> Function() action) {
    final previous = _operationQueue;
    final completed = Completer<void>();
    _operationQueue = completed.future;
    return previous.then((_) async {
      try {
        return await action();
      } finally {
        completed.complete();
      }
    });
  }

  /// True only while [userId] is still the account active in Firebase Auth.
  /// Sync callers use this to discard work that finishes after account switch.
  static bool isCurrentUser(String? userId) =>
      FirebaseAuth.instance.currentUser?.uid == userId;

  static Future<Database> database() async {
    return _synchronized(_openDatabaseForCurrentUser);
  }

  static Future<Database> _openDatabaseForCurrentUser() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Authentication can change while openDatabase awaits the filesystem.
    // Retry in that case instead of retaining a stale user's database.
    while (true) {
      final userId = FirebaseAuth.instance.currentUser?.uid;

      if (_currentUserId != userId) {
        if (_cachedDatabase != null && _cachedDatabase!.isOpen) {
          await _cachedDatabase!.close();
        }
        _cachedDatabase = null;
        _currentUserId = null;
      }

      if (_cachedDatabase != null && _cachedDatabase!.isOpen) {
        return _cachedDatabase!;
      }

      // Every signed-in account has a separate local database.  The guest
      // database is never reused after a user signs in.
      final dbFileName = userId != null ? 'notes_$userId.db' : 'notes_guest.db';
      final database = await openDatabase(
        join(await getDatabasesPath(), dbFileName),
        onCreate: (db, version) async {
          await db.execute(
            'create table if not exists notes(id integer primary key autoincrement, title text, content text, createdAt text not null, editedAt text, pinned integer not null default 0, remoteId text, isChecklist integer not null default 0, deleted integer not null default 0, reminderAt text, color integer not null default 0, folderId integer, isFavorite integer not null default 0, noteType text not null default \'note\', price text, imagePath text, collaborators text, sharedExternally integer not null default 0)',
          );
          await db.execute(
            'create table if not exists tags(id integer primary key autoincrement, name text not null, createdAt text not null, remoteId text)',
          );
          await db.execute(
            'create table if not exists note_tags(noteId integer not null, tagId integer not null, unique(noteId, tagId) on conflict ignore)',
          );
          await db.execute(
            'create table if not exists folders(id integer primary key autoincrement, name text not null, color integer not null, icon text not null, createdAt text not null, remoteId text)',
          );
          await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_remoteId ON tags(remoteId)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_note_tags_noteId ON note_tags(noteId)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_note_tags_tagId ON note_tags(tagId)',
          );
          await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_folders_remoteId ON folders(remoteId)',
          );
        },
        onOpen: (db) async {
          // Migration: if old table `dogs` exists and `notes` doesn't, rename it
          final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'",
          );
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
          Future<void> addColumnIfMissing(
            String name,
            String sqlTypeAndDefault,
          ) async {
            if (existing.contains(name)) return;
            await db.execute(
              'ALTER TABLE notes ADD COLUMN $name $sqlTypeAndDefault',
            );
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
          await addColumnIfMissing(
            'noteType',
            'text not null default \'note\'',
          );
          await addColumnIfMissing('price', 'text');
          await addColumnIfMissing('imagePath', 'text');
          await addColumnIfMissing('collaborators', 'text');
          await addColumnIfMissing(
            'sharedExternally',
            'integer not null default 0',
          );
          await addColumnIfMissing('archived', 'integer not null default 0');
          await addColumnIfMissing('deletedAt', 'text');
          await addColumnIfMissing(
            'reminderRepeat',
            'text not null default \'none\'',
          );
          await addColumnIfMissing(
            'reminderLeadMinutes',
            'integer not null default 0',
          );

          await db.execute(
            'CREATE TABLE IF NOT EXISTS tags(id integer primary key autoincrement, name text not null, createdAt text not null, remoteId text)',
          );
          await db.execute(
            'CREATE TABLE IF NOT EXISTS note_tags(noteId integer not null, tagId integer not null, unique(noteId, tagId) on conflict ignore)',
          );
          await db.execute(
            'CREATE TABLE IF NOT EXISTS folders(id integer primary key autoincrement, name text not null, color integer not null, icon text not null, createdAt text not null, remoteId text)',
          );
          await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_tags_remoteId ON tags(remoteId)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_note_tags_noteId ON note_tags(noteId)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_note_tags_tagId ON note_tags(tagId)',
          );
          await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_folders_remoteId ON folders(remoteId)',
          );
          // Add unique index to prevent duplicate rows per remoteId
          await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_notes_remoteId ON notes(remoteId)',
          );
        },
        version: 1,
      );

      if (!isCurrentUser(userId)) {
        await database.close();
        continue;
      }

      await _restoreLegacyNotesForFirstOwner(database, userId);
      if (!isCurrentUser(userId)) {
        await database.close();
        continue;
      }

      _currentUserId = userId;
      _cachedDatabase = database;
      return database;
    }
  }

  /// Restores pre-account My Note data once for the first account that opens
  /// the upgraded app. The legacy file is copied, not deleted, and the owner
  /// marker prevents it from being copied into any later account.
  static Future<void> _restoreLegacyNotesForFirstOwner(
    Database target,
    String? userId,
  ) async {
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_legacyOwnerPreference)) return;

    final targetNotes =
        Sqflite.firstIntValue(
          await target.rawQuery('SELECT COUNT(*) FROM notes'),
        ) ??
        0;
    final targetTags =
        Sqflite.firstIntValue(
          await target.rawQuery('SELECT COUNT(*) FROM tags'),
        ) ??
        0;
    final targetFolders =
        Sqflite.firstIntValue(
          await target.rawQuery('SELECT COUNT(*) FROM folders'),
        ) ??
        0;
    if (targetNotes > 0 || targetTags > 0 || targetFolders > 0) return;

    final dbPath = await getDatabasesPath();
    final legacyPath = join(dbPath, 'notes_guest.db');
    if (!await File(legacyPath).exists()) return;

    final legacy = await openDatabase(legacyPath, readOnly: true);
    try {
      final notes = await legacy.query('notes');
      final tags = await legacy.query('tags');
      final folders = await legacy.query('folders');
      final noteTags = await legacy.query('note_tags');
      if (notes.isEmpty && tags.isEmpty && folders.isEmpty) return;

      await target.transaction((transaction) async {
        for (final note in notes) {
          await transaction.insert(
            'notes',
            note,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        for (final tag in tags) {
          await transaction.insert(
            'tags',
            tag,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        for (final folder in folders) {
          await transaction.insert(
            'folders',
            folder,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        for (final link in noteTags) {
          await transaction.insert(
            'note_tags',
            link,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      });
      await prefs.setString(_legacyOwnerPreference, userId);
    } finally {
      await legacy.close();
    }
  }

  // Clear cache only (don't delete database files)
  static Future<void> clearCache() async {
    await _synchronized(() async {
      if (_cachedDatabase != null && _cachedDatabase!.isOpen) {
        await _cachedDatabase!.close();
      }
      _cachedDatabase = null;
      _currentUserId = null;
    });
  }

  // Clear all data for current user (clear cache and optionally delete database file)
  static Future<void> clearUserData({bool deleteFile = false}) async {
    await _synchronized(() async {
      final userId = _currentUserId;
      await _clearCache();
      if (deleteFile && userId != null) await _clearDataForUser(userId);
    });
  }

  // Clear data for specific user
  static Future<void> clearDataForUser(String userId) async {
    await _synchronized(() => _clearDataForUser(userId));
  }

  static Future<void> _clearCache() async {
    if (_cachedDatabase != null && _cachedDatabase!.isOpen) {
      await _cachedDatabase!.close();
    }
    _cachedDatabase = null;
    _currentUserId = null;
  }

  static Future<void> _clearDataForUser(String userId) async {
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
      await _clearCache();
    }
  }
}
