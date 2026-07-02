import 'package:flutter/material.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/widget/note_card.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/sync/note_sync.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Note> _favorites = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() {
      _isLoading = true;
    });
    final db = await DatabaseHelper.database();
    final allNotes = await NoteDatabase.getNotes(db);
    final favs = allNotes.where((n) => n.isFavorite).toList();
    if (mounted) {
      setState(() {
        _favorites = favs;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ghi chú yêu thích', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: theme.colorScheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _favorites.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.star_border_rounded, size: 80, color: Colors.grey.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      const Text(
                        'Chưa có ghi chú yêu thích nào',
                        style: TextStyle(color: Colors.grey, fontSize: 15),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _favorites.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final note = _favorites[index];
                    return NoteCard(
                      note: note,
                      onTap: (n) async {
                        if (n.isChecklist) {
                          await Navigator.pushNamed(
                            context,
                            '/todolist',
                            arguments: {
                              'id': n.id,
                              'title': n.title,
                              'content': n.content,
                              'remoteId': n.remoteId,
                              'tags': n.tagIds,
                            },
                          );
                        } else {
                          await Navigator.pushNamed(
                            context,
                            '/detail',
                            arguments: {
                              'id': n.id,
                              'title': n.title,
                              'content': n.content,
                              'remoteId': n.remoteId,
                              'tags': n.tagIds,
                            },
                          );
                        }
                        _loadFavorites();
                      },
                      delete: (id) async {
                        final db = await DatabaseHelper.database();
                        await NoteDatabase.softDelete(db, id);
                        await NoteSyncService.pushDeleted(note);
                        _loadFavorites();
                      },
                    );
                  },
                ),
    );
  }
}
