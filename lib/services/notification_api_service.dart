import 'dart:convert';
import 'package:todoapp/class/app_notification.dart';
import 'api_service.dart';

/// Client for the /api/notifications/* endpoints.
class NotificationApiService {
  static Future<List<AppNotification>> fetch({int limit = 30}) async {
    try {
      final res = await ApiService.get('/notifications?limit=$limit');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List list = data['notifications'] ?? [];
        return list.map((e) => AppNotification.fromJson(e)).toList();
      }
    } catch (e) {
      print('[NotificationApiService] fetch error: $e');
    }
    return [];
  }

  static Future<int> unreadCount() async {
    try {
      final res = await ApiService.get('/notifications/unread-count');
      if (res.statusCode == 200) return jsonDecode(res.body)['count'] as int? ?? 0;
    } catch (e) {
      print('[NotificationApiService] unreadCount error: $e');
    }
    return 0;
  }

  static Future<bool> markRead(String id) async {
    try {
      final res = await ApiService.post('/notifications/$id/read', {});
      return res.statusCode == 200;
    } catch (e) {
      print('[NotificationApiService] markRead error: $e');
      return false;
    }
  }

  static Future<bool> markAllRead() async {
    try {
      final res = await ApiService.post('/notifications/read-all', {});
      return res.statusCode == 200;
    } catch (e) {
      print('[NotificationApiService] markAllRead error: $e');
      return false;
    }
  }

  static Future<bool> delete(String id) async {
    try {
      final res = await ApiService.delete('/notifications/$id');
      return res.statusCode == 200;
    } catch (e) {
      print('[NotificationApiService] delete error: $e');
      return false;
    }
  }
}
