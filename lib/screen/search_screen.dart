import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:provider/provider.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/widget/note_list.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/sync/note_sync.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late Database? _db;
  final TextEditingController _searchController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)!.settings.arguments as Map?;
    if (args != null && args['db'] != null) {
      _db = args['db'] as Database;
    }
    _searchController.addListener(_onQueryChanged);
  }

  void _onQueryChanged() {
    setState(() {});
  }

  void clearSearchBar() {
    _searchController.clear();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              style: theme.textTheme.titleMedium!.copyWith(color: Colors.white),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: 'Search note ...',
                hintStyle: theme.textTheme.titleMedium!.copyWith(color: Colors.white70),
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
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: NoteList(
            db: _db,
            searchQuery: _searchController.text,
            onDelete: (int id) async {
              if (_db != null) {
                final note = Provider.of<NoteProvider>(context, listen: false).notes.firstWhere((n) => n.id == id);
                await NoteDatabase.deleteNote(_db!, id);
                await NoteSyncService.pushDeleted(note);
              }
              Provider.of<NoteProvider>(context, listen: false).removeNote(id);
            },
          ),
        ),
      ),
    );
  }
}
