import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/helper/note_text.dart';
import 'package:todoapp/services/note_api_service.dart';

/// A separate archive keeps active notes uncluttered without deleting them.
class ArchivedNotesScreen extends StatefulWidget {
  const ArchivedNotesScreen({super.key});

  @override
  State<ArchivedNotesScreen> createState() => _ArchivedNotesScreenState();
}

class _ArchivedNotesScreenState extends State<ArchivedNotesScreen> {
  Database? _db;
  List<Note> _notes = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _db = await DatabaseHelper.database();
    await _reload();
  }

  Future<void> _reload() async {
    final db = _db;
    if (db == null) return;
    final notes = await NoteDatabase.getArchivedNotes(db);
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _loading = false;
    });
  }

  Future<void> _restore(Note note) async {
    final db = _db;
    if (db == null) return;
    await NoteDatabase.setArchived(db, note.id, false);
    if (note.remoteId != null) await NoteApiService.unarchive(note.remoteId!);
    final restored = await NoteDatabase.getNote(db, note.id);
    if (!mounted) return;
    Provider.of<NoteProvider>(context, listen: false).addNote(restored);
    await _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã đưa ghi chú về danh sách chính')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đã lưu trữ')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
          ? const Center(child: Text('Chưa có ghi chú đã lưu trữ'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _notes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final note = _notes[index];
                final content = noteContentToPlainText(note);
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: Text(
                      (note.title?.isNotEmpty ?? false)
                          ? note.title!
                          : (content.isEmpty ? '(Ghi chú trống)' : content),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: content.isEmpty
                        ? null
                        : Text(
                            content,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    trailing: IconButton(
                      tooltip: 'Bỏ lưu trữ',
                      icon: const Icon(Icons.unarchive_outlined),
                      onPressed: () => _restore(note),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
