import 'dart:convert';
import 'package:todoapp/class/comment.dart';
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
      // Note: tagIds are handled locally and mapped in sync services
    );
  }
}
