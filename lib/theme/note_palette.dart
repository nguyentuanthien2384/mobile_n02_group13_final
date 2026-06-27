import 'dart:convert';
import 'package:flutter/material.dart';

/// Bảng màu thẻ ghi chú, lấy cảm hứng từ thiết kế "My Notes".
class NotePalette {
  // Màu thẻ cho My Notes / Reminder
  static const List<Color> cardColors = [
    Color(0xFFF28B82), // đỏ/coral
    Color(0xFFFDD663), // vàng
    Color(0xFFA7E26C), // xanh lá
    Color(0xFF7FE0D4), // teal
    Color(0xFFAECBFA), // xanh dương
    Color(0xFFF7A8D8), // hồng
  ];

  // Màu cho sticky note (Shopping List) – tông cam giấy nhớ
  static const Color shoppingPaper = Color(0xFFF6A623);
  static const Color shoppingPaperAlt = Color(0xFFF7B955);

  /// Chuyển giá trị color (int ARGB) đã lưu thành Color.
  /// 0 = mặc định theo loại note.
  static Color resolve(int value, {Color fallback = const Color(0xFFFDD663)}) {
    if (value == 0) return fallback;
    return Color(value);
  }

  /// Màu chữ tương phản (đen/trắng) dựa trên độ sáng nền.
  static Color textOn(Color bg) {
    return bg.computeLuminance() > 0.6 ? Colors.black87 : Colors.white;
  }
}

/// Định dạng ngày kiểu tiếng Việt: "Chủ Nhật, 28, thg 5 2023 12:44 CH".
String formatVietnameseDate(DateTime dt) {
  const weekdays = [
    'Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'
  ];
  final wd = weekdays[(dt.weekday - 1) % 7];
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final ampm = dt.hour < 12 ? 'SA' : 'CH';
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$wd, ${dt.day}, thg ${dt.month} ${dt.year} $hour12:$mm $ampm';
}

/// Lấy văn bản thuần từ content. Hỗ trợ cả Quill delta (JSON) lẫn text thường.
String plainTextFromContent(String? content) {
  if (content == null || content.trim().isEmpty) return '';
  final c = content.trim();
  if (c.startsWith('[') || c.startsWith('{')) {
    try {
      final data = jsonDecode(c);
      if (data is List) {
        final buf = StringBuffer();
        for (final op in data) {
          if (op is Map && op['insert'] is String) buf.write(op['insert']);
        }
        return buf.toString().trim();
      }
    } catch (_) {}
  }
  return c;
}
