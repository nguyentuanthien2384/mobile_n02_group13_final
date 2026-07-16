import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // BASE URL cho API. Đổi thành URL Render.com của bạn sau khi deploy.
  // Trên Emulator Android, 10.0.2.2 là localhost của máy tính.
  static const String defaultBaseUrl = 'http://10.0.2.2:3000/api';
  static String _baseUrl = defaultBaseUrl;

  static String get baseUrl => _baseUrl;

  /// Loads the server selected in Settings before any sync/share request.
  static Future<void> loadConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('api_base_url')?.trim();
    if (saved != null && saved.isNotEmpty) {
      _baseUrl = _normaliseBaseUrl(saved);
    }
  }

  static Future<void> setBaseUrl(String value) async {
    _baseUrl = _normaliseBaseUrl(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', _baseUrl);
  }

  static String _normaliseBaseUrl(String value) {
    final trimmed = value.trim().replaceFirst(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) return defaultBaseUrl;
    return trimmed.endsWith('/api') ? trimmed : '$trimmed/api';
  }

  static Future<bool> isServerReachable() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, String>> _getHeaders({
    String? expectedUserId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (expectedUserId != null && user?.uid != expectedUserId) {
      throw StateError('Authentication session changed during request');
    }
    if (user == null) {
      return {'Content-Type': 'application/json; charset=UTF-8'};
    }
    final token = await user.getIdToken();
    if (expectedUserId != null &&
        FirebaseAuth.instance.currentUser?.uid != expectedUserId) {
      throw StateError('Authentication session changed during request');
    }
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> get(
    String endpoint, {
    String? expectedUserId,
  }) async {
    final headers = await _getHeaders(expectedUserId: expectedUserId);
    return await http.get(Uri.parse('$_baseUrl$endpoint'), headers: headers);
  }

  static Future<http.Response> post(
    String endpoint,
    Map<String, dynamic> body, {
    String? expectedUserId,
  }) async {
    final headers = await _getHeaders(expectedUserId: expectedUserId);
    return await http.post(
      Uri.parse('$_baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
  }

  static Future<http.Response> put(
    String endpoint,
    Map<String, dynamic> body, {
    String? expectedUserId,
  }) async {
    final headers = await _getHeaders(expectedUserId: expectedUserId);
    return await http.put(
      Uri.parse('$_baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
  }

  static Future<http.Response> delete(
    String endpoint, {
    String? expectedUserId,
  }) async {
    final headers = await _getHeaders(expectedUserId: expectedUserId);
    return await http.delete(Uri.parse('$_baseUrl$endpoint'), headers: headers);
  }

  // Upload file image
  static Future<String?> uploadImage(File file) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      final token = await user.getIdToken();

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/upload/image'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(await http.MultipartFile.fromPath('image', file.path));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['url'] as String?;
      } else {
        print('[ApiService] Upload image failed: ${response.body}');
        return null;
      }
    } catch (e) {
      print('[ApiService] Error uploading image: $e');
      return null;
    }
  }

  // Upload avatar
  static Future<String?> uploadAvatar(File file) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      final token = await user.getIdToken();

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/upload/avatar'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(await http.MultipartFile.fromPath('avatar', file.path));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['url'] as String?;
      } else {
        print('[ApiService] Upload avatar failed: ${response.body}');
        return null;
      }
    } catch (e) {
      print('[ApiService] Error uploading avatar: $e');
      return null;
    }
  }
}
