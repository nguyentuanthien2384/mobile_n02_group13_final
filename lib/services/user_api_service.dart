import 'dart:convert';
import 'api_service.dart';

class UserApiService {
  static Future<Map<String, dynamic>?> fetchProfile() async {
    try {
      final res = await ApiService.get('/users/profile');
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('[UserApiService] fetchProfile error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> updateProfile({
    String? displayName,
    String? bio,
    Map<String, dynamic>? settings,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (displayName != null) body['displayName'] = displayName;
      if (bio != null) body['bio'] = bio;
      if (settings != null) body['settings'] = settings;

      final res = await ApiService.put('/users/profile', body);
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('[UserApiService] updateProfile error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> searchUser(String email) async {
    try {
      final res = await ApiService.get('/users/search?email=${Uri.encodeComponent(email)}');
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('[UserApiService] searchUser error: $e');
      return null;
    }
  }
}
