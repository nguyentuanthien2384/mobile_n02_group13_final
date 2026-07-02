import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:todoapp/sync/note_sync.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/screen/share_dialog.dart';
import 'package:todoapp/screen/comments_sheet.dart';

class TodoListScreen extends StatefulWidget {
  const TodoListScreen({super.key});

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen> {
  final TextEditingController _title = TextEditingController();
  final List<TextEditingController> _items = [];
  final List<bool> _checked = [];
  final List<FocusNode> _itemNodes = [];
  final List<bool> _backspaceArmed = [];
  Timer? _debounce;
  int? _noteId;
  String? _remoteId;
  bool _dirty = false;
  bool _suppress = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  bool _initialized = false;
  List<int> _tagIds = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _docSub?.cancel();
    _title.dispose();
    for (final c in _items) { c.dispose(); }
    for (final f in _itemNodes) { f.dispose(); }
    super.dispose();
  }

  void _ensureSub() {
    if (_remoteId == null || _docSub != null) return;
    final user = FirebaseAuth.instance.currentUser; if (user == null) return;
    final doc = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('notes').doc(_remoteId);
    _docSub = doc.snapshots(includeMetadataChanges: true).listen((snap) {
      final data = snap.data(); if (data == null) return;
      if (snap.metadata.hasPendingWrites) return;
      if (_dirty) return; // don't override while typing
      _applyFromJson((data['content'] as String?) ?? '');
      setState(() {});
    });
  }

  void _ensureFirstItemAndFocus() {
    if (_itemNodes.isEmpty) {
      _items.add(TextEditingController());
      _checked.add(false);
      _itemNodes.add(FocusNode());
      _backspaceArmed.add(false);
      setState(() {});
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_itemNodes.isNotEmpty) {
        FocusScope.of(context).requestFocus(_itemNodes.first);
      }
    });
  }

  void _applyFromJson(String jsonStr) {
    try {
      final parsed = (jsonStr.isEmpty) ? [] : (jsonDecode(jsonStr) as List);
      _suppress = true;
      for (final c in _items) { c.dispose(); }
      _items.clear(); _checked.clear();
      for (final e in parsed) {
        final text = (e['text'] as String?) ?? '';
        final done = (e['done'] as bool?) ?? false;
        _items.add(TextEditingController(text: text));
        _checked.add(done);
        _itemNodes.add(FocusNode());
        _backspaceArmed.add(false);
      }
      if (_items.isEmpty) {
        _items.add(TextEditingController());
        _checked.add(false);
        _itemNodes.add(FocusNode());
        _backspaceArmed.add(false);
      }
      _suppress = false;
    } catch (_) {}
  }

  String _toJson() {
    final list = <Map<String, dynamic>>[];
    for (int i = 0; i < _items.length; i++) {
      list.add({'text': _items[i].text, 'done': _checked[i]});
    }
    return jsonEncode(list);
  }

  void _schedulePush() {
    if (_noteId == null || _remoteId == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      await NoteSyncService.pushUpdated(Note(
        id: _noteId!, title: _title.text, content: _toJson(),
        createdAt: DateTime.now(), editedAt: DateTime.now(), pinned: false, remoteId: _remoteId, isChecklist: true,
        tagIds: _tagIds,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final args = ModalRoute.of(context)!.settings.arguments as Map;
    if (!_initialized) {
      _title.text = (args['title'] as String?) ?? '';
      _applyFromJson((args['content'] as String?) ?? '');
      _noteId = args['id'] as int?;
      _remoteId = args['remoteId'] as String?;
      _tagIds = List<int>.from((args['tags'] as List?) ?? const []);
      _initialized = true;
    }
    _ensureSub();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_dirty) {
          final data = <String, dynamic>{
            'title': _title.text,
            'content': _toJson(),
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
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('Checklist', style: TextStyle(color: Colors.white)),
          actions: [
            if (_remoteId != null) ...[
              IconButton(
                icon: const Icon(Icons.share_outlined, color: Colors.white),
                tooltip: 'Chia sẻ',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => ShareDialog(noteRemoteId: _remoteId!),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.comment_outlined, color: Colors.white),
                tooltip: 'Bình luận',
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    builder: (context) => CommentsSheet(noteRemoteId: _remoteId!),
                  );
                },
              ),
            ],
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
          child: Column(
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Title'),
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 20),
                autofocus: _title.text.isEmpty,
                textInputAction: TextInputAction.next,
                onChanged: (_) { if (_suppress) return; _dirty = true; _schedulePush(); },
                onSubmitted: (_) {
                  _ensureFirstItemAndFocus();
                },
                onEditingComplete: _ensureFirstItemAndFocus,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Checkbox(
                          value: _checked[index],
                          onChanged: (v) {
                            _checked[index] = v ?? false; _dirty = true; _schedulePush(); setState(() {});
                          },
                        ),
                        Expanded(
                          child: Focus(
                            focusNode: _itemNodes[index],
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent) {
                                if (event.logicalKey == LogicalKeyboardKey.enter) {
                                  // handled by onSubmitted; keep for desktop
                                  return KeyEventResult.ignored;
                                }
                                if (event.logicalKey == LogicalKeyboardKey.backspace) {
                                  final empty = _items[index].text.isEmpty;
                                  if (empty) {
                                    if (_backspaceArmed[index]) {
                                      if (_items.length > 1) {
                                        final prev = (index > 0) ? index - 1 : 0;
                                        _items.removeAt(index); _checked.removeAt(index);
                                        _itemNodes.removeAt(index).dispose();
                                        _backspaceArmed.removeAt(index);
                                        setState(() {});
                                        Future.delayed(const Duration(milliseconds: 10), () {
                                          _itemNodes[prev].requestFocus();
                                        });
                                      }
                                      _dirty = true; _schedulePush();
                                    } else {
                                      _backspaceArmed[index] = true;
                                    }
                                    return KeyEventResult.handled;
                                  } else {
                                    _backspaceArmed[index] = false;
                                  }
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            child: TextField(
                              controller: _items[index],
                              decoration: const InputDecoration(border: InputBorder.none, hintText: 'List item'),
                              maxLines: 1,
                              textInputAction: TextInputAction.next,
                              onChanged: (_) { if (_suppress) return; _dirty = true; _schedulePush(); _backspaceArmed[index] = false; },
                              onSubmitted: (_) {
                                _items.insert(index + 1, TextEditingController());
                                _checked.insert(index + 1, false);
                                _itemNodes.insert(index + 1, FocusNode());
                                _backspaceArmed.insert(index + 1, false);
                                _dirty = true; _schedulePush();
                                setState(() {});
                                Future.delayed(const Duration(milliseconds: 10), () {
                                  _itemNodes[index + 1].requestFocus();
                                });
                              },
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            if (_items.length == 1) {
                              _items[0].clear(); _checked[0] = false;
                            } else {
                              _items.removeAt(index); _checked.removeAt(index);
                              _itemNodes.removeAt(index).dispose(); _backspaceArmed.removeAt(index);
                            }
                            _dirty = true; _schedulePush();
                            setState(() {});
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


