import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:provider/provider.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/widget/note_list.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/helper/vietnamese_telex.dart';
import 'package:todoapp/sync/note_sync.dart';
import 'package:todoapp/provider/folder_provider.dart';
import 'package:todoapp/provider/tag_provider.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  Database? _db;
  final TextEditingController _searchController = TextEditingController();
  int? _folderId;
  int? _tagId;
  String _dateRange = 'all';
  bool _onlyPinned = false;
  bool _unfinishedChecklist = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)!.settings.arguments as Map?;
    if (args != null && args['db'] != null) {
      _db = args['db'] as Database;
    }
  }

  void _onQueryChanged() {
    setState(() {});
  }

  void clearSearchBar() {
    _searchController.clear();
  }

  bool _matchesAdvancedFilters(Note note) {
    if (_folderId != null && note.folderId != _folderId) return false;
    if (_tagId != null && !note.tagIds.contains(_tagId)) return false;
    if (_onlyPinned && !note.pinned) return false;
    if (_unfinishedChecklist &&
        (!note.isChecklist ||
            !RegExp(r'"done"\s*:\s*false').hasMatch(note.content ?? ''))) {
      return false;
    }
    final now = DateTime.now();
    final start = switch (_dateRange) {
      'today' => DateTime(now.year, now.month, now.day),
      'week' => now.subtract(const Duration(days: 7)),
      'month' => now.subtract(const Duration(days: 30)),
      _ => null,
    };
    return start == null || !note.createdAt.isBefore(start);
  }

  void _clearFilters() {
    setState(() {
      _folderId = null;
      _tagId = null;
      _dateRange = 'all';
      _onlyPinned = false;
      _unfinishedChecklist = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folders = context.watch<FolderProvider>().folders;
    final tags = context.watch<TagProvider>().tags;
    final hasFilters =
        _folderId != null ||
        _tagId != null ||
        _dateRange != 'all' ||
        _onlyPinned ||
        _unfinishedChecklist;
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: theme.colorScheme.primary,
          iconTheme: const IconThemeData(color: Colors.white),
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              inputFormatters: const [VietnameseTelexFormatter()],
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              style: theme.textTheme.titleMedium!.copyWith(color: Colors.white),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: 'Search note ...',
                hintStyle: theme.textTheme.titleMedium!.copyWith(
                  color: Colors.white70,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                suffixIcon: (_searchController.text.isEmpty)
                    ? null
                    : IconButton(
                        onPressed: clearSearchBar,
                        icon: const Icon(Icons.clear, color: Colors.white70),
                      ),
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('Đã ghim'),
                    selected: _onlyPinned,
                    onSelected: (value) => setState(() => _onlyPinned = value),
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    label: const Text('Checklist chưa xong'),
                    selected: _unfinishedChecklist,
                    onSelected: (value) =>
                        setState(() => _unfinishedChecklist = value),
                  ),
                  const SizedBox(width: 6),
                  DropdownButton<String>(
                    value: _dateRange,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Mọi ngày')),
                      DropdownMenuItem(value: 'today', child: Text('Hôm nay')),
                      DropdownMenuItem(
                        value: 'week',
                        child: Text('7 ngày qua'),
                      ),
                      DropdownMenuItem(
                        value: 'month',
                        child: Text('30 ngày qua'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _dateRange = value ?? 'all'),
                  ),
                  if (folders.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    DropdownButton<int?>(
                      value: _folderId,
                      hint: const Text('Thư mục'),
                      underline: const SizedBox.shrink(),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Mọi thư mục'),
                        ),
                        ...folders.map(
                          (folder) => DropdownMenuItem<int?>(
                            value: folder.id,
                            child: Text(folder.name),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() => _folderId = value),
                    ),
                  ],
                  if (tags.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    DropdownButton<int?>(
                      value: _tagId,
                      hint: const Text('Nhãn'),
                      underline: const SizedBox.shrink(),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Mọi nhãn'),
                        ),
                        ...tags.map(
                          (tag) => DropdownMenuItem<int?>(
                            value: tag.id,
                            child: Text(tag.name),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() => _tagId = value),
                    ),
                  ],
                  if (hasFilters) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Xóa bộ lọc',
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.filter_alt_off_outlined),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: NoteList(
                  db: _db,
                  searchQuery: _searchController.text,
                  advancedFilter: _matchesAdvancedFilters,
                  onDelete: (int id) async {
                    if (_db != null) {
                      final note = Provider.of<NoteProvider>(
                        context,
                        listen: false,
                      ).notes.firstWhere((n) => n.id == id);
                      await NoteDatabase.deleteNote(_db!, id);
                      await NoteSyncService.pushDeleted(note);
                    }
                    if (!mounted) return;
                    Provider.of<NoteProvider>(
                      context,
                      listen: false,
                    ).removeNote(id);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
