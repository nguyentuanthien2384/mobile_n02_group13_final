import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/helper/vietnamese_telex.dart';
import 'package:todoapp/screen/share_dialog.dart';
import 'package:todoapp/services/notification_service.dart';
import 'package:todoapp/services/note_api_service.dart';
import 'package:todoapp/theme/note_palette.dart';

/// Trình soạn ghi chú nền tối, có bảng chọn màu – giống thiết kế mẫu.
/// Dùng chung cho 3 loại: note / reminder / shopping.
class StickyEditorScreen extends StatefulWidget {
  final Note? note; // null = tạo mới
  final String noteType; // 'note' | 'reminder' | 'shopping'
  final int? folderId; // nếu != null: ghi chú mới sẽ được lưu vào thư mục này

  const StickyEditorScreen({
    super.key,
    this.note,
    this.noteType = 'note',
    this.folderId,
  });

  @override
  State<StickyEditorScreen> createState() => _StickyEditorScreenState();
}

class _StickyEditorScreenState extends State<StickyEditorScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _price = TextEditingController();
  late String _type;
  late Color _color;
  String? _imagePath;
  Database? _db;
  int? _noteId;
  DateTime? _reminderAt;
  String _reminderRepeat = 'none';
  int _reminderLeadMinutes = 0;

  @override
  void initState() {
    super.initState();
    _type = widget.note?.noteType ?? widget.noteType;
    _noteId = widget.note?.id;
    _title.text = widget.note?.title ?? '';
    _body.text = plainTextFromContent(widget.note?.content);
    _price.text = widget.note?.price ?? '';
    _imagePath = widget.note?.imagePath;
    _reminderAt = widget.note?.reminderAt;
    _reminderRepeat = widget.note?.reminderRepeat ?? 'none';
    _reminderLeadMinutes = widget.note?.reminderLeadMinutes ?? 0;
    final defColor = _type == 'reminder'
        ? const Color(0xFFA7E26C)
        : _type == 'shopping'
        ? NotePalette.shoppingPaper
        : NotePalette.cardColors[1];
    _color = (widget.note != null && widget.note!.color != 0)
        ? Color(widget.note!.color)
        : defColor;
    DatabaseHelper.database().then((d) => setState(() => _db = d));
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Chọn từ thư viện ảnh'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Chọn từ tệp / Download / Máy tính'),
              onTap: () => Navigator.pop(ctx, 'files'),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    String? sourcePath;
    try {
      if (source == 'gallery') {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          imageQuality: 80,
        );
        sourcePath = picked?.path;
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
        );
        sourcePath = result?.files.single.path;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không mở được trình chọn ảnh: $e')),
        );
      }
      return;
    }

    if (sourcePath == null) return; // người dùng hủy chọn

    // Sao chép ảnh vào thư mục dữ liệu của app để ảnh tồn tại lâu dài
    // (đường dẫn gốc từ cache/gallery có thể bị xóa sau này).
    try {
      final saved = await _persistImage(sourcePath);
      if (mounted) setState(() => _imagePath = saved);
    } catch (_) {
      if (mounted) setState(() => _imagePath = sourcePath);
    }
  }

  Future<String> _persistImage(String sourcePath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final imgDir = Directory('${appDir.path}/note_images');
    if (!await imgDir.exists()) {
      await imgDir.create(recursive: true);
    }
    final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'jpg';
    final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final destPath = '${imgDir.path}/$fileName';
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  void _removeImage() {
    setState(() => _imagePath = null);
  }

  Future<void> _pickReminderDateTime() async {
    final now = DateTime.now();
    final initial = _reminderAt?.isAfter(now) == true
        ? _reminderAt!
        : now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final chosen = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!chosen.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hãy chọn thời điểm trong tương lai.')),
      );
      return;
    }
    setState(() => _reminderAt = chosen);
  }

  String _formatReminder(DateTime value) {
    final local = MaterialLocalizations.of(context);
    return '${local.formatMediumDate(value)} · ${local.formatTimeOfDay(TimeOfDay.fromDateTime(value))}';
  }

  Future<void> _share() async {
    final note = await _persist();
    if (note == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hãy nhập nội dung trước khi chia sẻ')),
        );
      }
      return;
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => ShareDialog(noteRemoteId: note.remoteId, note: note),
    );
  }

  Future<void> _showVersionHistory() async {
    final remoteId = widget.note?.remoteId;
    final db = _db;
    if (remoteId == null || db == null || _noteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hãy đồng bộ ghi chú trước khi xem lịch sử.'),
        ),
      );
      return;
    }
    final versions = await NoteApiService.fetchVersions(remoteId);
    if (!mounted) return;
    if (versions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có phiên bản cũ nào.')),
      );
      return;
    }
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.history),
              title: Text('Lịch sử thay đổi'),
              subtitle: Text('Chọn một phiên bản để khôi phục'),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: versions.length,
                itemBuilder: (_, index) {
                  final version = versions[index];
                  final created = DateTime.tryParse(
                    version['createdAt']?.toString() ?? '',
                  );
                  final preview = version['content']?.toString().trim() ?? '';
                  return ListTile(
                    title: Text(
                      created == null
                          ? 'Phiên bản ${index + 1}'
                          : MaterialLocalizations.of(
                              context,
                            ).formatMediumDate(created),
                    ),
                    subtitle: Text(
                      preview.isEmpty ? '(Không có nội dung)' : preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.restore),
                    onTap: () => Navigator.pop(sheetContext, version),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final restored = await NoteApiService.restoreVersion(
      remoteId,
      selected['id']?.toString() ?? '',
    );
    if (!restored) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể khôi phục phiên bản này.')),
        );
      }
      return;
    }
    final current = await NoteDatabase.getNote(db, _noteId!);
    final updated = current.copyWith(
      title: selected['title']?.toString() ?? '',
      content: selected['content']?.toString() ?? '',
      editedAt: DateTime.now(),
    );
    await NoteDatabase.updateNote(db, updated);
    _title.text = updated.title ?? '';
    _body.text = plainTextFromContent(updated.content);
    if (!mounted) return;
    Provider.of<NoteProvider>(context, listen: false).updateNote(updated);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã khôi phục phiên bản đã chọn.')),
    );
  }

  Future<void> _delete() async {
    final db = _db;
    final note = widget.note;
    if (db == null || note == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa ghi chú?'),
        content: Text(
          (note.title ?? '').trim().isEmpty
              ? 'Ghi chú này sẽ được chuyển vào thùng rác.'
              : '"${note.title}" sẽ được chuyển vào thùng rác.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await NoteDatabase.softDelete(db, note.id);
    await NotificationService.instance.cancel(note.id);
    final notes = await NoteDatabase.getNotes(db);
    if (!mounted) return;
    Provider.of<NoteProvider>(context, listen: false).setNotes(notes);
    Navigator.pop(context, true);
  }

  /// Lưu ghi chú vào DB (tạo mới hoặc cập nhật) và trả về Note đã lưu.
  /// Trả về null nếu ghi chú trống. Không tự đóng màn hình.
  Future<Note?> _persist() async {
    final db = _db;
    if (db == null) return null;
    final title = _title.text.trim();
    if (title.isEmpty && _body.text.trim().isEmpty) return null;
    final now = DateTime.now();
    if (_noteId == null) {
      final note = Note(
        id: 0,
        title: title,
        content: _body.text.trim(),
        createdAt: now,
        editedAt: now,
        color: _color.toARGB32(),
        noteType: _type,
        price: _type == 'shopping' ? _price.text.trim() : null,
        imagePath: _type == 'note' ? _imagePath : null,
        folderId: widget.folderId,
        reminderAt: _type == 'reminder' ? _reminderAt : null,
        reminderRepeat: _type == 'reminder' ? _reminderRepeat : 'none',
        reminderLeadMinutes: _type == 'reminder' ? _reminderLeadMinutes : 0,
      );
      _noteId = await NoteDatabase.insertNote(db, note);
    } else {
      final existing = await NoteDatabase.getNote(db, _noteId!);
      final updated = existing.copyWith(
        title: title,
        content: _body.text.trim(),
        editedAt: now,
        color: _color.toARGB32(),
        noteType: _type,
        price: _type == 'shopping' ? _price.text.trim() : null,
      );
      // copyWith giữ ảnh cũ khi truyền null, nên gán trực tiếp để có thể GỠ ảnh.
      updated.imagePath = _type == 'note' ? _imagePath : null;
      updated.reminderAt = _type == 'reminder' ? _reminderAt : null;
      updated.reminderRepeat = _type == 'reminder' ? _reminderRepeat : 'none';
      updated.reminderLeadMinutes = _type == 'reminder'
          ? _reminderLeadMinutes
          : 0;
      await NoteDatabase.updateNote(db, updated);
    }
    final saved = await NoteDatabase.getNote(db, _noteId!);
    if (saved.reminderAt == null) {
      await NotificationService.instance.cancel(saved.id);
    } else {
      await NotificationService.instance.scheduleReminder(
        id: saved.id,
        title: (saved.title?.isNotEmpty ?? false) ? saved.title! : 'Nhắc việc',
        body: (saved.content?.isNotEmpty ?? false)
            ? saved.content!
            : 'Bạn có một việc cần thực hiện.',
        scheduledAt: saved.reminderAt!,
        repeat: saved.reminderRepeat,
        leadMinutes: saved.reminderLeadMinutes,
      );
    }
    // Đồng bộ lại provider để các màn khác cập nhật.
    final notes = await NoteDatabase.getNotes(db);
    if (mounted) {
      Provider.of<NoteProvider>(context, listen: false).setNotes(notes);
    }
    return saved;
  }

  Future<void> _save() async {
    if (_db == null) return;
    if (_title.text.trim().isEmpty && _body.text.trim().isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    await _persist();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF6E6E6E),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black),
        actions: [
          Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: vietnameseInputEnabled,
              builder: (context, enabled, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TextButton(
                  onPressed: () => vietnameseInputEnabled.value = !enabled,
                  style: TextButton.styleFrom(
                    backgroundColor: enabled
                        ? Colors.black
                        : Colors.grey.shade300,
                    foregroundColor: enabled ? Colors.white : Colors.black54,
                    minimumSize: const Size(44, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    enabled ? 'VI' : 'EN',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _share,
            icon: const Icon(Icons.ios_share, color: Colors.black),
            tooltip: 'Chia sẻ ra ứng dụng khác',
          ),
          if (widget.note != null)
            IconButton(
              onPressed: _showVersionHistory,
              icon: const Icon(Icons.history, color: Colors.black),
              tooltip: 'Lịch sử thay đổi',
            ),
          if (widget.note != null)
            IconButton(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Xóa ghi chú',
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _save,
              style: TextButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
              ),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 14),
              Text(
                formatVietnameseDate(widget.note?.createdAt ?? DateTime.now()),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              // Tiêu đề
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TextField(
                  controller: _title,
                  autofocus: widget.note == null,
                  inputFormatters: const [VietnameseTelexFormatter()],
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.next,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Note Title',
                    hintStyle: TextStyle(color: Colors.white60),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white54),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (_type == 'note') _buildNoteBody() else _buildStickyBody(),
              if (_type == 'reminder') ...[
                const SizedBox(height: 16),
                _buildReminderSettings(),
              ],
              const SizedBox(height: 28),
              Text(
                'Click me',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              _buildColorPicker(),
              const SizedBox(height: 16),
              if (_type == 'note') _buildAddImage(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // Thân ghi chú thường: vùng nhập + 2 thanh màu dọc 2 bên
  Widget _buildNoteBody() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _verticalBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  if (_imagePath != null && _imagePath!.isNotEmpty) ...[
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(_imagePath!),
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Material(
                            color: Colors.black54,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _removeImage,
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _body,
                    autofocus: widget.note != null,
                    inputFormatters: const [VietnameseTelexFormatter()],
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.newline,
                    maxLines: 10,
                    minLines: 6,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.4,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Type your note here...',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _verticalBar(),
        ],
      ),
    );
  }

  Widget _verticalBar() => Container(
    width: 5,
    height: 220,
    decoration: BoxDecoration(
      color: _color,
      borderRadius: BorderRadius.circular(4),
    ),
  );

  // Thân reminder/shopping: ô giấy nhớ màu (có ghim với reminder), kèm giá nếu shopping
  Widget _buildStickyBody() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 230),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _color,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(2, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            if (_type == 'reminder')
              const Text('📌', style: TextStyle(fontSize: 30)),
            const SizedBox(height: 8),
            if (_type == 'shopping')
              TextField(
                controller: _price,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'Giá (vd: 30k)',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
              ),
            TextField(
              controller: _body,
              autofocus: widget.note != null && _type != 'shopping',
              inputFormatters: const [VietnameseTelexFormatter()],
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.newline,
              textAlign: TextAlign.center,
              maxLines: 6,
              minLines: 3,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText: _type == 'reminder'
                    ? 'Nội dung nhắc nhở...'
                    : 'Ghi chú mua sắm...',
                hintStyle: const TextStyle(color: Colors.white70),
                border: InputBorder.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorPicker() {
    final colors = _type == 'note'
        ? NotePalette.cardColors
        : const [
            Color(0xFFF28B82),
            Color(0xFFFDD663),
            Color(0xFFA7E26C),
            Color(0xFF7FE0D4),
          ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ...colors.map(
          (c) => GestureDetector(
            onTap: () => setState(() => _color = c),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _color.toARGB32() == c.toARGB32()
                      ? Colors.white
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: _color.toARGB32() == c.toARGB32()
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _type == 'note' ? 'Pick color' : 'Pick your\nsticky color',
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildReminderSettings() {
    const repeatLabels = {
      'none': 'Không lặp lại',
      'daily': 'Lặp lại hằng ngày',
      'weekly': 'Lặp lại hằng tuần',
    };
    const leadLabels = {
      0: 'Đúng giờ',
      5: 'Trước 5 phút',
      15: 'Trước 15 phút',
      30: 'Trước 30 phút',
      60: 'Trước 1 giờ',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _pickReminderDateTime,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white70),
                ),
                icon: const Icon(Icons.notifications_active_outlined),
                label: Text(
                  _reminderAt == null
                      ? 'Đặt thời gian nhắc'
                      : _formatReminder(_reminderAt!),
                ),
              ),
            ),
            if (_reminderAt != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() => _reminderAt = null),
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  icon: const Icon(Icons.notifications_off_outlined, size: 18),
                  label: const Text('Bỏ nhắc'),
                ),
              ),
            DropdownButtonFormField<String>(
              value: _reminderRepeat,
              dropdownColor: const Color(0xFF555555),
              style: const TextStyle(color: Colors.white),
              iconEnabledColor: Colors.white,
              decoration: const InputDecoration(
                labelText: 'Lặp lại',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white54),
                ),
              ),
              items: repeatLabels.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _reminderRepeat = value ?? 'none'),
            ),
            DropdownButtonFormField<int>(
              value: _reminderLeadMinutes,
              dropdownColor: const Color(0xFF555555),
              style: const TextStyle(color: Colors.white),
              iconEnabledColor: Colors.white,
              decoration: const InputDecoration(
                labelText: 'Thông báo',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white54),
                ),
              ),
              items: leadLabels.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _reminderLeadMinutes = value ?? 0),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddImage() {
    final hasImage = _imagePath != null && _imagePath!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: _pickImage,
            icon: Icon(
              hasImage ? Icons.swap_horiz : Icons.image_outlined,
              color: Colors.white,
            ),
            label: Text(
              hasImage ? 'Đổi ảnh' : 'Thêm ảnh',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          if (hasImage)
            TextButton.icon(
              onPressed: _removeImage,
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              label: const Text(
                'Gỡ ảnh',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
        ],
      ),
    );
  }
}
