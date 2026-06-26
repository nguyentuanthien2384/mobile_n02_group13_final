import 'package:flutter/material.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/services/note_api_service.dart';
import 'package:todoapp/widget/note_card.dart';

class SharedNotesScreen extends StatefulWidget {
  const SharedNotesScreen({super.key});

  @override
  State<SharedNotesScreen> createState() => _SharedNotesScreenState();
}

class _SharedNotesScreenState extends State<SharedNotesScreen> {
  List<Note> _sharedNotes = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSharedNotes();
  }

  Future<void> _loadSharedNotes() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final res = await NoteApiService.fetchSharedNotes();
      setState(() {
        _sharedNotes = res;
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Được chia sẻ với tôi', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: theme.colorScheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSharedNotes,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sharedNotes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 80, color: Colors.grey.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      const Text(
                        'Chưa có ghi chú nào được chia sẻ với bạn',
                        style: TextStyle(color: Colors.grey, fontSize: 15),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _sharedNotes.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final note = _sharedNotes[index];
                    return NoteCard(
                      note: note,
                      onTap: (n) async {
                        if (n.isChecklist) {
                          await Navigator.pushNamed(
                            context,
                            '/checklist_detail',
                            arguments: {
                              'id': n.id,
                              'title': n.title,
                              'content': n.content,
                              'remoteId': n.remoteId,
                              'tags': n.tagIds,
                              'ownerUid': n.remoteId, // Passing key data for shared notes edit
                            },
                          );
                        } else {
                          await Navigator.pushNamed(
                            context,
                            '/rich_detail',
                            arguments: {
                              'id': n.id,
                              'title': n.title,
                              'content': n.content,
                              'remoteId': n.remoteId,
                              'tags': n.tagIds,
                            },
                          );
                        }
                        _loadSharedNotes();
                      },
                      delete: (id) async {
                        // User can't delete shared notes of other people, just stop sharing locally
                        setState(() {
                          _sharedNotes.removeWhere((e) => e.id == id);
                        });
                      },
                    );
                  },
                ),
    );
  }
}
