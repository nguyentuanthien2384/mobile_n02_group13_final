import 'package:flutter/material.dart';
import 'dart:async';
import 'package:todoapp/sync/note_sync.dart';
import 'package:todoapp/class/note.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final FocusNode _contentFocus = FocusNode();
  Timer? _debounce;
  int? _noteId;
  String? _remoteId;
  bool _dirty = false;
  bool _suppressLocalChange = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  String _lastAckTitle = '';
  String _lastAckContent = '';
  bool _initialized = false;
  List<int> _tagIds = const [];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noteInfo = ModalRoute.of(context)!.settings.arguments as Map;
    if (!_initialized) {
      _titleController.text = noteInfo['title'];
      _contentController.text = noteInfo['content'];
      _lastAckTitle = noteInfo['title'] ?? '';
      _lastAckContent = noteInfo['content'] ?? '';
      _noteId = noteInfo['id'] as int?;
      _remoteId = noteInfo['remoteId'] as String?;
      _tagIds = List<int>.from((noteInfo['tags'] as List?) ?? const []);
      _initialized = true;
    }

    void schedulePush() {
      if (_noteId == null || _remoteId == null) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () async {
        await NoteSyncService.pushUpdated(
          // We only need fields to push; ids are carried in remoteId
          // Local DB update will be handled when leaving screen
          // and by realtime listener on other devices
          // Create a lightweight Note just for payload
          // ignore: unnecessary_new
          new Note(
            id: _noteId!,
            title: _titleController.text,
            content: _contentController.text,
            createdAt: DateTime.now(),
            editedAt: DateTime.now(),
            pinned: false,
            remoteId: _remoteId,
            tagIds: _tagIds,
          ),
        );
      });
    }

    // Realtime subscribe to this note to reflect remote edits (simple merge)
    void ensureSubscription() {
      if (_remoteId == null || _docSub != null) return;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('notes').doc(_remoteId);
      _docSub = doc.snapshots(includeMetadataChanges: true).listen((snap) {
        final data = snap.data();
        if (data == null) return;
        if (snap.metadata.hasPendingWrites) return; // skip our own local writes
        final String remoteTitle = (data['title'] as String?) ?? '';
        final String remoteContent = (data['content'] as String?) ?? '';

        // Simple three-way strategy:
        // - If no local edits since last ack, adopt remote
        // - If local is dirty, defer applying remote but update lastAck to remote
        if (remoteTitle != _lastAckTitle) {
          if (!_dirty) {
            _suppressLocalChange = true;
            _titleController.text = remoteTitle;
            _titleController.selection = TextSelection.collapsed(offset: _titleController.text.length);
            _suppressLocalChange = false;
          }
          _lastAckTitle = remoteTitle;
        }

        if (remoteContent != _lastAckContent) {
          if (!_dirty) {
            _suppressLocalChange = true;
            _contentController.text = remoteContent;
            _contentController.selection = TextSelection.collapsed(offset: _contentController.text.length);
            _suppressLocalChange = false;
          }
          _lastAckContent = remoteContent;
        }
      });
    }
    ensureSubscription();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_dirty) {
          final data = <String, dynamic>{
            'title': _titleController.text,
            'content': _contentController.text,
            'tags': _tagIds,
            'id': _noteId,
            'remoteId': _remoteId,
          };
          Navigator.pop(context, data);
        } else {
          Navigator.pop(context, null);
        }
      },
      child: Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () async {
            if (_dirty) {
              final result = <String, dynamic>{
                'title': _titleController.text,
                'content': _contentController.text,
                'tags': _tagIds,
                'id': _noteId,
                'remoteId': _remoteId,
              };
              Navigator.pop(context, result);
            } else {
              Navigator.pop(context, null);
            }
          },
        ),
        elevation: 1.5,
        centerTitle: true,
        // title: Text(
        //   'Ghi chú',
        //   style: theme.textTheme.titleLarge!.copyWith(
        //     color: Colors.white,
        //     fontWeight: FontWeight.bold,
        //     fontSize: 24,
        //   ),
        // ),
        actions: const [],
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => _contentFocus.requestFocus(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
          child: Form(
            child: Column(
              children: [
                TextFormField(
                  controller: _titleController,
                  autofocus: _titleController.text.isEmpty,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Title',
                  ),
                  style: theme.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.bold, fontSize: 20),
                  maxLines: 1,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    if (_suppressLocalChange) return;
                    _dirty = true;
                    schedulePush();
                  },
                  onFieldSubmitted: (_) => _contentFocus.requestFocus(),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: TextFormField(
                    focusNode: _contentFocus,
                    controller: _contentController,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Content ...',
                      isCollapsed: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                    style: theme.textTheme.bodyLarge,
                    keyboardType: TextInputType.multiline,
                    minLines: null,
                    maxLines: null,
                    expands: true,
                    textInputAction: TextInputAction.newline,
                    onChanged: (_) {
                      if (_suppressLocalChange) return;
                      _dirty = true;
                      schedulePush();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _docSub?.cancel();
    _titleController.dispose();
    _contentController.dispose();
    _contentFocus.dispose();
    super.dispose();
  }
}
