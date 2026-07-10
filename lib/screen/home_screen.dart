import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/widget/note_list.dart';
import '../class/note.dart';
import 'package:provider/provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:todoapp/sync/note_sync.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:todoapp/database/tag_database.dart';
import 'package:todoapp/provider/tag_provider.dart';
import 'package:todoapp/provider/folder_provider.dart';
import 'package:todoapp/sync/tag_sync.dart';
import 'package:todoapp/class/tag.dart';
import 'package:todoapp/helper/database.dart';

class HomeScreen extends StatefulWidget {
  final Database? database;

  const HomeScreen({super.key, this.database});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Database? _db;
  StreamSubscription? _sub;
  StreamSubscription? _tagSub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _isSyncing = false;
  bool _showFabMenu = false;
  int? _selectedTagId;
  NoteSortMode _sortMode = NoteSortMode.editedDesc;

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
  }

  Future<void> _initializeDatabase() async {
    // Always get fresh database to ensure it's for current user
    final db = await DatabaseHelper.database();
    if (!mounted) return;
    setState(() {
      _db = db;
    });
    await _loadLocalData(db);
    _setupRealtimeListeners(db);
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 600),
        () => _syncAllAndRefresh(db),
      ),
    );
  }

  Future<void> _loadLocalData(Database db) async {
    final noteProvider = Provider.of<NoteProvider>(context, listen: false);
    final tagProvider = Provider.of<TagProvider>(context, listen: false);
    final localTags = await TagDatabase.getTags(db);
    final localNotes = await NoteDatabase.getNotes(db);
    if (!mounted) return;
    tagProvider.setTags(localTags);
    noteProvider.setNotes(localNotes);
  }

  void _setupRealtimeListeners(Database db) {
    _sub ??= NoteSyncService.listenRealtime(db, () async {
      final noteProvider = Provider.of<NoteProvider>(context, listen: false);
      final tagProvider = Provider.of<TagProvider>(context, listen: false);
      final latestNotes = await NoteDatabase.getNotes(db);
      final latestTags = await TagDatabase.getTags(db);
      if (!mounted) return;
      noteProvider.setNotes(latestNotes);
      tagProvider.setTags(latestTags);
    });

    _tagSub ??= TagSyncService.listenRealtime(db, () async {
      final noteProvider = Provider.of<NoteProvider>(context, listen: false);
      final tagProvider = Provider.of<TagProvider>(context, listen: false);
      final latestNotes = await NoteDatabase.getNotes(db);
      final latestTags = await TagDatabase.getTags(db);
      if (!mounted) return;
      noteProvider.setNotes(latestNotes);
      tagProvider.setTags(latestTags);
    });

    _connSub ??= Connectivity().onConnectivityChanged.listen((results) async {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline) {
        await _syncAllAndRefresh(db);
      }
    });
  }

  Future<void> _syncAllAndRefresh(Database db) async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final noteProvider = Provider.of<NoteProvider>(context, listen: false);
      final tagProvider = Provider.of<TagProvider>(context, listen: false);
      final currentTags = await TagDatabase.getTags(db);
      await TagSyncService.syncAll(db, currentTags);
      final currentNotes = await NoteDatabase.getNotes(db);
      await NoteSyncService.syncAll(db, currentNotes);
      final refreshedNotes = await NoteDatabase.getNotes(db);
      final refreshedTags = await TagDatabase.getTags(db);
      if (!mounted) return;
      noteProvider.setNotes(refreshedNotes);
      tagProvider.setTags(refreshedTags);
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _addNoteButton(String choice) async {
    final db = _db;
    if (db == null) return;
    Map? result;
    if (choice == 'note') {
      result = await Navigator.pushNamed(
        context, '/detail', arguments: {'title': '', 'content': ''},
      ) as Map?;
    } else {
      result = await Navigator.pushNamed(
        context, '/todolist', arguments: {'title': '', 'content': ''},
      ) as Map?;
    }
    if (result == null) return;
    if ((result['title'] as String?) == '' && (result['content'] as String?) == '') return;
    final now = DateTime.now().toIso8601String();
    // raw insert without isChecklist; we'll update flag after fetch
    final noteId = await NoteDatabase.rawInsertNote(db, [
      result['title'] as String? ?? '',
      result['content'] as String? ?? '',
      now, now,
    ]);
    var newNote = await NoteDatabase.getNote(db, noteId);
    if (choice == 'list') {
      newNote = Note(
        id: newNote.id,
        title: newNote.title,
        content: newNote.content,
        createdAt: newNote.createdAt,
        editedAt: newNote.editedAt,
        pinned: newNote.pinned,
        remoteId: newNote.remoteId,
        isChecklist: true,
        tagIds: newNote.tagIds,
      );
      await NoteDatabase.updateNote(db, newNote);
    }
    if (!mounted) return;
    Provider.of<NoteProvider>(context, listen: false).addNote(newNote);
    try {
      await NoteSyncService.pushAdded(db, newNote);
    } catch (e) {
      // ignore: avoid_print
      print('[HomeScreen] Error pushing note to Firestore: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Note created locally but failed to sync. ${e.toString()}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
    final updated = await NoteDatabase.getNote(db, newNote.id);
    if (!mounted) return;
    Provider.of<NoteProvider>(context, listen: false).updateNote(updated);
  }

  // ignore: unused_element
  void _openProfileSheet() {
    final user = FirebaseAuth.instance.currentUser;
    final photo = user?.photoURL;
    final name = user?.displayName ?? 'User';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundImage: (photo != null && photo.isNotEmpty) ? NetworkImage(photo) : null,
                child: (photo == null || photo.isEmpty)
                    ? Text(
                        (name.isNotEmpty ? name[0] : '?'),
                        style: const TextStyle(fontSize: 24, color: Colors.white),
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    // Xóa dữ liệu provider và cache DB trước khi đăng xuất
                    Provider.of<NoteProvider>(context, listen: false).clearNotes();
                    Provider.of<TagProvider>(context, listen: false).setTags([]);
                    Provider.of<FolderProvider>(context, listen: false).setFolders([]);
                    await DatabaseHelper.clearCache();
                    try {
                      await GoogleSignIn().signOut();
                    } catch (_) {}
                    await FirebaseAuth.instance.signOut();
                    if (!mounted) return;
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                  child: const Text('Sign out'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onTagSelected(int? tagId) {
    if (_selectedTagId == tagId) return;
    setState(() {
      _selectedTagId = tagId;
    });
  }

  Widget _buildTagFilterBar(List<Tag> tags) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: _selectedTagId == null,
              onSelected: (_) => _onTagSelected(null),
            ),
            const SizedBox(width: 8),
            ...tags.map(
              (tag) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('${tag.name} (${tag.noteIds.length})'),
                  selected: _selectedTagId == tag.id,
                  onSelected: (_) => _onTagSelected(tag.id),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tags = context.watch<TagProvider>().tags;
    if (_selectedTagId != null && tags.every((t) => t.id != _selectedTagId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedTagId = null;
          });
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 64,
        leading: Center(
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => Navigator.pushNamed(context, '/profile', arguments: {'db': _db}),
            child: SizedBox(
              width: 34,
              height: 34,
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white24,
                backgroundImage: (FirebaseAuth.instance.currentUser?.photoURL != null &&
                        (FirebaseAuth.instance.currentUser?.photoURL ?? '').isNotEmpty)
                    ? NetworkImage(FirebaseAuth.instance.currentUser!.photoURL!)
                    : null,
                child: (FirebaseAuth.instance.currentUser?.photoURL == null ||
                        (FirebaseAuth.instance.currentUser?.photoURL ?? '').isEmpty)
                    ? Text(
                        (FirebaseAuth.instance.currentUser?.displayName?.isNotEmpty == true)
                            ? FirebaseAuth.instance.currentUser!.displayName![0]
                            : 'U',
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      )
                    : null,
              ),
            ),
          ),
        ),
        centerTitle: true,
        title: Text('My Note'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          IconButton(
            icon: Icon(PhosphorIconsDuotone.magnifyingGlass, color: Colors.white),
            onPressed: () async {
              await Navigator.pushNamed(
                context,
                '/search',
                arguments: {'db': _db},
              );
            },
          ),
          IconButton(
            icon: Icon(PhosphorIconsDuotone.checkCircle, color: Colors.white),
            onPressed: () async {
              await Navigator.pushNamed(
                context,
                '/select',
                arguments: {'db': _db},
              );
            },
          ),
          PopupMenuButton<NoteSortMode>(
            icon: const Icon(Icons.sort, color: Colors.white),
            tooltip: 'Sort',
            initialValue: _sortMode,
            onSelected: (mode) => setState(() => _sortMode = mode),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: NoteSortMode.editedDesc,
                child: Text('Last edited (newest)'),
              ),
              PopupMenuItem(
                value: NoteSortMode.editedAsc,
                child: Text('Last edited (oldest)'),
              ),
              PopupMenuItem(
                value: NoteSortMode.createdDesc,
                child: Text('Date created (newest)'),
              ),
              PopupMenuItem(
                value: NoteSortMode.titleAsc,
                child: Text('Title (A–Z)'),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: _db == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  NoteList(
                    db: _db!,
                    filterTagId: _selectedTagId,
                    tagFilterBar: _buildTagFilterBar(tags),
                    sortMode: _sortMode,
                  ),
            Positioned(
              bottom: 36,
              right: 16,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  if (_showFabMenu) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 120),
                      child: SizedBox(
                        width: 120,
                        child: FloatingActionButton.extended(
                          heroTag: 'fab_list',
                          onPressed: () { setState(() { _showFabMenu = false; }); _addNoteButton('list'); },
                          icon: const Icon(Icons.checklist),
                          label: const Text('List'),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 60),
                      child: SizedBox(
                        width: 120,
                        child: FloatingActionButton.extended(
                          heroTag: 'fab_note',
                          onPressed: () { setState(() { _showFabMenu = false; }); _addNoteButton('note'); },
                          icon: const Icon(Icons.note_add),
                          label: const Text('Note'),
                        ),
                      ),
                    ),
                  ],
                  FloatingActionButton(
                    heroTag: 'fab_main',
                    onPressed: () => setState(() { _showFabMenu = !_showFabMenu; }),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    shape: const CircleBorder(),
                    child: Icon(_showFabMenu ? Icons.close : PhosphorIconsFill.plusCircle, color: Colors.white, size: 28),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tagSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}
