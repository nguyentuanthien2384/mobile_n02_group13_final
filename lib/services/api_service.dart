import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ApiService {
  // BASE URL cho API. Đổi thành URL Render.com của bạn sau khi deploy.
  // Trên Emulator Android, 10.0.2.2 là localhost của máy tính.
  static const String baseUrl = 'http://10.0.2.2:3000/api';

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
    return await http.get(Uri.parse('$baseUrl$endpoint'), headers: headers);
  }

  static Future<http.Response> post(
    String endpoint,
    Map<String, dynamic> body, {
    String? expectedUserId,
  }) async {
    final headers = await _getHeaders(expectedUserId: expectedUserId);
    return await http.post(
      Uri.parse('$baseUrl$endpoint'),
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
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
  }

  static Future<http.Response> delete(
    String endpoint, {
    String? expectedUserId,
  }) async {
    final headers = await _getHeaders(expectedUserId: expectedUserId);
    return await http.delete(Uri.parse('$baseUrl$endpoint'), headers: headers);
  }

  // Upload file image
  static Future<String?> uploadImage(File file) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      final token = await user.getIdToken();

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/upload/image'),
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
        Uri.parse('$baseUrl/upload/avatar'),
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
