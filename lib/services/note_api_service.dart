import 'dart:convert';
import 'package:todoapp/class/comment.dart';
import 'package:todoapp/class/feed_post.dart';
import 'package:todoapp/class/note.dart';
import 'api_service.dart';

class NoteApiService {
  static Future<List<Note>> fetchNotes() async {
    try {
      final res = await ApiService.get('/notes');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List list = data['notes'] ?? [];
        return list.map((item) => _parseNoteJson(item)).toList();
      }
      return [];
    } catch (e) {
      print('[NoteApiService] fetchNotes error: $e');
      return [];
    }
  }

  static Future<List<Note>> fetchSharedNotes() async {
    try {
      final res = await ApiService.get('/notes/shared');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List list = data['notes'] ?? [];
        return list.map((item) {
          final note = _parseNoteJson(item);
          // Set extra properties for shared notes if any
          return note;
        }).toList();
      }
      return [];
    } catch (e) {
      print('[NoteApiService] fetchSharedNotes error: $e');
      return [];
    }
  }

  static Future<Note?> createNote(Note note) async {
    try {
      final body = note.toMap();
      body['localId'] = note.id;
      // We don't send tagIds directly as tags in Firestore is List<String> of remote tag IDs
      // But we will handle tag synchronization separately or during syncAll.
      final res = await ApiService.post('/notes', body);
      if (res.statusCode == 201) {
        final data = jsonDecode(res.body);
        return _parseNoteJson(data);
      }
      return null;
    } catch (e) {
      print('[NoteApiService] createNote error: $e');
      return null;
    }
  }

  static Future<Note?> updateNote(Note note) async {
    if (note.remoteId == null) return null;
    try {
      final body = note.toMap();
      body['localId'] = note.id;
      final res = await ApiService.put('/notes/${note.remoteId}', body);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return _parseNoteJson(data);
      }
      return null;
    } catch (e) {
      print('[NoteApiService] updateNote error: $e');
      return null;
    }
  }

  static Future<bool> deleteNote(String remoteId) async {
    try {
      final res = await ApiService.delete('/notes/$remoteId');
      return res.statusCode == 200;
    } catch (e) {
      print('[NoteApiService] deleteNote error: $e');
      return false;
    }
  }

  // Chia sẻ ghi chú với email
  static Future<Map<String, dynamic>?> shareNote({
    required String remoteId,
    required String email,
    required String permission, // 'view' hoặc 'edit'
  }) async {
    try {
      final res = await ApiService.post('/notes/$remoteId/share', {
        'email': email,
        'permission': permission,
        'isPublic': false,
      });
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('[NoteApiService] shareNote error: $e');
      return null;
    }
  }

  // Chia sẻ ghi chú công khai (Public link)
  static Future<Map<String, dynamic>?> sharePublic({
    required String remoteId,
    required String permission,
  }) async {
    try {
      final res = await ApiService.post('/notes/$remoteId/share', {
        'isPublic': true,
        'permission': permission,
      });
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('[NoteApiService] sharePublic error: $e');
      return null;
    }
  }

  // Lấy danh sách bình luận
  static Future<List<Comment>> fetchComments(String remoteId, {String? ownerUid}) async {
    try {
      String path = '/notes/$remoteId/comments';
      if (ownerUid != null) {
        path += '?ownerUid=$ownerUid';
      }
      final res = await ApiService.get(path);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List list = data['comments'] ?? [];
        return list.map((item) => Comment.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      print('[NoteApiService] fetchComments error: $e');
      return [];
    }
  }

  // Thêm bình luận
  static Future<Comment?> addComment(String remoteId, String text, {String? ownerUid}) async {
    try {
      final res = await ApiService.post('/notes/$remoteId/comments', {
        'text': text,
        'noteOwnerUid': ownerUid,
      });
      if (res.statusCode == 201) {
        final data = jsonDecode(res.body);
        return Comment.fromJson(data);
      }
      return null;
    } catch (e) {
      print('[NoteApiService] addComment error: $e');
      return null;
    }
  }

  // Lấy thông tin các tài khoản đang share chung ghi chú
  static Future<List<Map<String, dynamic>>> fetchShares(String remoteId) async {
    try {
      final res = await ApiService.get('/notes/$remoteId/shares');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List list = data['shares'] ?? [];
        return list.map((e) => e as Map<String, dynamic>).toList();
      }
      return [];
    } catch (e) {
      print('[NoteApiService] fetchShares error: $e');
      return [];
    }
  }

  // Hủy chia sẻ với 1 tài khoản
  static Future<bool> revokeShare(String remoteId, String targetUid) async {
    try {
      final res = await ApiService.delete('/notes/$remoteId/share/$targetUid');
      return res.statusCode == 200;
    } catch (e) {
      print('[NoteApiService] revokeShare error: $e');
      return false;
    }
  }

  // ══════════════════════════════════════════════════════════
  //  PROFESSIONAL FEATURES
  // ══════════════════════════════════════════════════════════

  /// Full-text search across the user's own notes (server-side).
  static Future<List<Note>> search(String query) async {
    try {
      final res = await ApiService.get('/notes/search?q=${Uri.encodeQueryComponent(query)}');
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body)['notes'] ?? [];
        return list.map((e) => _parseNoteJson(e)).toList();
      }
    } catch (e) {
      print('[NoteApiService] search error: $e');
    }
    return [];
  }

  // ─── Trash (soft delete) ──────────────────────────────────
  static Future<List<Note>> fetchTrash() => _fetchList('/notes/trash');

  static Future<bool> moveToTrash(String remoteId) =>
      _simpleDelete('/notes/$remoteId');

  static Future<bool> restoreFromTrash(String remoteId) =>
      _simplePost('/notes/$remoteId/restore');

  static Future<bool> deletePermanent(String remoteId) =>
      _simpleDelete('/notes/$remoteId?permanent=true');

  static Future<bool> emptyTrash() => _simpleDelete('/notes/trash/empty');

  // ─── Archive ──────────────────────────────────────────────
  static Future<List<Note>> fetchArchived() => _fetchList('/notes/archived');
  static Future<bool> archive(String remoteId) => _simplePost('/notes/$remoteId/archive');
  static Future<bool> unarchive(String remoteId) => _simplePost('/notes/$remoteId/unarchive');

  // ─── Duplicate ────────────────────────────────────────────
  static Future<Note?> duplicate(String remoteId) async {
    try {
      final res = await ApiService.post('/notes/$remoteId/duplicate', {});
      if (res.statusCode == 201) return _parseNoteJson(jsonDecode(res.body));
    } catch (e) {
      print('[NoteApiService] duplicate error: $e');
    }
    return null;
  }

  // ─── Version history ──────────────────────────────────────
  static Future<List<Map<String, dynamic>>> fetchVersions(String remoteId) async {
    try {
      final res = await ApiService.get('/notes/$remoteId/versions');
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body)['versions'] ?? [];
        return list.map((e) => e as Map<String, dynamic>).toList();
      }
    } catch (e) {
      print('[NoteApiService] fetchVersions error: $e');
    }
    return [];
  }

  static Future<bool> restoreVersion(String remoteId, String versionId) =>
      _simplePost('/notes/$remoteId/restore-version/$versionId');

  // ══════════════════════════════════════════════════════════
  //  SOCIAL FEATURES
  // ══════════════════════════════════════════════════════════

  /// Publish a note so it appears in the public feed.
  static Future<bool> publish(String remoteId) => _simplePost('/notes/$remoteId/publish');
  static Future<bool> unpublish(String remoteId) => _simplePost('/notes/$remoteId/unpublish');

  /// Like / unlike a published post. Returns the fresh like count, or null.
  static Future<({bool liked, int likesCount})?> toggleLike(String postId, bool currentlyLiked) async {
    try {
      final res = currentlyLiked
          ? await ApiService.delete('/notes/$postId/like')
          : await ApiService.post('/notes/$postId/like', {});
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        return (liked: d['liked'] as bool? ?? false, likesCount: d['likesCount'] as int? ?? 0);
      }
    } catch (e) {
      print('[NoteApiService] toggleLike error: $e');
    }
    return null;
  }

  static Future<bool> bookmark(String postId) => _simplePost('/notes/$postId/bookmark');
  static Future<bool> removeBookmark(String postId) => _simpleDelete('/notes/$postId/bookmark');

  static Future<List<FeedPost>> fetchBookmarks() async {
    try {
      final res = await ApiService.get('/notes/bookmarks');
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body)['posts'] ?? [];
        return list.map((e) => FeedPost.fromJson(e)).toList();
      }
    } catch (e) {
      print('[NoteApiService] fetchBookmarks error: $e');
    }
    return [];
  }

  // ─── Threaded comments ────────────────────────────────────
  /// Add a comment or a reply (pass [parentId] for a reply).
  static Future<Comment?> addThreadedComment(
    String remoteId,
    String text, {
    String? ownerUid,
    String? parentId,
  }) async {
    try {
      final res = await ApiService.post('/notes/$remoteId/comments', {
        'text': text,
        'noteOwnerUid': ownerUid,
        'parentId': parentId,
      });
      if (res.statusCode == 201) return Comment.fromJson(jsonDecode(res.body));
    } catch (e) {
      print('[NoteApiService] addThreadedComment error: $e');
    }
    return null;
  }

  static Future<({bool liked, int likesCount})?> toggleCommentLike(
      String remoteId, String commentId, {String? ownerUid}) async {
    try {
      final q = ownerUid != null ? '?ownerUid=$ownerUid' : '';
      final res = await ApiService.post('/notes/$remoteId/comments/$commentId/like$q', {});
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        return (liked: d['liked'] as bool? ?? false, likesCount: d['likesCount'] as int? ?? 0);
      }
    } catch (e) {
      print('[NoteApiService] toggleCommentLike error: $e');
    }
    return null;
  }

  static Future<bool> deleteComment(String remoteId, String commentId, {String? ownerUid}) async {
    try {
      final q = ownerUid != null ? '?ownerUid=$ownerUid' : '';
      final res = await ApiService.delete('/notes/$remoteId/comments/$commentId$q');
      return res.statusCode == 200;
    } catch (e) {
      print('[NoteApiService] deleteComment error: $e');
      return false;
    }
  }

  // ─── Small shared helpers ─────────────────────────────────
  static Future<List<Note>> _fetchList(String path) async {
    try {
      final res = await ApiService.get(path);
      if (res.statusCode == 200) {
        final List list = jsonDecode(res.body)['notes'] ?? [];
        return list.map((e) => _parseNoteJson(e)).toList();
      }
    } catch (e) {
      print('[NoteApiService] _fetchList($path) error: $e');
    }
    return [];
  }

  static Future<bool> _simplePost(String path) async {
    try {
      final res = await ApiService.post(path, {});
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      print('[NoteApiService] POST $path error: $e');
      return false;
    }
  }

  static Future<bool> _simpleDelete(String path) async {
    try {
      final res = await ApiService.delete(path);
      return res.statusCode == 200;
    } catch (e) {
      print('[NoteApiService] DELETE $path error: $e');
      return false;
    }
  }

  static List<String> _decodeCollaborators(Object? raw) {
    if (raw == null) return const [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } catch (_) {}
    }
    return const [];
  }

  static Note _parseNoteJson(Map<String, dynamic> json) {
    return Note(
      id: json['localId'] as int? ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: json['title'] as String?,
      content: json['content'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      editedAt: json['editedAt'] != null ? DateTime.tryParse(json['editedAt'] as String) : null,
      pinned: json['pinned'] as bool? ?? false,
      remoteId: json['id'] as String?,
      isChecklist: json['isChecklist'] as bool? ?? false,
      color: json['color'] as int? ?? 0,
      folderId: json['folderId'] as int?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      collaborators: _decodeCollaborators(json['collaborators']),
      sharedExternally: json['sharedExternally'] == 1 || json['sharedExternally'] == true,
      isPublished: json['isPublished'] as bool? ?? false,
      likesCount: json['likesCount'] as int? ?? 0,
      commentsCount: json['commentsCount'] as int? ?? 0,
      archived: json['archived'] as bool? ?? false,
      deleted: json['deleted'] as bool? ?? false,
      // Note: tagIds are handled locally and mapped in sync services
    );
  }
}
