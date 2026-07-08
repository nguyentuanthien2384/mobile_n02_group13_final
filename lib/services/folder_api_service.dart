import 'dart:convert';
import 'package:todoapp/class/folder.dart';
import 'api_service.dart';

class FolderApiService {
  static Folder _parseFolderJson(
    Map<String, dynamic> item, {
    int? fallbackLocalId,
  }) {
    return Folder.fromMap({
      'id':
          item['localId'] as int? ??
          fallbackLocalId ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'name': item['name'],
      'color': item['color'],
      'icon': item['icon'],
      'createdAt': item['createdAt'],
      'remoteId': item['id'],
    });
  }

  static Future<List<Folder>> fetchFolders() async {
    try {
      final res = await ApiService.get('/folders');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List list = data['folders'] ?? [];
        return list.map((item) => _parseFolderJson(item)).toList();
      }
      return [];
    } catch (e) {
      print('[FolderApiService] fetchFolders error: $e');
      return [];
    }
  }

  static Future<Folder?> createFolder(Folder folder) async {
    try {
      final body = folder.toMap();
      body['localId'] = folder.id;
      final res = await ApiService.post('/folders', body);
      if (res.statusCode == 201) {
        final data = jsonDecode(res.body);
        return _parseFolderJson(data, fallbackLocalId: folder.id);
      }
      return null;
    } catch (e) {
      print('[FolderApiService] createFolder error: $e');
      return null;
    }
  }

  static Future<Folder?> updateFolder(Folder folder) async {
    if (folder.remoteId == null) return null;
    try {
      final body = folder.toMap();
      body['localId'] = folder.id;
      final res = await ApiService.put('/folders/${folder.remoteId}', body);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return _parseFolderJson(data, fallbackLocalId: folder.id);
      }
      return null;
    } catch (e) {
      print('[FolderApiService] updateFolder error: $e');
      return null;
    }
  }

  static Future<bool> deleteFolder(
    String remoteId, {
    int? localFolderId,
  }) async {
    try {
      final suffix = localFolderId == null
          ? ''
          : '?localFolderId=$localFolderId';
      final res = await ApiService.delete('/folders/$remoteId$suffix');
      return res.statusCode == 200;
    } catch (e) {
      print('[FolderApiService] deleteFolder error: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> shareFolder({
    required String remoteId,
    required int localFolderId,
    required String email,
    required String permission,
  }) async {
    try {
      final res = await ApiService.post('/folders/$remoteId/share', {
        'email': email,
        'permission': permission,
        'localFolderId': localFolderId,
      });
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('[FolderApiService] shareFolder error: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchShares(String remoteId) async {
    try {
      final res = await ApiService.get('/folders/$remoteId/shares');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List list = data['shares'] ?? [];
        return list.map((e) => e as Map<String, dynamic>).toList();
      }
      return [];
    } catch (e) {
      print('[FolderApiService] fetchShares error: $e');
      return [];
    }
  }

  static Future<bool> revokeShare(
    String remoteId,
    String targetUid,
    int localFolderId,
  ) async {
    try {
      final res = await ApiService.delete(
        '/folders/$remoteId/share/$targetUid?localFolderId=$localFolderId',
      );
      return res.statusCode == 200;
    } catch (e) {
      print('[FolderApiService] revokeShare error: $e');
      return false;
    }
  }
}
