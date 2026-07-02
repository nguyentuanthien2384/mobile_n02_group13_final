import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:todoapp/class/tag.dart';
import 'package:todoapp/database/tag_database.dart';
import 'package:todoapp/provider/tag_provider.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/sync/tag_sync.dart';
import 'package:todoapp/sync/note_sync.dart';

class TagManagementScreen extends StatefulWidget {
  const TagManagementScreen({super.key});

  @override
  State<TagManagementScreen> createState() => _TagManagementScreenState();
}

class _TagManagementScreenState extends State<TagManagementScreen> {
  Database? _db;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _db = args != null ? args['db'] as Database? : null;
  }

  Future<void> _createTag() async {
    final db = _db;
    if (db == null) return;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'Tag name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (confirmed != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) return;
    final createdAt = DateTime.now();
    final tagId = await TagDatabase.insertTag(db, Tag(id: 0, name: name, createdAt: createdAt));
    final tag = Tag(id: tagId, name: name, createdAt: createdAt);
    Provider.of<TagProvider>(context, listen: false).addTag(tag);
    final remoteId = await TagSyncService.pushAdded(db, tag);
    if (remoteId != null && mounted) {
      Provider.of<TagProvider>(context, listen: false).setTagRemoteId(tag.id, remoteId);
    }
  }

  Future<void> _renameTag(Tag tag) async {
    final db = _db;
    if (db == null) return;
    final controller = TextEditingController(text: tag.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'Tag name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (confirmed != true) return;
    final newName = controller.text.trim();
    if (newName.isEmpty || newName == tag.name) return;
    final updated = tag.copyWith(name: newName);
    await TagDatabase.updateTag(db, updated);
    if (!mounted) return;
    Provider.of<TagProvider>(context, listen: false).updateTag(updated);
    await TagSyncService.pushUpdated(updated);
  }

  Future<void> _deleteTag(Tag tag) async {
    final db = _db;
    if (db == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete tag'),
        content: const Text('This will detach the tag from notes but keep the notes themselves.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    final noteProvider = Provider.of<NoteProvider>(context, listen: false);
    final tagProvider = Provider.of<TagProvider>(context, listen: false);
    final affectedNoteIds = List<int>.from(tag.noteIds);

    await TagDatabase.deleteTag(db, tag.id);
    tagProvider.removeTag(tag.id);
    for (final noteId in affectedNoteIds) {
      noteProvider.removeTagFromNote(noteId, tag.id);
      await NoteSyncService.pushNoteTags(db, noteId);
    }
    await TagSyncService.pushDeleted(tag);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final db = _db;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Manage tags', style: TextStyle(color: Colors.white)),
      ),
      floatingActionButton: db == null
          ? null
          : FloatingActionButton(
              onPressed: _createTag,
              child: const Icon(Icons.add),
            ),
      body: Consumer<TagProvider>(
        builder: (context, tagProvider, _) {
          final tags = tagProvider.tags;
          if (tags.isEmpty) {
            return Center(
              child: Text(
                db == null ? 'Database unavailable' : 'No tags yet. Tap + to create one.',
                style: theme.textTheme.bodyMedium,
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: tags.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final tag = tags[index];
              final noteCount = tag.noteIds.length;
              return Material(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  title: Text(tag.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Text('$noteCount note${noteCount == 1 ? '' : 's'}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Rename',
                        onPressed: () => _renameTag(tag),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        tooltip: 'Delete',
                        onPressed: () => _deleteTag(tag),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
