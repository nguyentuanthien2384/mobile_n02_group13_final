import 'package:sqflite/sqflite.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/theme/note_palette.dart';

/// Nạp dữ liệu mẫu vào SQLite cục bộ trong lần chạy đầu (khi chưa có ghi chú).
/// Nhờ vậy mở app lên là thấy ngay nội dung ở cả 3 chế độ.
class SampleData {
  static Future<void> seedIfEmpty(Database db) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM notes'),
    ) ?? 0;
    if (count > 0) return; // đã có dữ liệu, không seed nữa

    final now = DateTime.now();
    DateTime ago(int h) => now.subtract(Duration(hours: h, minutes: h * 7 % 60));

    final c = NotePalette.cardColors; // [đỏ, vàng, lá, teal, dương, hồng]

    final samples = <Note>[
      // ── MY NOTES ──
      Note(id: 0, noteType: 'note', color: c[1].toARGB32(),
          title: 'SINH NHẬT CÁ',
          content: '@@ Hôm đấy bị mắng sợ ZL 😔 nhưng mà vui phết, cả nhóm tụ tập ăn uống tới khuya.',
          createdAt: ago(2), editedAt: ago(2)),
      Note(id: 0, noteType: 'note', color: c[4].toARGB32(),
          title: 'ĐI ĐẠI TỪ NÀY',
          content: 'Mệt nhưng mà cũng vui phết !!! Chuyến đi đáng nhớ với hội bạn thân.',
          createdAt: ago(5), editedAt: ago(5)),
      Note(id: 0, noteType: 'note', color: c[2].toARGB32(),
          title: 'ĐI ĂN NƯỚNG NÀY',
          content: 'Ngon thiệc! Quán nướng mới mở gần nhà, giá hợp lý, không gian ổn.',
          createdAt: ago(9), editedAt: ago(9)),
      Note(id: 0, noteType: 'note', color: c[0].toARGB32(),
          title: 'PHƯỢT NÚI',
          content: 'Săn mây trên đỉnh, cắm trại qua đêm. Nhớ mang theo áo ấm và đèn pin.',
          createdAt: ago(20), editedAt: ago(20)),
      Note(id: 0, noteType: 'note', color: c[5].toARGB32(),
          title: 'KẾ HOẠCH HỌC TẬP',
          content: 'Mỗi ngày 1 giờ tiếng Anh, 1 giờ lập trình. Cuối tuần ôn lại.',
          createdAt: ago(30), editedAt: ago(30)),
      Note(id: 0, noteType: 'note', color: c[3].toARGB32(),
          title: 'PHIM CẦN XEM',
          content: 'Danh sách phim hay bạn bè giới thiệu, để dành cuối tuần xem dần.',
          createdAt: ago(40), editedAt: ago(40)),

      // ── REMINDER ──
      Note(id: 0, noteType: 'reminder', color: c[0].toARGB32(),
          title: 'coding', content: 'Hoàn thành bài tập Flutter trước 9h tối.',
          createdAt: ago(1), editedAt: ago(1)),
      Note(id: 0, noteType: 'reminder', color: c[3].toARGB32(),
          title: 'gaming', content: 'Hẹn team chơi game lúc 8h.',
          createdAt: ago(3), editedAt: ago(3)),
      Note(id: 0, noteType: 'reminder', color: c[2].toARGB32(),
          title: 'shopping', content: 'Đi siêu thị mua đồ cuối tuần.',
          createdAt: ago(6), editedAt: ago(6)),
      Note(id: 0, noteType: 'reminder', color: c[1].toARGB32(),
          title: 'họp nhóm', content: 'Họp dự án lúc 14h chiều thứ Tư.',
          createdAt: ago(12), editedAt: ago(12)),

      // ── SHOPPING LIST ──
      Note(id: 0, noteType: 'shopping', color: NotePalette.shoppingPaper.toARGB32(),
          title: 'mua thịt bò', price: '30k', content: '500g thịt bò để làm bún bò.',
          createdAt: ago(1), editedAt: ago(1)),
      Note(id: 0, noteType: 'shopping', color: NotePalette.shoppingPaper.toARGB32(),
          title: 'mua cá', price: '30k', content: 'Cá basa hoặc cá hồi.',
          createdAt: ago(2), editedAt: ago(2)),
      Note(id: 0, noteType: 'shopping', color: NotePalette.shoppingPaperAlt.toARGB32(),
          title: 'rau củ', price: '20k', content: 'Cà rốt, cải xanh, hành lá.',
          createdAt: ago(4), editedAt: ago(4)),
      Note(id: 0, noteType: 'shopping', color: NotePalette.shoppingPaperAlt.toARGB32(),
          title: 'trái cây', price: '50k', content: 'Táo, cam, chuối cho cả tuần.',
          createdAt: ago(7), editedAt: ago(7)),
    ];

    for (final n in samples) {
      await NoteDatabase.insertNote(db, n);
    }
  }
}
