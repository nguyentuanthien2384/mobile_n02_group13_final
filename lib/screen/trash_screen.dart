import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/helper/note_text.dart';
import 'package:todoapp/sync/note_sync.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  Database? _db;
  List<Note> _notes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final db = await DatabaseHelper.database();
    _db = db;
    await _reload();
  }

  Future<void> _reload() async {
    final db = _db;
    if (db == null) return;
    final deleted = await NoteDatabase.getDeletedNotes(db);
    if (!mounted) return;
    setState(() {
      _notes = deleted;
      _loading = false;
    });
  }

  Future<void> _restore(Note note) async {
    final db = _db;
    if (db == null) return;
    await NoteDatabase.restore(db, note.id);
    final restored = await NoteDatabase.getNote(db, note.id);
    if (mounted) {
      Provider.of<NoteProvider>(context, listen: false).addNote(restored);
    }
    // Re-upload to remote (remoteId was cleared on soft delete).
    try {
      await NoteSyncService.pushAdded(db, restored);
    } catch (_) {}
    await _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note restored')),
      );
    }
  }

  Future<void> _deleteForever(Note note) async {
    final db = _db;
    if (db == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: const Text('This note will be removed for good.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await NoteDatabase.deleteNote(db, note.id);
    await _reload();
  }

  Future<void> _emptyTrash() async {
    final db = _db;
    if (db == null || _notes.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty trash?'),
        content: Text('${_notes.length} note(s) will be permanently deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Empty', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    for (final n in List<Note>.from(_notes)) {
      await NoteDatabase.deleteNote(db, n.id);
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Trash', style: TextStyle(color: Colors.white)),
        actions: [
          if (_notes.isNotEmpty)
            IconButton(
              tooltip: 'Empty trash',
              icon: const Icon(Icons.delete_sweep, color: Colors.white),
              onPressed: _emptyTrash,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline,
                          size: 64, color: theme.colorScheme.outline),
                      const SizedBox(height: 12),
                      Text('Trash is empty',
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _notes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final note = _notes[index];
                    final preview = noteContentToPlainText(note);
                    return Card(
                      child: ListTile(
                        title: Text(
                          (note.title?.isNotEmpty ?? false)
                              ? note.title!
                              : (preview.isEmpty ? '(empty note)' : preview),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: preview.isEmpty
                            ? null
                            : Text(preview,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Restore',
                              icon: const Icon(Icons.restore_from_trash,
                                  color: Colors.green),
                              onPressed: () => _restore(note),
                            ),
                            IconButton(
                              tooltip: 'Delete forever',
                              icon: const Icon(Icons.delete_forever,
                                  color: Colors.red),
                              onPressed: () => _deleteForever(note),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
