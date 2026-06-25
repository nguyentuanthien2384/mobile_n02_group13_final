import 'package:flutter/material.dart';
import 'package:sqflite/sqlite_api.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/widget/note_card.dart';
import 'package:provider/provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:todoapp/sync/note_sync.dart';
import 'package:todoapp/provider/tag_provider.dart';
import 'package:todoapp/class/tag.dart';
import 'package:todoapp/database/tag_database.dart';
import 'dart:convert';

class NoteList extends StatefulWidget {
  NoteList({super.key, this.db, this.searchQuery = '', this.onDelete, this.filterTagId, this.tagFilterBar});

  final Database? db;
  final String searchQuery;
  final Future<void> Function(int id)? onDelete;
  final int? filterTagId;
  final Widget? tagFilterBar;

  @override
  State<NoteList> createState() => _NoteListState();
}

class _NoteListState extends State<NoteList> {
  late Database? _db;

  @override
  void initState() {
    super.initState();
    _db = widget.db;
  }

  List<Note> _filterNotes(List<Note> notes, String query) {
    final txt = query.trim().toLowerCase();
    if (txt.isEmpty) return List<Note>.from(notes);
    return notes.where((note) =>
      ((note.title ?? '').toLowerCase().contains(txt) ||
        (note.content ?? '').toLowerCase().contains(txt))
    ).toList();
  }

  List<Note> _applyTagFilter(List<Note> notes) {
    final tagId = widget.filterTagId;
    if (tagId == null) return notes;
    return notes.where((note) => note.tagIds.contains(tagId)).toList();
  }

  int _compareTimeDesc(Note a, Note b) {
    final ta = a.editedAt ?? a.createdAt;
    final tb = b.editedAt ?? b.createdAt;
    return tb.compareTo(ta);
  }

  Future<void> _applyTagSelection(Note note, Tag tag, bool attach) async {
    final db = _db;
    if (db == null) return;
    if (attach) {
      await TagDatabase.attachTagToNote(db, note.id, tag.id);
      Provider.of<NoteProvider>(context, listen: false).addTagToNote(note.id, tag.id);
      Provider.of<TagProvider>(context, listen: false).attachNote(tag.id, note.id);
    } else {
      await TagDatabase.detachTagFromNote(db, note.id, tag.id);
      Provider.of<NoteProvider>(context, listen: false).removeTagFromNote(note.id, tag.id);
      Provider.of<TagProvider>(context, listen: false).detachNote(tag.id, note.id);
    }
    await NoteSyncService.pushNoteTags(db, note.id);
  }

  Future<void> _openLabelSelector(Note note) async {
    final db = _db;
    if (db == null) return;
    final theme = Theme.of(context);
    final selected = Set<int>.from(note.tagIds);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            final tags = Provider.of<TagProvider>(ctx).tags;
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text('Labels', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.pushNamed(context, '/tags', arguments: {'db': db});
                          },
                          child: const Text('Manage tags'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (tags.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text('No tags yet. Use Manage tags to create new ones.', style: theme.textTheme.bodyMedium),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(ctx).size.height * 0.6,
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: tags.length,
                          itemBuilder: (context, index) {
                            final tag = tags[index];
                            final isChecked = selected.contains(tag.id);
                            return CheckboxListTile(
                              value: isChecked,
                              title: Text(tag.name),
                              subtitle: Text('${tag.noteIds.length} note${tag.noteIds.length == 1 ? '' : 's'}'),
                              onChanged: (value) async {
                                final shouldAttach = value ?? false;
                                setState(() {
                                  if (shouldAttach) {
                                    selected.add(tag.id);
                                  } else {
                                    selected.remove(tag.id);
                                  }
                                });
                                await _applyTagSelection(note, tag, shouldAttach);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _buildTagChipWidgets(Note note) {
    if (note.tagIds.isEmpty) return const [];
    final tagProvider = Provider.of<TagProvider>(context, listen: false);
    final chips = note.tagIds
        .map((id) => tagProvider.getById(id)?.name)
        .whereType<String>()
        .where((name) => name.trim().isNotEmpty)
        .map(
          (name) => Chip(
            label: Text(name, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11)),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          ),
        )
        .toList();
    if (chips.isEmpty) return const [];
    return [
      const SizedBox(height: 4),
      Wrap(spacing: 6, runSpacing: 4, children: chips),
    ];
  }

  List<Widget> _buildTagChipWidgetsForPinned(Note note) {
    if (note.tagIds.isEmpty) return const [];
    final tagProvider = Provider.of<TagProvider>(context, listen: false);
    final allTags = note.tagIds
        .map((id) => tagProvider.getById(id)?.name)
        .whereType<String>()
        .where((name) => name.trim().isNotEmpty)
        .toList();
    
    if (allTags.isEmpty) return const [];
    
    // Limit to max 2 tags for pinned notes to prevent overflow
    const maxTags = 2;
    final displayTags = allTags.take(maxTags).toList();
    final remainingCount = allTags.length - maxTags;
    
    final chips = displayTags.map(
      (name) => Chip(
        label: Text(name, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 9)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        labelPadding: const EdgeInsets.symmetric(horizontal: 3),
      ),
    ).toList();
    
    if (remainingCount > 0) {
      chips.add(
        Chip(
          label: Text('+$remainingCount', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 9)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          labelPadding: const EdgeInsets.symmetric(horizontal: 3),
        ),
      );
    }
    
    return [
      Wrap(spacing: 1, runSpacing: 1, children: chips),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<NoteProvider>(context);
    final tagFilteredAll = _applyTagFilter(provider.notes);
    final totalCount = tagFilteredAll.length;
    final searchQuery = widget.searchQuery.trim();
    final bool isSearching = searchQuery.isNotEmpty;

    final List<Note> searchResults = List<Note>.from(
      isSearching ? _filterNotes(tagFilteredAll, searchQuery) : tagFilteredAll,
    )..sort(_compareTimeDesc);

    final List<Note> pinned;
    if (isSearching) {
      pinned = const [];
    } else {
      pinned = List<Note>.from(_filterNotes(_applyTagFilter(provider.pinnedNotes), ''))
        ..sort(_compareTimeDesc);
    }

    final List<Note> unpinned;
    if (isSearching) {
      unpinned = searchResults;
    } else {
      unpinned = List<Note>.from(_filterNotes(_applyTagFilter(provider.unpinnedNotes), ''))
        ..sort(_compareTimeDesc);
    }

    // Empty states
    if (isSearching && searchResults.isEmpty) {
      return Center(
        child: Text(
          'No note match',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }
    if (!isSearching && totalCount == 0) {
      return Center(
        child: Text(
          'No note',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        if (widget.tagFilterBar != null)
          SliverToBoxAdapter(
            child: widget.tagFilterBar!,
          ),
        if (!isSearching && pinned.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
              child: Row(
                children: [
                  Text(
                    'Pinned notes',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '${totalCount} note${totalCount == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            ),
          ),
        if (!isSearching && pinned.isNotEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: pinned.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final note = pinned[index];
                  return GestureDetector(
                    onTap: () async {
                      final route = note.isChecklist ? '/todolist' : '/detail';
                      final newNoteInfo = await Navigator.pushNamed(
                        context,
                        route,
                        arguments: {'title': note.title, 'content': note.content, 'id': note.id, 'remoteId': note.remoteId, 'tags': note.tagIds},
                      );
                      if (newNoteInfo is! Map) return;
                      final returnedTags = (newNoteInfo['tags'] as List?)?.cast<int>();
                      final edited = Note(
                        id: note.id,
                        title: newNoteInfo['title'] as String,
                        content: newNoteInfo['content'] as String,
                        createdAt: note.createdAt,
                        editedAt: DateTime.now(),
                        pinned: note.pinned,
                        remoteId: note.remoteId,
                        isChecklist: note.isChecklist,
                        tagIds: returnedTags ?? note.tagIds,
                      );
                      if (_db != null) {
                        await NoteDatabase.updateNote(_db!, edited);
                        await NoteSyncService.pushUpdated(edited);
                      }
                      Provider.of<NoteProvider>(context, listen: false).updateNote(edited);
                    },
                    child: SizedBox(
                      width: 160,
                      child: Card(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        elevation: 3,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ClipRect(
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Expanded(
                                      child: (note.title == null || (note.title ?? '').isEmpty)
                                          ? const SizedBox(height: 0)
                                            : Text(
                                              note.title ?? '',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context).textTheme.titleMedium!.copyWith(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                    ),
                                  PopupMenuButton<String>(
                                    padding: EdgeInsets.zero,
                                    icon: Icon(PhosphorIconsDuotone.dotsThreeVertical, size: 16, color: Theme.of(context).colorScheme.primary),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    onSelected: (value) async {
                                      switch (value) {
                                        case 'unpin':
                                          final updated = Note(
                                            id: note.id,
                                            title: note.title,
                                            content: note.content,
                                            createdAt: note.createdAt,
                                            editedAt: DateTime.now(),
                                            pinned: false,
                                            remoteId: note.remoteId,
                                            isChecklist: note.isChecklist,
                                            tagIds: note.tagIds,
                                          );
                                          if (_db != null) {
                                            await NoteDatabase.updateNote(_db!, updated);
                                            await NoteSyncService.pushUpdated(updated);
                                          }
                                          Provider.of<NoteProvider>(context, listen: false).updateNote(updated);
                                          break;
                                        case 'labels':
                                          await _openLabelSelector(note);
                                          break;
                                        case 'delete':
                                          if (_db != null) {
                                            await NoteDatabase.deleteNote(_db!, note.id);
                                            if (note.remoteId != null) {
                                              await NoteSyncService.pushDeleted(note);
                                            }
                                          }
                                          Provider.of<NoteProvider>(context, listen: false).removeNote(note.id);
                                          break;
                                        default:
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem(
                                        value: 'unpin',
                                        child: Row(children: [
                                          Icon(PhosphorIconsDuotone.pushPin),
                                          const SizedBox(width: 8),
                                          Text('Unpin', style: Theme.of(context).textTheme.bodySmall),
                                        ]),
                                      ),
                                      PopupMenuItem(
                                        value: 'labels',
                                        child: Row(children: [
                                          const Icon(Icons.label_outline),
                                          const SizedBox(width: 8),
                                          Text('Add label', style: Theme.of(context).textTheme.bodySmall),
                                        ]),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Row(children: [
                                          Icon(PhosphorIconsDuotone.trash, color: Colors.red),
                                          const SizedBox(width: 8),
                                          Text('Delete', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red)),
                                        ]),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if ((note.content ?? '').trim().isNotEmpty)
                                Flexible(
                                  child: Text(
                                    _plainPreview(note.content),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                                  ),
                                ),
                              if (note.tagIds.isNotEmpty) ..._buildTagChipWidgetsForPinned(note),
                              Text(
                                _formatDdMmYyyy(note.editedAt),
                                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: Theme.of(context).colorScheme.outline,
                                  fontSize: 9,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 4, top: 4, bottom: 8),
              child: Text(
                'List notes',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final note = unpinned[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: NoteCard(
                  key: ValueKey(note.id),
                  note: note,
                  onTap: (Note note) async {
                    final route = note.isChecklist ? '/todolist' : '/detail';
                    final newNoteInfo = await Navigator.pushNamed(
                      context,
                      route,
                      arguments: {
                        'title': note.title,
                        'content': note.content,
                        'id': note.id,
                        'remoteId': note.remoteId,
                        'tags': note.tagIds,
                      },
                    );
                    if (newNoteInfo is! Map) return;
                    // update note in database and Provider state
                    final returnedTags = (newNoteInfo['tags'] as List?)?.cast<int>();
                    final edited = Note(
                      id: note.id,
                      title: newNoteInfo['title'] as String,
                      content: newNoteInfo['content'] as String,
                      createdAt: note.createdAt,
                      editedAt: DateTime.now(),
                      pinned: note.pinned,
                      remoteId: note.remoteId,
                      isChecklist: note.isChecklist,
                      tagIds: returnedTags ?? note.tagIds,
                    );
                    if (_db != null) await NoteDatabase.updateNote(_db!, edited);
                    Provider.of<NoteProvider>(context, listen: false).updateNote(edited);
                  },
                  onTogglePin: (bool pinned) async {
                    final updated = Note(
                      id: note.id,
                      title: note.title,
                      content: note.content,
                      createdAt: note.createdAt,
                      editedAt: DateTime.now(),
                      pinned: pinned,
                      remoteId: note.remoteId,
                      isChecklist: note.isChecklist,
                      tagIds: note.tagIds,
                    );
                    if (_db != null) {
                      await NoteDatabase.updateNote(_db!, updated);
                      await NoteSyncService.pushUpdated(updated);
                    }
                    Provider.of<NoteProvider>(context, listen: false).updateNote(updated);
                  },
                  onManageLabels: _openLabelSelector,
                  delete: (int id) async {
                    if (widget.onDelete != null) {
                      await widget.onDelete!(id);
                    } else if (_db != null) {
                      final note = Provider.of<NoteProvider>(context, listen: false).notes.firstWhere((n) => n.id == id);
                      await NoteDatabase.deleteNote(_db!, id);
                      await NoteSyncService.pushDeleted(note);
                      Provider.of<NoteProvider>(context, listen: false).removeNote(id);
                    }
                  },
                ),
              );
            },
            childCount: unpinned.length,
          ),
        ),
      ],
    );
  }
}

String _formatDdMmYyyy(DateTime? dt) {
  if (dt == null) return '';
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final y = dt.year.toString();
  return '$d/$m/$y';
}

String _plainPreview(String? content) {
  if (content == null || content.isEmpty) return '';
  try {
    final obj = jsonDecode(content);
    if (obj is List) {
      // Handle quill delta as list or checklist
      if (obj.isNotEmpty) {
        if (obj.first is Map) {
          final firstMap = obj.first as Map;
          // Check if it's checklist format
          if (firstMap.containsKey('text') && firstMap.containsKey('done')) {
            return (firstMap['text'] as String?) ?? '';
          }
          // Otherwise treat as quill delta ops
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

