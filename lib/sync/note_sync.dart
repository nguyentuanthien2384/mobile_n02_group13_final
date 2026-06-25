import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/database/tag_database.dart';
import 'package:todoapp/helper/database.dart';
import 'dart:async';
import 'dart:convert';

class NoteSyncService {
  static CollectionReference<Map<String, dynamic>> _userNotesCol(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid).collection('notes');
  }

  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>> listenRealtime(
    Database db,
    void Function() onAnyChange,
  ) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Return a dummy subscription
      final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
      return controller.stream.listen((_) {});
    }
    final col = _userNotesCol(user.uid);
    return col.snapshots(includeMetadataChanges: true).listen((snap) async {
      for (final change in snap.docChanges) {
        final rid = change.doc.id;
        
        // Handle deleted documents first (before checking data)
        if (change.type == DocumentChangeType.removed) {
          final rows = await db.rawQuery('select id from notes where remoteId = ?', [rid]);
          if (rows.isNotEmpty) {
            final localId = rows.first['id'] as int;
            await NoteDatabase.deleteNote(db, localId);
            // ignore: avoid_print
            print('[NoteSync] RT deleted note rid=$rid -> localId=$localId');
          }
          continue;
        }
        
        final data = change.doc.data();
        if (data == null) continue;
        
        // Skip local pending writes to avoid double-processing our own adds/updates
        if (change.doc.metadata.hasPendingWrites) {
          // ignore: avoid_print
          print('[NoteSync] RT skip pending local write rid=$rid');
          continue;
        }
        final createdAt = DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now();
        final editedAt = DateTime.tryParse(data['editedAt'] as String? ?? '');
        final pinned = (data['pinned'] == true);
        final title = data['title'] as String?;
        final content = data['content'] as String?;
        final remoteTagsRaw = data['tags'];
        final mappedTagIds = await _mapRemoteTagsToLocal(db, remoteTagsRaw is List ? remoteTagsRaw : const []);

        final rows = await db.rawQuery('select id, createdAt, editedAt from notes where remoteId = ?', [rid]);
        if (rows.isEmpty) {
          final dynamicLocalId = data['localId'];
          if (dynamicLocalId is int) {
            final existsLocal = await db.rawQuery('select id from notes where id = ?', [dynamicLocalId]);
            if (existsLocal.isNotEmpty) {
              // Detect isChecklist from content or remote data
              bool isChecklist = (data['isChecklist'] == true);
              if (!isChecklist && content != null) {
                try { final l = jsonDecode(content); if (l is List) isChecklist = true; } catch (_) {}
              }
              await db.update(
                'notes',
                {
                  'title': title,
                  'content': content,
                  'createdAt': createdAt.toIso8601String(),
                  'editedAt': editedAt?.toIso8601String(),
                  'pinned': pinned ? 1 : 0,
                  'remoteId': rid,
                  'isChecklist': isChecklist ? 1 : 0,
                },
                where: 'id = ?',
                whereArgs: [dynamicLocalId],
              );
              await TagDatabase.setTagsForNote(db, dynamicLocalId, mappedTagIds);
              // ignore: avoid_print
              print('[NoteSync] RT attach remoteId to existing localId=$dynamicLocalId');
            } else {
              // Detect isChecklist from content or remote data
              bool isChecklist = (data['isChecklist'] == true);
              if (!isChecklist && content != null) {
                try { final l = jsonDecode(content); if (l is List) isChecklist = true; } catch (_) {}
              }
              final insertedId = await db.rawInsert(
                'insert or ignore into notes (title, content, createdAt, editedAt, pinned, remoteId, isChecklist) values(?, ?, ?, ?, ?, ?, ?)',
                [title, content, createdAt.toIso8601String(), editedAt?.toIso8601String(), pinned ? 1 : 0, rid, isChecklist ? 1 : 0],
              );
              await TagDatabase.setTagsForNote(db, insertedId, mappedTagIds);
              // ignore: avoid_print
              print('[NoteSync] RT insert new local for remoteId=$rid');
            }
          } else {
            // Detect isChecklist from content or remote data
            bool isChecklist = (data['isChecklist'] == true);
            if (!isChecklist && content != null) {
              try { final l = jsonDecode(content); if (l is List) isChecklist = true; } catch (_) {}
            }
            final insertedId = await db.rawInsert(
              'insert or ignore into notes (title, content, createdAt, editedAt, pinned, remoteId, isChecklist) values(?, ?, ?, ?, ?, ?, ?)',
              [title, content, createdAt.toIso8601String(), editedAt?.toIso8601String(), pinned ? 1 : 0, rid, isChecklist ? 1 : 0],
            );
            await TagDatabase.setTagsForNote(db, insertedId, mappedTagIds);
            // ignore: avoid_print
            print('[NoteSync] RT insert new local for remoteId=$rid (no localId)');
          }
        } else {
          final localEditedStr = rows.first['editedAt'] as String?;
          final localEdited = (localEditedStr == null) ? DateTime.fromMillisecondsSinceEpoch(0) : DateTime.tryParse(localEditedStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
          final remoteEdited = editedAt ?? createdAt;
          if (remoteEdited.isAfter(localEdited)) {
            final localId = rows.first['id'] as int;
            // Get current isChecklist from local DB to preserve it
            final currentRows = await db.rawQuery('select isChecklist from notes where id = ?', [localId]);
            final currentIsChecklist = (currentRows.isNotEmpty && (currentRows.first['isChecklist'] ?? 0) as int == 1);
            // Also check remote isChecklist
            bool remoteIsChecklist = (data['isChecklist'] == true);
            if (!remoteIsChecklist && content != null) {
              try { final l = jsonDecode(content); if (l is List) remoteIsChecklist = true; } catch (_) {}
            }
            final updated = Note(
              id: localId,
              title: title,
              content: content,
              createdAt: createdAt,
              editedAt: editedAt,
              pinned: pinned,
              remoteId: rid,
              isChecklist: remoteIsChecklist || currentIsChecklist,
              tagIds: mappedTagIds,
            );
            await TagDatabase.setTagsForNote(db, localId, mappedTagIds);
            await NoteDatabase.updateNote(db, updated);
          }
        }
      }
      onAnyChange();
    });
  }

  static Future<void> syncAll(Database db, List<Note> localNotes) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // ignore: avoid_print
        print('[NoteSync] skip syncAll: no user');
        return;
      }
      final col = _userNotesCol(user.uid);

      final remoteSnap = await col.get();
      // ignore: avoid_print
      print('[NoteSync] syncAll: remote count=${remoteSnap.docs.length}');
      final remoteDocs = {for (var d in remoteSnap.docs) d.id: d.data()};
      final localByRemote = {for (var n in localNotes) if (n.remoteId != null) n.remoteId!: n};

      // 1) Upload locals without remoteId
      for (final n in localNotes.where((n) => n.remoteId == null)) {
        final payload = {
          'title': n.title,
          'content': n.content,
          'createdAt': n.createdAt.toIso8601String(),
          'editedAt': (n.editedAt ?? n.createdAt).toIso8601String(),
          'pinned': n.pinned,
          'localId': n.id,
          'isChecklist': n.isChecklist,
          'tags': await _mapLocalTagsToRemote(db, n.tagIds),
        };
        final doc = await col.add(payload);
        // ignore: avoid_print
        print('[NoteSync] uploaded local -> remoteId=${doc.id}');
        n.remoteId = doc.id;
        await NoteDatabase.updateNote(db, n);
      }

      // 2) Download/attach remotes not in local
      for (final entry in remoteDocs.entries) {
        final rid = entry.key;
        final data = entry.value;
        if (!localByRemote.containsKey(rid)) {
          final createdAt = DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now();
          final editedAt = DateTime.tryParse(data['editedAt'] as String? ?? '');
          final contentStr = data['content'] as String?;
          bool isChecklist = (data['isChecklist'] == true);
          if (!isChecklist && contentStr != null) {
            try { final l = jsonDecode(contentStr); if (l is List) isChecklist = true; } catch (_) {}
          }
          final remoteTagsRaw = data['tags'];
          final localTagIds = await _mapRemoteTagsToLocal(db, remoteTagsRaw is List ? remoteTagsRaw : const []);
          final dynamicLocalId = data['localId'];
          if (dynamicLocalId is int) {
            final existingLocal = await db.rawQuery('select id from notes where id = ?', [dynamicLocalId]);
            if (existingLocal.isNotEmpty) {
              await db.update(
                'notes',
                {
                  'title': data['title'] as String?,
                  'content': contentStr,
                  'createdAt': createdAt.toIso8601String(),
                  'editedAt': editedAt?.toIso8601String(),
                  'pinned': (data['pinned'] == true) ? 1 : 0,
                  'remoteId': rid,
                  'isChecklist': isChecklist ? 1 : 0,
                },
                where: 'id = ?',
                whereArgs: [dynamicLocalId],
              );
              await TagDatabase.setTagsForNote(db, dynamicLocalId, localTagIds);
              // ignore: avoid_print
              print('[NoteSync] attach remoteId to existing localId=$dynamicLocalId');
              continue;
            }
          }
          final noteId = await db.rawInsert(
            'insert or ignore into notes (title, content, createdAt, editedAt, pinned, remoteId, isChecklist) values(?, ?, ?, ?, ?, ?, ?)',
            [
              data['title'] as String?,
              contentStr,
              createdAt.toIso8601String(),
              editedAt?.toIso8601String(),
              (data['pinned'] == true) ? 1 : 0,
              rid,
              isChecklist ? 1 : 0,
            ],
          );
          await TagDatabase.setTagsForNote(db, noteId, localTagIds);
          // ignore: avoid_print
          print('[NoteSync] downloaded remote -> localId=$noteId');
        }
      }

      // 4) Delete local notes that no longer exist on remote
      final remoteIds = remoteDocs.keys.toSet();
      for (final n in localNotes.where((n) => n.remoteId != null)) {
        if (!remoteIds.contains(n.remoteId)) {
          await NoteDatabase.deleteNote(db, n.id);
          // ignore: avoid_print
          print('[NoteSync] deleted local note (missing on remote) localId=${n.id} remoteId=${n.remoteId}');
        }
      }

      // 3) Resolve conflicts simple: newer editedAt wins (push local if newer, else pull)
      for (final n in localNotes.where((n) => n.remoteId != null)) {
        final data = remoteDocs[n.remoteId];
        if (data == null) continue;
        final remoteEdited = DateTime.tryParse(data['editedAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final localEdited = n.editedAt ?? n.createdAt;
        final remoteTagsRaw = data['tags'];
        final remoteTagIds = await _mapRemoteTagsToLocal(db, remoteTagsRaw is List ? remoteTagsRaw : const []);
        if (localEdited.isAfter(remoteEdited)) {
          await col.doc(n.remoteId).set({
            'title': n.title,
            'content': n.content,
            'createdAt': n.createdAt.toIso8601String(),
            'editedAt': (n.editedAt ?? n.createdAt).toIso8601String(),
            'pinned': n.pinned,
            'localId': n.id,
            'isChecklist': n.isChecklist,
            'tags': await _mapLocalTagsToRemote(db, n.tagIds),
          }, SetOptions(merge: true));
          // ignore: avoid_print
          print('[NoteSync] pushed newer local -> remoteId=${n.remoteId}');
        } else if (remoteEdited.isAfter(localEdited)) {
          final updated = Note(
            id: n.id,
            title: data['title'] as String?,
            content: data['content'] as String?,
            createdAt: DateTime.tryParse(data['createdAt'] as String? ?? '') ?? n.createdAt,
            editedAt: remoteEdited,
            pinned: (data['pinned'] == true),
            remoteId: n.remoteId,
            isChecklist: (data['isChecklist'] == true) || n.isChecklist,
            tagIds: remoteTagIds,
          );
          await TagDatabase.setTagsForNote(db, n.id, remoteTagIds);
          await NoteDatabase.updateNote(db, updated);
          // ignore: avoid_print
          print('[NoteSync] pulled newer remote -> localId=${n.id}');
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[NoteSync] syncAll error: $e');
    }
  }

  static Future<void> pushAdded(Database db, Note note) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // ignore: avoid_print
        print('[NoteSync] pushAdded error: No user logged in');
        return;
      }
      final payload = {
        'title': note.title,
        'content': note.content,
        'createdAt': note.createdAt.toIso8601String(),
        'editedAt': (note.editedAt ?? note.createdAt).toIso8601String(),
        'pinned': note.pinned,
        'localId': note.id,
        'isChecklist': note.isChecklist,
        'tags': await _mapLocalTagsToRemote(db, note.tagIds),
      };
      final doc = await _userNotesCol(user.uid).add(payload);
      // ignore: avoid_print
      print('[NoteSync] pushAdded -> remoteId=${doc.id}');
      note.remoteId = doc.id;
      await NoteDatabase.updateNote(db, note);
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('[NoteSync] pushAdded error: $e');
      print('[NoteSync] Stack trace: $stackTrace');
      rethrow; // Re-throw để caller có thể handle
    }
  }

  static Future<void> pushUpdated(Note note, {List<String>? remoteTagIds}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || note.remoteId == null) return;
      final db = await DatabaseHelper.database();
      final tags = remoteTagIds ?? await _mapLocalTagsToRemote(db, note.tagIds);
      await _userNotesCol(user.uid).doc(note.remoteId).set({
        'title': note.title,
        'content': note.content,
        'createdAt': note.createdAt.toIso8601String(),
        'editedAt': (note.editedAt ?? note.createdAt).toIso8601String(),
        'pinned': note.pinned,
        'localId': note.id,
        'isChecklist': note.isChecklist,
        'tags': tags,
      }, SetOptions(merge: true));
      // ignore: avoid_print
      print('[NoteSync] pushUpdated -> remoteId=${note.remoteId}');
    } catch (e) {
      // ignore: avoid_print
      print('[NoteSync] pushUpdated error: $e');
    }
  }

  static Future<void> pushDeleted(Note note) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || note.remoteId == null) return;
      await _userNotesCol(user.uid).doc(note.remoteId).delete();
      // ignore: avoid_print
      print('[NoteSync] pushDeleted -> remoteId=${note.remoteId}');
    } catch (e) {
      // ignore: avoid_print
      print('[NoteSync] pushDeleted error: $e');
    }
  }

  static Future<void> pushNoteTags(Database db, int noteId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final note = await NoteDatabase.getNote(db, noteId);
      if (note.remoteId == null) return;
      final remoteTagIds = await _mapLocalTagsToRemote(db, note.tagIds);
      await _userNotesCol(user.uid).doc(note.remoteId).set({
        'tags': remoteTagIds,
        'localId': note.id,
      }, SetOptions(merge: true));
      // ignore: avoid_print
      print('[NoteSync] pushNoteTags -> remoteId=${note.remoteId}');
    } catch (e) {
      // ignore: avoid_print
      print('[NoteSync] pushNoteTags error: $e');
    }
  }

  static Future<List<String>> _mapLocalTagsToRemote(Database db, Iterable<int> tagIds) async {
    if (tagIds.isEmpty) return const [];
    final placeholders = List.filled(tagIds.length, '?').join(',');
    final rows = await db.rawQuery('SELECT id, remoteId FROM tags WHERE id IN ($placeholders)', tagIds.toList());
    final Map<int, String?> remoteById = {
      for (final row in rows)
        row['id'] as int: row['remoteId'] as String?,
    };
    final result = <String>[];
    for (final id in tagIds) {
      final remoteId = remoteById[id];
      if (remoteId != null && remoteId.isNotEmpty) {
        result.add(remoteId);
      }
    }
    return result;
  }

  static Future<List<int>> _mapRemoteTagsToLocal(Database db, Iterable<dynamic> remoteIds) async {
    final ids = remoteIds.whereType<String>().where((e) => e.isNotEmpty).toList();
    if (ids.isEmpty) return const [];
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.rawQuery('SELECT id, remoteId FROM tags WHERE remoteId IN ($placeholders)', ids);
    final Map<String, int> localByRemote = {
      for (final row in rows)
        row['remoteId'] as String: row['id'] as int,
    };
    final result = <int>[];
    for (final rid in ids) {
      final localId = localByRemote[rid];
      if (localId != null) {
        result.add(localId);
      }
    }
    return result;
  }
}


