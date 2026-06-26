import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/database/tag_database.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/services/note_api_service.dart';
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
      final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
      return controller.stream.listen((_) {});
    }
    final col = _userNotesCol(user.uid);
    return col.snapshots(includeMetadataChanges: true).listen((snap) async {
      for (final change in snap.docChanges) {
        final rid = change.doc.id;
        
        if (change.type == DocumentChangeType.removed) {
          final rows = await db.rawQuery('select id from notes where remoteId = ?', [rid]);
          if (rows.isNotEmpty) {
            final localId = rows.first['id'] as int;
            await NoteDatabase.deleteNote(db, localId);
            print('[NoteSync] RT deleted note rid=$rid -> localId=$localId');
          }
          continue;
        }
        
        final data = change.doc.data();
        if (data == null) continue;
        
        if (change.doc.metadata.hasPendingWrites) {
          print('[NoteSync] RT skip pending local write rid=$rid');
          continue;
        }
        final createdAt = DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now();
        final editedAt = DateTime.tryParse(data['editedAt'] as String? ?? '');
        final pinned = (data['pinned'] == true);
        final title = data['title'] as String?;
        final content = data['content'] as String?;
        final color = data['color'] as int? ?? 0;
        final folderId = data['folderId'] as int?;
        final isFavorite = (data['isFavorite'] == true);
        final remoteTagsRaw = data['tags'];
        final mappedTagIds = await _mapRemoteTagsToLocal(db, remoteTagsRaw is List ? remoteTagsRaw : const []);

        final rows = await db.rawQuery('select id, createdAt, editedAt from notes where remoteId = ?', [rid]);
        if (rows.isEmpty) {
          final dynamicLocalId = data['localId'];
          if (dynamicLocalId is int) {
            final existsLocal = await db.rawQuery('select id from notes where id = ?', [dynamicLocalId]);
            if (existsLocal.isNotEmpty) {
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
                  'color': color,
                  'folderId': folderId,
                  'isFavorite': isFavorite ? 1 : 0,
                },
                where: 'id = ?',
                whereArgs: [dynamicLocalId],
              );
              await TagDatabase.setTagsForNote(db, dynamicLocalId, mappedTagIds);
              print('[NoteSync] RT attach remoteId to existing localId=$dynamicLocalId');
            } else {
              bool isChecklist = (data['isChecklist'] == true);
              if (!isChecklist && content != null) {
                try { final l = jsonDecode(content); if (l is List) isChecklist = true; } catch (_) {}
              }
              final insertedId = await db.rawInsert(
                'insert or ignore into notes (title, content, createdAt, editedAt, pinned, remoteId, isChecklist, color, folderId, isFavorite) values(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
                [title, content, createdAt.toIso8601String(), editedAt?.toIso8601String(), pinned ? 1 : 0, rid, isChecklist ? 1 : 0, color, folderId, isFavorite ? 1 : 0],
              );
              await TagDatabase.setTagsForNote(db, insertedId, mappedTagIds);
              print('[NoteSync] RT insert new local for remoteId=$rid');
            }
          } else {
            bool isChecklist = (data['isChecklist'] == true);
            if (!isChecklist && content != null) {
              try { final l = jsonDecode(content); if (l is List) isChecklist = true; } catch (_) {}
            }
            final insertedId = await db.rawInsert(
              'insert or ignore into notes (title, content, createdAt, editedAt, pinned, remoteId, isChecklist, color, folderId, isFavorite) values(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
              [title, content, createdAt.toIso8601String(), editedAt?.toIso8601String(), pinned ? 1 : 0, rid, isChecklist ? 1 : 0, color, folderId, isFavorite ? 1 : 0],
            );
            await TagDatabase.setTagsForNote(db, insertedId, mappedTagIds);
            print('[NoteSync] RT insert new local for remoteId=$rid (no localId)');
          }
        } else {
          final localEditedStr = rows.first['editedAt'] as String?;
          final localEdited = (localEditedStr == null) ? DateTime.fromMillisecondsSinceEpoch(0) : DateTime.tryParse(localEditedStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
          final remoteEdited = editedAt ?? createdAt;
          if (remoteEdited.isAfter(localEdited)) {
            final localId = rows.first['id'] as int;
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
              isChecklist: remoteIsChecklist,
              tagIds: mappedTagIds,
              color: color,
              folderId: folderId,
              isFavorite: isFavorite,
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
        print('[NoteSync] skip syncAll: no user');
        return;
      }

      final remoteNotes = await NoteApiService.fetchNotes();
      print('[NoteSync] syncAll: remote count=${remoteNotes.length}');
      final remoteNotesMap = {for (var n in remoteNotes) n.remoteId!: n};
      final localByRemote = {for (var n in localNotes) if (n.remoteId != null) n.remoteId!: n};

      // 1) Upload locals without remoteId
      for (final n in localNotes.where((n) => n.remoteId == null)) {
        final created = await NoteApiService.createNote(n);
        if (created != null && created.remoteId != null) {
          print('[NoteSync] uploaded local -> remoteId=${created.remoteId}');
          n.remoteId = created.remoteId;
          await NoteDatabase.updateNote(db, n);
        }
      }

      // 2) Download/attach remotes not in local
      for (final remoteNote in remoteNotes) {
        final rid = remoteNote.remoteId!;
        if (!localByRemote.containsKey(rid)) {
          final dynamicLocalId = remoteNote.id;
          final existingLocal = await db.rawQuery('select id from notes where id = ?', [dynamicLocalId]);
          if (existingLocal.isNotEmpty) {
            await db.update(
              'notes',
              {
                'title': remoteNote.title,
                'content': remoteNote.content,
                'createdAt': remoteNote.createdAt.toIso8601String(),
                'editedAt': remoteNote.editedAt?.toIso8601String(),
                'pinned': remoteNote.pinned ? 1 : 0,
                'remoteId': rid,
                'isChecklist': remoteNote.isChecklist ? 1 : 0,
                'color': remoteNote.color,
                'folderId': remoteNote.folderId,
                'isFavorite': remoteNote.isFavorite ? 1 : 0,
              },
              where: 'id = ?',
              whereArgs: [dynamicLocalId],
            );
            print('[NoteSync] attach remoteId to existing localId=$dynamicLocalId');
            continue;
          }

          final noteId = await db.rawInsert(
            'insert or ignore into notes (title, content, createdAt, editedAt, pinned, remoteId, isChecklist, color, folderId, isFavorite) values(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              remoteNote.title,
              remoteNote.content,
              remoteNote.createdAt.toIso8601String(),
              remoteNote.editedAt?.toIso8601String(),
              remoteNote.pinned ? 1 : 0,
              rid,
              remoteNote.isChecklist ? 1 : 0,
              remoteNote.color,
              remoteNote.folderId,
              remoteNote.isFavorite ? 1 : 0,
            ],
          );
          print('[NoteSync] downloaded remote -> localId=$noteId');
        }
      }

      // 3) Delete local notes that no longer exist on remote
      final remoteIds = remoteNotesMap.keys.toSet();
      for (final n in localNotes.where((n) => n.remoteId != null)) {
        if (!remoteIds.contains(n.remoteId)) {
          await NoteDatabase.deleteNote(db, n.id);
          print('[NoteSync] deleted local note (missing on remote) localId=${n.id} remoteId=${n.remoteId}');
        }
      }

      // 4) Resolve conflicts simple: newer editedAt wins
      for (final n in localNotes.where((n) => n.remoteId != null)) {
        final rn = remoteNotesMap[n.remoteId];
        if (rn == null) continue;
        final remoteEdited = rn.editedAt ?? rn.createdAt;
        final localEdited = n.editedAt ?? n.createdAt;
        if (localEdited.isAfter(remoteEdited)) {
          await NoteApiService.updateNote(n);
          print('[NoteSync] pushed newer local -> remoteId=${n.remoteId}');
        } else if (remoteEdited.isAfter(localEdited)) {
          await NoteDatabase.updateNote(db, rn.copyWith(id: n.id));
          print('[NoteSync] pulled newer remote -> localId=${n.id}');
        }
      }
    } catch (e) {
      print('[NoteSync] syncAll error: $e');
    }
  }

  static Future<void> pushAdded(Database db, Note note) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final created = await NoteApiService.createNote(note);
      if (created != null && created.remoteId != null) {
        note.remoteId = created.remoteId;
        await NoteDatabase.updateNote(db, note);
        print('[NoteSync] pushAdded -> remoteId=${created.remoteId}');
      }
    } catch (e) {
      print('[NoteSync] pushAdded error: $e');
    }
  }

  static Future<void> pushUpdated(Note note) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || note.remoteId == null) return;
      await NoteApiService.updateNote(note);
      print('[NoteSync] pushUpdated -> remoteId=${note.remoteId}');
    } catch (e) {
      print('[NoteSync] pushUpdated error: $e');
    }
  }

  static Future<void> pushDeleted(Note note) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || note.remoteId == null) return;
      await NoteApiService.deleteNote(note.remoteId!);
      print('[NoteSync] pushDeleted -> remoteId=${note.remoteId}');
    } catch (e) {
      print('[NoteSync] pushDeleted error: $e');
    }
  }

  static Future<void> pushNoteTags(Database db, int noteId) async {
    // Keep tag sync logic local or simple for now
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
