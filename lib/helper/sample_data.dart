import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/class/tag.dart';
import 'package:todoapp/class/folder.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/database/tag_database.dart';
import 'package:todoapp/database/folder_database.dart';
import 'package:todoapp/theme/note_palette.dart';

/// Nạp dữ liệu mẫu vào SQLite cục bộ trong lần chạy đầu (khi chưa có ghi chú).
///
/// Bao phủ toàn bộ các chức năng lưu trữ cục bộ của ứng dụng để mở app lên
/// là thấy ngay nội dung ở mọi màn hình:
///   • My Notes / Reminder / Shopping (3 chế độ ở màn hình chính)
///   • Ghi chú checklist (todo list)
///   • Thư mục (Folder) + ghi chú thuộc thư mục
///   • Tag / nhãn + liên kết note ↔ tag
///   • Ghi chú Ghim (pinned) và Yêu thích (favorite)
///   • Ghi chú có nhắc nhở (reminderAt) -> hiện trong Thống kê
///   • Thùng rác (một ghi chú đã xóa mềm)
class SampleData {
  static Future<void> seedIfEmpty(Database db) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM notes'),
    ) ?? 0;
    if (count > 0) return; // đã có dữ liệu, không seed lại nữa

    final now = DateTime.now();
    DateTime ago(int h) => now.subtract(Duration(hours: h, minutes: h * 7 % 60));
    DateTime ahead(int h) => now.add(Duration(hours: h));

    final c = NotePalette.cardColors; // [đỏ, vàng, lá, teal, dương, hồng]

    // ─────────────────────────── TAGS ───────────────────────────
    // Tạo tag trước để lấy id, sau đó gắn vào note.
    final tagIds = <String, int>{};
    for (final name in const ['Cá nhân', 'Công việc', 'Học tập', 'Du lịch', 'Quan trọng']) {
      final id = await TagDatabase.insertTag(
        db,
        Tag(id: 0, name: name, createdAt: now),
      );
      tagIds[name] = id;
    }

    // ────────────────────────── FOLDERS ─────────────────────────
    final folderIds = <String, int>{};
    final folders = <List<Object>>[
      // [name, colorInt, icon]
      ['Ghi chú cá nhân', 0xFF42A5F5, 'folder'],
      ['Dự án Flutter', 0xFF66BB6A, 'work'],
      ['Ý tưởng', 0xFFFFA726, 'lightbulb'],
    ];
    for (final f in folders) {
      final id = await FolderDatabase.insertFolder(
        db,
        Folder(
          id: 0,
          name: f[0] as String,
          color: f[1] as int,
          icon: f[2] as String,
          createdAt: now,
        ),
      );
      folderIds[f[0] as String] = id;
    }

    // ─────────────────────────── NOTES ──────────────────────────
    // Ghi chú thường có reminderAt sẽ được set sau khi insert (vì toMap()
    // không lưu reminderAt — nó được quản lý riêng qua NoteDatabase.setReminder).

    // ── MY NOTES ──
    final myNotes = <Note>[
      Note(
        id: 0, noteType: 'note', color: c[1].toARGB32(),
        title: 'SINH NHẬT CÁ',
        content: 'Hôm đấy cả nhóm tụ tập ăn uống tới khuya, vui phết! Nhớ mang quà lần sau.',
        createdAt: ago(2), editedAt: ago(2),
        pinned: true, // ghim lên đầu
        isFavorite: true, // đánh dấu yêu thích
        folderId: folderIds['Ghi chú cá nhân'],
        tagIds: [tagIds['Cá nhân']!, tagIds['Quan trọng']!],
      ),
      Note(
        id: 0, noteType: 'note', color: c[4].toARGB32(),
        title: 'ĐI ĐÀ LẠT',
        content: 'Mệt nhưng mà cũng vui phết! Chuyến đi đáng nhớ với hội bạn thân.',
        createdAt: ago(5), editedAt: ago(5),
        isFavorite: true,
        folderId: folderIds['Ghi chú cá nhân'],
        tagIds: [tagIds['Du lịch']!],
      ),
      Note(
        id: 0, noteType: 'note', color: c[2].toARGB32(),
        title: 'ĐI ĂN NƯỚNG',
        content: 'Ngon thiệc! Quán nướng mới mở gần nhà, giá hợp lý, không gian ổn.',
        createdAt: ago(9), editedAt: ago(9),
        tagIds: [tagIds['Cá nhân']!],
      ),
      Note(
        id: 0, noteType: 'note', color: c[0].toARGB32(),
        title: 'PHƯỢT NÚI',
        content: 'Săn mây trên đỉnh, cắm trại qua đêm. Nhớ mang theo áo ấm và đèn pin.',
        createdAt: ago(20), editedAt: ago(20),
        tagIds: [tagIds['Du lịch']!],
      ),
      Note(
        id: 0, noteType: 'note', color: c[5].toARGB32(),
        title: 'KẾ HOẠCH HỌC TẬP',
        content: 'Mỗi ngày 1 giờ tiếng Anh, 1 giờ lập trình. Cuối tuần ôn lại toàn bộ.',
        createdAt: ago(30), editedAt: ago(30),
        pinned: true,
        folderId: folderIds['Dự án Flutter'],
        tagIds: [tagIds['Học tập']!, tagIds['Quan trọng']!],
      ),
      Note(
        id: 0, noteType: 'note', color: c[3].toARGB32(),
        title: 'PHIM CẦN XEM',
        content: 'Danh sách phim hay bạn bè giới thiệu, để dành cuối tuần xem dần.',
        createdAt: ago(40), editedAt: ago(40),
        tagIds: [tagIds['Cá nhân']!],
      ),
    ];

    // ── CHECKLIST (todo list) ──
    // content là JSON [{text, done}] đúng định dạng màn hình TodoListScreen dùng.
    String checklist(List<List<Object>> items) => jsonEncode(
          items.map((e) => {'text': e[0], 'done': e[1]}).toList(),
        );

    final checklistNotes = <Note>[
      Note(
        id: 0, noteType: 'note', color: c[3].toARGB32(),
        title: 'Việc cần làm hôm nay',
        isChecklist: true,
        content: checklist([
          ['Học bài Flutter', true],
          ['Làm bài tập Provider', false],
          ['Đọc tài liệu Firebase', false],
          ['Tập thể dục 30 phút', true],
        ]),
        createdAt: ago(3), editedAt: ago(1),
        folderId: folderIds['Dự án Flutter'],
        tagIds: [tagIds['Công việc']!],
      ),
      Note(
        id: 0, noteType: 'note', color: c[2].toARGB32(),
        title: 'Chuẩn bị đồ án',
        isChecklist: true,
        content: checklist([
          ['Hoàn thiện màn hình chính', true],
          ['Viết báo cáo', false],
          ['Chuẩn bị slide thuyết trình', false],
        ]),
        createdAt: ago(8), editedAt: ago(8),
        folderId: folderIds['Dự án Flutter'],
        tagIds: [tagIds['Học tập']!, tagIds['Quan trọng']!],
      ),
    ];

    // ── REMINDER ── (đặt reminderAt sau khi insert)
    final reminderNotes = <Note>[
      Note(
        id: 0, noteType: 'reminder', color: c[0].toARGB32(),
        title: 'coding', content: 'Hoàn thành bài tập Flutter trước 9h tối.',
        createdAt: ago(1), editedAt: ago(1),
        tagIds: [tagIds['Công việc']!],
      ),
      Note(
        id: 0, noteType: 'reminder', color: c[3].toARGB32(),
        title: 'gaming', content: 'Hẹn team chơi game lúc 8h.',
        createdAt: ago(3), editedAt: ago(3),
      ),
      Note(
        id: 0, noteType: 'reminder', color: c[2].toARGB32(),
        title: 'shopping', content: 'Đi siêu thị mua đồ cuối tuần.',
        createdAt: ago(6), editedAt: ago(6),
      ),
      Note(
        id: 0, noteType: 'reminder', color: c[1].toARGB32(),
        title: 'họp nhóm', content: 'Họp dự án lúc 14h chiều thứ Tư.',
        createdAt: ago(12), editedAt: ago(12),
        tagIds: [tagIds['Công việc']!, tagIds['Quan trọng']!],
      ),
    ];
    // Thời điểm nhắc tương ứng cho từng reminder ở trên.
    final reminderTimes = <DateTime>[ahead(2), ahead(5), ahead(26), ahead(48)];

    // ── SHOPPING LIST ──
    final shoppingNotes = <Note>[
      Note(
        id: 0, noteType: 'shopping', color: NotePalette.shoppingPaper.toARGB32(),
        title: 'mua thịt bò', price: '30k', content: '500g thịt bò để làm bún bò.',
        createdAt: ago(1), editedAt: ago(1),
      ),
      Note(
        id: 0, noteType: 'shopping', color: NotePalette.shoppingPaper.toARGB32(),
        title: 'mua cá', price: '30k', content: 'Cá basa hoặc cá hồi.',
        createdAt: ago(2), editedAt: ago(2),
      ),
      Note(
        id: 0, noteType: 'shopping', color: NotePalette.shoppingPaperAlt.toARGB32(),
        title: 'rau củ', price: '20k', content: 'Cà rốt, cải xanh, hành lá.',
        createdAt: ago(4), editedAt: ago(4),
      ),
      Note(
        id: 0, noteType: 'shopping', color: NotePalette.shoppingPaperAlt.toARGB32(),
        title: 'trái cây', price: '50k', content: 'Táo, cam, chuối cho cả tuần.',
        createdAt: ago(7), editedAt: ago(7),
      ),
    ];

    // Chèn tất cả note "còn hoạt động".
    for (final n in [...myNotes, ...checklistNotes, ...shoppingNotes]) {
      await NoteDatabase.insertNote(db, n);
    }
    // Chèn reminder + set thời điểm nhắc.
    for (var i = 0; i < reminderNotes.length; i++) {
      final id = await NoteDatabase.insertNote(db, reminderNotes[i]);
      await NoteDatabase.setReminder(db, id, reminderTimes[i]);
    }

    // ── THÙNG RÁC ── (một ghi chú đã xóa mềm để màn hình Trash có nội dung)
    final trashedId = await NoteDatabase.insertNote(
      db,
      Note(
        id: 0, noteType: 'note', color: c[5].toARGB32(),
        title: 'Ghi chú cũ đã xóa',
        content: 'Đây là ghi chú mẫu nằm trong thùng rác — bạn có thể khôi phục hoặc xóa hẳn.',
        createdAt: ago(72), editedAt: ago(72),
      ),
    );
    await NoteDatabase.softDelete(db, trashedId);
  }
}
