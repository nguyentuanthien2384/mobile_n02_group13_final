import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart';
import 'package:todoapp/class/tag.dart';
import 'package:todoapp/database/tag_database.dart';

class TagSyncService {
  static CollectionReference<Map<String, dynamic>> _userTagsCol(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid).collection('tags');
  }

  static Future<void> syncAll(Database db, List<Tag> localTags) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final col = _userTagsCol(user.uid);
      final remoteSnap = await col.get();
      final remoteDocs = {for (var d in remoteSnap.docs) d.id: d.data()};
      final localByRemote = {for (var t in localTags) if (t.remoteId != null) t.remoteId!: t};

      // Upload locals without remoteId
      for (final tag in localTags.where((t) => t.remoteId == null)) {
        final doc = await col.add({
          'name': tag.name,
          'createdAt': tag.createdAt.toIso8601String(),
          'localId': tag.id,
        });
        await TagDatabase.setTagRemoteId(db, tag.id, doc.id);
      }

      // Download remote tags not in local
      for (final entry in remoteDocs.entries) {
        final rid = entry.key;
        final data = entry.value;
        if (!localByRemote.containsKey(rid)) {
          final name = data['name'] as String? ?? 'Untitled';
          final createdAt = DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now();
          final localId = data['localId'];
          if (localId is int) {
            final existing = await db.query('tags', where: 'id = ?', whereArgs: [localId]);
            if (existing.isNotEmpty) {
              await db.update(
                'tags',
                {'name': name, 'createdAt': createdAt.toIso8601String(), 'remoteId': rid},
                where: 'id = ?',
                whereArgs: [localId],
              );
              continue;
            }
          }
          final tagId = await TagDatabase.insertTag(
            db,
            Tag(id: 0, name: name, createdAt: createdAt, remoteId: rid),
          );
          await TagDatabase.setTagRemoteId(db, tagId, rid);
        } else {
          final local = localByRemote[rid]!;
          final remoteName = data['name'] as String? ?? local.name;
          final remoteCreated = DateTime.tryParse(data['createdAt'] as String? ?? '') ?? local.createdAt;
          if (remoteName != local.name || remoteCreated != local.createdAt) {
            await TagDatabase.updateTag(
              db,
              Tag(id: local.id, name: remoteName, createdAt: remoteCreated, remoteId: rid, noteIds: local.noteIds),
            );
          }
        }
      }

      // Remove locals missing remotely
      final remoteIds = remoteDocs.keys.toSet();
      for (final tag in localTags.where((t) => t.remoteId != null)) {
        if (!remoteIds.contains(tag.remoteId)) {
          await TagDatabase.deleteTag(db, tag.id);
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[TagSync] syncAll error: $e');
    }
  }

  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>> listenRealtime(
    Database db,
    Future<void> Function() onAnyChange,
  ) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
      return controller.stream.listen((_) {});
    }
    final col = _userTagsCol(user.uid);
    return col.snapshots(includeMetadataChanges: true).listen((snap) async {
      for (final change in snap.docChanges) {
        final rid = change.doc.id;
        
        // Handle deleted documents first (before checking data)
        if (change.type == DocumentChangeType.removed) {
          final rows = await db.query('tags', where: 'remoteId = ?', whereArgs: [rid]);
          if (rows.isNotEmpty) {
            final localId = rows.first['id'] as int;
            await TagDatabase.deleteTag(db, localId);
            // ignore: avoid_print
            print('[TagSync] RT deleted tag rid=$rid -> localId=$localId');
          }
          continue;
        }
        
        final data = change.doc.data();
        if (data == null) continue;
        
        if (change.doc.metadata.hasPendingWrites) continue;
        final name = data['name'] as String? ?? 'Untitled';
        final createdAt = DateTime.tryParse(data['createdAt'] as String? ?? '') ?? DateTime.now();
        final rows = await db.query('tags', where: 'remoteId = ?', whereArgs: [rid]);
        if (rows.isEmpty) {
          final localId = data['localId'];
          if (localId is int) {
            final exists = await db.query('tags', where: 'id = ?', whereArgs: [localId]);
            if (exists.isNotEmpty) {
              await TagDatabase.updateTag(
                db,
                Tag(id: localId, name: name, createdAt: createdAt, remoteId: rid),
              );
              continue;
            }
          }
          final insertedId = await TagDatabase.insertTag(
            db,
            Tag(id: 0, name: name, createdAt: createdAt, remoteId: rid),
          );
          await TagDatabase.setTagRemoteId(db, insertedId, rid);
        } else {
          final localId = rows.first['id'] as int;
          await TagDatabase.updateTag(
            db,
            Tag(id: localId, name: name, createdAt: createdAt, remoteId: rid),
          );
        }
      }
      await onAnyChange();
    });
  }

  static Future<String?> pushAdded(Database db, Tag tag) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      final doc = await _userTagsCol(user.uid).add({
        'name': tag.name,
        'createdAt': tag.createdAt.toIso8601String(),
        'localId': tag.id,
      });
      await TagDatabase.setTagRemoteId(db, tag.id, doc.id);
      return doc.id;
    } catch (e) {
      // ignore: avoid_print
      print('[TagSync] pushAdded error: $e');
      return null;
    }
  }

  static Future<void> pushUpdated(Tag tag) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || tag.remoteId == null) return;
      await _userTagsCol(user.uid).doc(tag.remoteId).set({
        'name': tag.name,
        'createdAt': tag.createdAt.toIso8601String(),
        'localId': tag.id,
      }, SetOptions(merge: true));
    } catch (e) {
      // ignore: avoid_print
      print('[TagSync] pushUpdated error: $e');
    }
  }

  static Future<void> pushDeleted(Tag tag) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || tag.remoteId == null) return;
      await _userTagsCol(user.uid).doc(tag.remoteId).delete();
    } catch (e) {
      // ignore: avoid_print
      print('[TagSync] pushDeleted error: $e');
    }
  }
}
