import 'dart:convert';
import 'package:todoapp/class/folder.dart';
import 'api_service.dart';

class FolderApiService {
  static Future<List<Folder>> fetchFolders() async {
    try {
      final res = await ApiService.get('/folders');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List list = data['folders'] ?? [];
        return list.map((item) => Folder.fromMap({
          'id': item['localId'] as int? ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'name': item['name'],
          'color': item['color'],
          'icon': item['icon'],
          'createdAt': item['createdAt'],
          'remoteId': item['id'],
        })).toList();
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
        return Folder.fromMap({
          'id': data['localId'] as int? ?? folder.id,
          'name': data['name'],
          'color': data['color'],
          'icon': data['icon'],
          'createdAt': data['createdAt'],
          'remoteId': data['id'],
        });
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
        return Folder.fromMap({
          'id': data['localId'] as int? ?? folder.id,
          'name': data['name'],
          'color': data['color'],
          'icon': data['icon'],
          'createdAt': data['createdAt'],
          'remoteId': data['id'],
        });
      }
      return null;
    } catch (e) {
      print('[FolderApiService] updateFolder error: $e');
      return null;
    }
  }

  static Future<bool> deleteFolder(String remoteId) async {
    try {
      final res = await ApiService.delete('/folders/$remoteId');
      return res.statusCode == 200;
    } catch (e) {
      print('[FolderApiService] deleteFolder error: $e');
      return false;
    }
  }
}
