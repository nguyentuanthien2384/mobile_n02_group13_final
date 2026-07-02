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
import 'package:todoapp/helper/note_text.dart';
import 'package:todoapp/services/notification_service.dart';
import 'dart:convert';
import 'package:todoapp/class/folder.dart';
import 'package:todoapp/database/folder_database.dart';
import 'package:todoapp/screen/share_dialog.dart';

/// Ordering options for the note list.
enum NoteSortMode { editedDesc, editedAsc, titleAsc, createdDesc }

class NoteList extends StatefulWidget {
  const NoteList({super.key, this.db, this.searchQuery = '', this.onDelete, this.filterTagId, this.tagFilterBar, this.sortMode = NoteSortMode.editedDesc});

  final Database? db;
  final String searchQuery;
  final Future<void> Function(int id)? onDelete;
  final int? filterTagId;
  final Widget? tagFilterBar;
  final NoteSortMode sortMode;

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
    switch (widget.sortMode) {
      case NoteSortMode.editedDesc:
        return (b.editedAt ?? b.createdAt).compareTo(a.editedAt ?? a.createdAt);
      case NoteSortMode.editedAsc:
        return (a.editedAt ?? a.createdAt).compareTo(b.editedAt ?? b.createdAt);
      case NoteSortMode.titleAsc:
        final ta = (a.title ?? '').toLowerCase();
        final tb = (b.title ?? '').toLowerCase();
        final cmp = ta.compareTo(tb);
        return cmp != 0
            ? cmp
            : (b.editedAt ?? b.createdAt).compareTo(a.editedAt ?? a.createdAt);
      case NoteSortMode.createdDesc:
        return b.createdAt.compareTo(a.createdAt);
    }
  }

  Future<void> _setReminder(Note note) async {
    final db = _db;
    if (db == null) return;

    if (note.reminderAt != null) {
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reminder'),
          content: Text('Current reminder: ${_formatReminderFull(note.reminderAt!)}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'remove'),
                child: const Text('Remove', style: TextStyle(color: Colors.red))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'change'),
                child: const Text('Change time')),
          ],
        ),
      );
      if (action == 'remove') {
        await NoteDatabase.setReminder(db, note.id, null);
        await NotificationService.instance.cancel(note.id);
        final updated = await NoteDatabase.getNote(db, note.id);
        if (!mounted) return;
        Provider.of<NoteProvider>(context, listen: false).updateNote(updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reminder removed')),
        );
        return;
      }
      if (action != 'change') return;
    }

    final now = DateTime.now();
    final initial = note.reminderAt != null && note.reminderAt!.isAfter(now)
        ? note.reminderAt!
        : now.add(const Duration(hours: 1));
    if (!mounted) return;
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
    if (time == null) return;
    final scheduled =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (scheduled.isBefore(DateTime.now())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please pick a time in the future')),
        );
      }
      return;
    }
    await NoteDatabase.setReminder(db, note.id, scheduled);
    final body = noteContentToPlainText(note);
    final ok = await NotificationService.instance.scheduleReminder(
      id: note.id,
      title: (note.title?.isNotEmpty ?? false) ? note.title! : 'Note reminder',
      body: body.isEmpty ? 'You have a note reminder' : body,
      scheduledAt: scheduled,
    );
    final updated = await NoteDatabase.getNote(db, note.id);
    if (!mounted) return;
    Provider.of<NoteProvider>(context, listen: false).updateNote(updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Reminder set for ${_formatReminderFull(scheduled)}'
            : 'Reminder saved (notification could not be scheduled)'),
      ),
    );
  }

  Future<void> _softDelete(Note note) async {
    final db = _db;
    if (db == null) return;
    final remoteId = note.remoteId;
    await NoteDatabase.softDelete(db, note.id);
    if (remoteId != null) {
      await NoteSyncService.pushDeleted(note);
    }
    await NotificationService.instance.cancel(note.id);
    if (!mounted) return;
    Provider.of<NoteProvider>(context, listen: false).removeNote(note.id);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Moved to trash')),
    );
  }

  Future<void> _toggleFavorite(Note note) async {
    final db = _db;
    if (db == null) return;
    final updated = note.copyWith(isFavorite: !note.isFavorite);
    await NoteDatabase.updateNote(db, updated);
    await NoteSyncService.pushUpdated(updated);
    if (!mounted) return;
    Provider.of<NoteProvider>(context, listen: false).updateNote(updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(updated.isFavorite ? 'Đã thêm vào mục yêu thích' : 'Đã bỏ yêu thích')),
    );
  }

  Future<void> _moveToFolder(Note note) async {
    final db = _db;
    if (db == null) return;
    final folders = await FolderDatabase.getFolders(db);
    if (folders.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có thư mục nào. Hãy tạo thư mục trước!')),
      );
      return;
    }

    if (!mounted) return;
    final selectedFolder = await showDialog<Folder>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chọn thư mục'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: folders.length,
            itemBuilder: (context, index) {
              final folder = folders[index];
              return ListTile(
                leading: Icon(Icons.folder, color: Color(folder.color)),
                title: Text(folder.name),
                onTap: () => Navigator.pop(context, folder),
              );
            },
          ),
        ),
      ),
    );

    if (selectedFolder != null) {
      final updated = note.copyWith(folderId: selectedFolder.id);
      await NoteDatabase.updateNote(db, updated);
      await NoteSyncService.pushUpdated(updated);
      if (!mounted) return;
      Provider.of<NoteProvider>(context, listen: false).updateNote(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã đưa vào thư mục ${selectedFolder.name}')),
      );
    }
  }

  Future<void> _changeColor(Note note) async {
    final db = _db;
    if (db == null) return;
    final colors = [
      0x00000000, // Default transparent
      0xFFF44336, // Red
      0xFFE91E63, // Pink
      0xFF9C27B0, // Purple
      0xFF673AB7, // Deep Purple
      0xFF3F51B5, // Indigo
      0xFF2196F3, // Blue
      0xFF03A9F4, // Light Blue
      0xFF00BCD4, // Cyan
      0xFF009688, // Teal
      0xFF4CAF50, // Green
      0xFF8BC34A, // Light Green
      0xFFCDDC39, // Lime
      0xFFFFEB3B, // Yellow
      0xFFFFC107, // Amber
      0xFFFF9800, // Orange
    ];

    if (!mounted) return;
    final selectedColor = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chọn màu sắc'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((c) {
            return GestureDetector(
              onTap: () => Navigator.pop(context, c),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c == 0 ? Colors.grey.shade300 : Color(c),
                  shape: BoxShape.circle,
                  border: c == 0 ? Border.all(color: Colors.grey) : null,
                ),
                child: c == 0 ? const Icon(Icons.format_color_reset, size: 20) : null,
              ),
            );
          }).toList(),
        ),
      ),
    );

    if (selectedColor != null) {
      final updated = note.copyWith(color: selectedColor);
      await NoteDatabase.updateNote(db, updated);
      await NoteSyncService.pushUpdated(updated);
      if (!mounted) return;
      Provider.of<NoteProvider>(context, listen: false).updateNote(updated);
    }
  }

  Future<void> _openShareDialog(Note note) async {
    if (note.remoteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đang đồng bộ ghi chú... Vui lòng thử lại sau.')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => ShareDialog(noteRemoteId: note.remoteId!),
    );
  }

  Future<void> _applyTagSelection(Note note, Tag tag, bool attach) async {
    final db = _db;
    if (db == null) return;
    if (attach) {
      await TagDatabase.attachTagToNote(db, note.id, tag.id);
      if (!mounted) return;
      Provider.of<NoteProvider>(context, listen: false).addTagToNote(note.id, tag.id);
      Provider.of<TagProvider>(context, listen: false).attachNote(tag.id, note.id);
    } else {
      await TagDatabase.detachTagFromNote(db, note.id, tag.id);
      if (!mounted) return;
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
                    '$totalCount note${totalCount == 1 ? '' : 's'}',
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
                      if (!mounted) return;
                      Provider.of<NoteProvider>(context, listen: false).updateNote(edited);
                    },
                    child: SizedBox(
                      width: 160,
                      child: Card(
                        color: note.color != 0 ? Color(note.color) : Theme.of(context).colorScheme.surfaceContainerHighest,
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
                                                color: note.color != 0 ? (ThemeData.estimateBrightnessForColor(Color(note.color)) == Brightness.dark ? Colors.white : Colors.black87) : Theme.of(context).textTheme.bodyMedium?.color,
                                              ),
                                            ),
                                    ),
                                  PopupMenuButton<String>(
                                    padding: EdgeInsets.zero,
                                    icon: Icon(PhosphorIconsDuotone.dotsThreeVertical, size: 16, color: note.color != 0 ? (ThemeData.estimateBrightnessForColor(Color(note.color)) == Brightness.dark ? Colors.white : Colors.black87) : Theme.of(context).colorScheme.primary),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    onSelected: (value) async {
                                      switch (value) {
                                        case 'unpin':
                                          final updated = note.copyWith(pinned: false, editedAt: DateTime.now());
                                          if (_db != null) {
                                            await NoteDatabase.updateNote(_db!, updated);
                                            await NoteSyncService.pushUpdated(updated);
                                          }
                                          if (!mounted) return;
                                          Provider.of<NoteProvider>(context, listen: false).updateNote(updated);
                                          break;
                                        case 'labels':
                                          await _openLabelSelector(note);
                                          break;
                                        case 'favorite':
                                          await _toggleFavorite(note);
                                          break;
                                        case 'folder':
                                          await _moveToFolder(note);
                                          break;
                                        case 'color':
                                          await _changeColor(note);
                                          break;
                                        case 'share':
                                          await _openShareDialog(note);
                                          break;
                                        case 'delete':
                                          await _softDelete(note);
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
                                          Text('Bỏ ghim', style: Theme.of(context).textTheme.bodySmall),
                                        ]),
                                      ),
                                      PopupMenuItem(
                                        value: 'labels',
                                        child: Row(children: [
                                          const Icon(Icons.label_outline),
                                          const SizedBox(width: 8),
                                          Text('Thêm nhãn', style: Theme.of(context).textTheme.bodySmall),
                                        ]),
                                      ),
                                      PopupMenuItem(
                                        value: 'favorite',
                                        child: Row(children: [
                                          Icon(note.isFavorite ? Icons.star : Icons.star_border),
                                          const SizedBox(width: 8),
                                          Text(note.isFavorite ? 'Bỏ yêu thích' : 'Yêu thích', style: Theme.of(context).textTheme.bodySmall),
                                        ]),
                                      ),
                                      PopupMenuItem(
                                        value: 'folder',
                                        child: Row(children: [
                                          const Icon(Icons.folder_open_outlined),
                                          const SizedBox(width: 8),
                                          Text('Đưa vào thư mục', style: Theme.of(context).textTheme.bodySmall),
                                        ]),
                                      ),
                                      PopupMenuItem(
                                        value: 'color',
                                        child: Row(children: [
                                          const Icon(Icons.color_lens_outlined),
                                          const SizedBox(width: 8),
                                          Text('Đổi màu sắc', style: Theme.of(context).textTheme.bodySmall),
                                        ]),
                                      ),
                                      PopupMenuItem(
                                        value: 'share',
                                        child: Row(children: [
                                          const Icon(Icons.share_outlined),
                                          const SizedBox(width: 8),
                                          Text('Chia sẻ', style: Theme.of(context).textTheme.bodySmall),
                                        ]),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Row(children: [
                                          Icon(PhosphorIconsDuotone.trash, color: Colors.red),
                                          const SizedBox(width: 8),
                                          Text('Xóa', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red)),
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
                      color: note.color,
                      folderId: note.folderId,
                      isFavorite: note.isFavorite,
                    );
                    if (_db != null) await NoteDatabase.updateNote(_db!, edited);
                    if (!mounted) return;
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
                      color: note.color,
                      folderId: note.folderId,
                      isFavorite: note.isFavorite,
                    );
                    if (_db != null) {
                      await NoteDatabase.updateNote(_db!, updated);
                      await NoteSyncService.pushUpdated(updated);
                    }
                    if (!mounted) return;
                    Provider.of<NoteProvider>(context, listen: false).updateNote(updated);
                  },
                  onManageLabels: _openLabelSelector,
                  onShare: _openShareDialog,
                  onSetReminder: _setReminder,
                  onMoveToFolder: _moveToFolder,
                  onToggleFavorite: _toggleFavorite,
                  onChangeColor: _changeColor,
                  delete: (int id) async {
                    if (widget.onDelete != null) {
                      await widget.onDelete!(id);
                    } else if (_db != null) {
                      final note = Provider.of<NoteProvider>(context, listen: false).notes.firstWhere((n) => n.id == id);
                      await _softDelete(note);
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

String _formatReminderFull(DateTime dt) {
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final y = dt.year.toString();
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$d/$m/$y $hh:$mm';
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

