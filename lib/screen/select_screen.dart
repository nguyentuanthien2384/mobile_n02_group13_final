import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/sync/note_sync.dart';
import 'dart:convert';

class SelectScreen extends StatefulWidget {
  const SelectScreen({super.key});

  @override
  State<SelectScreen> createState() => _SelectScreenState();
}

class _SelectScreenState extends State<SelectScreen> {
  late Database? _db;
  final Set<int> _selectedIds = <int>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)!.settings.arguments as Map?;
    _db = (args != null) ? args['db'] as Database? : null;
  }

  int _compareTimeDesc(Note a, Note b) {
    final ta = a.editedAt ?? a.createdAt;
    final tb = b.editedAt ?? b.createdAt;
    return tb.compareTo(ta);
  }

  Future<void> _confirmAndDelete() async {
    if (_selectedIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm'),
        content: Text('Delete ${_selectedIds.length} selected notes?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    final provider = Provider.of<NoteProvider>(context, listen: false);
    for (final id in _selectedIds) {
      if (_db != null) {
        final note = provider.notes.firstWhere((n) => n.id == id);
        await NoteDatabase.deleteNote(_db!, id);
        await NoteSyncService.pushDeleted(note);
      }
      provider.removeNote(id);
    }
    setState(() => _selectedIds.clear());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted selected notes')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = List<Note>.from(Provider.of<NoteProvider>(context).notes)..sort(_compareTimeDesc);

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: theme.colorScheme.primary,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            _selectedIds.isEmpty ? '' : '${_selectedIds.length} selected',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            IconButton(
              onPressed: _selectedIds.isEmpty ? null : _confirmAndDelete,
              icon: Icon(
                Icons.delete,
                color: _selectedIds.isEmpty ? Colors.white38 : Colors.white,
              ),
            ),
          ],
        ),
        body: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          itemCount: notes.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final note = notes[index];
            final checked = _selectedIds.contains(note.id);
            return Material(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  setState(() {
                    if (checked) {
                      _selectedIds.remove(note.id);
                    } else {
                      _selectedIds.add(note.id);
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: checked,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selectedIds.add(note.id);
                            } else {
                              _selectedIds.remove(note.id);
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((note.title ?? '').isNotEmpty)
                              Text(
                                note.title ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            if ((note.content ?? '').isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: note.isChecklist
                                    ? _buildChecklistPreview(note.content, theme)
                                    : Text(
                                        _plainPreview(note.content),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                _formatDdMmYyyy(note.editedAt ?? note.createdAt),
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline, fontStyle: FontStyle.italic),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

String _formatDdMmYyyy(DateTime dt) {
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final y = dt.year.toString();
  return '$d/$m/$y';
}

Widget _buildChecklistPreview(String? content, ThemeData theme) {
  final preview = _firstChecklistItem(content);
  if (preview == null || preview.text.isEmpty) {
    return const SizedBox.shrink();
  }
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(preview.done ? Icons.check_box : Icons.check_box_outline_blank, size: 18, color: theme.colorScheme.primary),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          preview.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
      ),
    ],
  );
}

String _plainPreview(String? content) {
  if (content == null || content.isEmpty) return '';
  try {
    final obj = jsonDecode(content);
    if (obj is List && obj.isNotEmpty) {
      if (obj.first is Map) {
        final firstMap = obj.first as Map;
        if (firstMap.containsKey('text') && firstMap.containsKey('done')) {
          return (firstMap['text'] as String?) ?? '';
        }
        final buffer = StringBuffer();
        for (final op in obj) {
          if (op is Map) {
            final ins = op['insert'];
            if (ins is String) buffer.write(ins);
          }
        }
        return buffer.toString().split('\n').first;
      }
    }
    if (obj is Map && obj['ops'] is List) {
      final ops = obj['ops'] as List;
      final buffer = StringBuffer();
      for (final op in ops) {
        final ins = (op as Map)['insert'];
        if (ins is String) buffer.write(ins);
      }
      return buffer.toString().split('\n').first;
    }
  } catch (_) {}
  return content;
}

_ChecklistPreviewItem? _firstChecklistItem(String? content) {
  if (content == null || content.isEmpty) return null;
  try {
    final list = jsonDecode(content);
    if (list is List && list.isNotEmpty) {
      final first = list.first;
      if (first is Map) {
        final text = (first['text'] as String?) ?? '';
        final done = (first['done'] as bool?) ?? false;
        return _ChecklistPreviewItem(text: text, done: done);
      }
    }
  } catch (_) {}
  return null;
}

class _ChecklistPreviewItem {
  final String text;
  final bool done;
  const _ChecklistPreviewItem({required this.text, required this.done});
}
