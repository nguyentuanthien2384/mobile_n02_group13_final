import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:todoapp/sync/note_sync.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/screen/rich_detail_screen_audio.dart';
import 'package:record/record.dart' if (dart.library.io) 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class RichDetailScreen extends StatefulWidget {
  const RichDetailScreen({super.key});

  @override
  State<RichDetailScreen> createState() => _RichDetailScreenState();
}

class _RichDetailScreenState extends State<RichDetailScreen> {
  final TextEditingController _title = TextEditingController();
  late QuillController _controller;
  final FocusNode _editorFocus = FocusNode();
  Timer? _debounce;
  String? _remoteId;
  int? _noteId;
  bool _dirty = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  bool _controllerHooked = false;
  bool _initialized = false;
  bool _suppressLocalChange = false; // Flag to prevent push when updating from remote
  List<int> _tagIds = const [];
  final ScrollController _scrollController = ScrollController();
  
  // Audio recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;

  Document _fromContent(String? content) {
    try {
      if (content != null && content.isNotEmpty) {
        final data = jsonDecode(content);
        // Register custom embed for audio
        final document = Document.fromJson(data as List);
        return document;
      }
    } catch (_) {}
    return Document()..insert(0, '');
  }

  String _toContent() => jsonEncode(_controller.document.toDelta().toJson());

  void _schedulePush() {
    if (_noteId == null || _remoteId == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      await NoteSyncService.pushUpdated(Note(
        id: _noteId!,
        title: _title.text,
        content: _toContent(),
        createdAt: DateTime.now(),
        editedAt: DateTime.now(),
        pinned: false,
        remoteId: _remoteId,
        tagIds: _tagIds,
      ));
    });
  }

  void _ensureSub() {
    final uid = FirebaseAuth.instance.currentUser?.uid; 
    if (uid == null || _remoteId == null) return;
    _sub ??= FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notes')
        .doc(_remoteId)
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      final data = snap.data(); 
      if (data == null) return;
      if (snap.metadata.hasPendingWrites) return;
      if (_dirty) return;
      
      // Update document content instead of recreating controller
      final newContent = data['content'] as String?;
      if (newContent != null) {
        final currentContent = _toContent();
        // Only update if content actually changed (avoid unnecessary updates)
        if (newContent != currentContent && mounted) {
          final currentSelection = _controller.selection;
          final newDoc = _fromContent(newContent);
          
          // Suppress local change to prevent triggering push when updating from remote
          _suppressLocalChange = true;
          
          // Update document directly - this preserves the controller and embedBuilders
          _controller.document = newDoc;
          
          // Restore selection if possible
          if (currentSelection.isValid) {
            final newDocLength = newDoc.length;
            _controller.updateSelection(
              TextSelection.collapsed(
                offset: currentSelection.baseOffset.clamp(0, newDocLength),
              ),
              ChangeSource.local,
            );
          }
          
          // Clear suppress flag and dirty flag since we accepted remote changes
          _suppressLocalChange = false;
          _dirty = false;
        }
      }
      
      // Update title if changed
      final remoteTitle = data['title'] as String? ?? '';
      if (remoteTitle != _title.text && mounted) {
        _title.text = remoteTitle;
      }
    });
  }

  void _toggleAttribute(Attribute attr) {
    final attrs = _controller.getSelectionStyle().attributes;
    final applied = attrs.containsKey(attr.key);
    _dirty = true; _schedulePush();
    if (applied) {
      _controller.formatSelection(Attribute.fromKeyValue(attr.key, null));
    } else {
      _controller.formatSelection(attr);
    }
  }

  bool _isActive(Attribute attr) {
    final attrs = _controller.getSelectionStyle().attributes;
    return attrs.containsKey(attr.key);
  }

  void _ensureControllerListener() {
    if (_controllerHooked) return;
    _controllerHooked = true;
    _controller.addListener(() {
      if (mounted && !_suppressLocalChange) {
        // Mark as dirty and schedule push when user edits
        _dirty = true;
        _schedulePush();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _title.dispose();
    _controller.dispose();
    _editorFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required to record audio')),
        );
      }
      return;
    }
  }

  Future<void> _startRecording() async {
    await _requestMicrophonePermission();
    
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path = '${dir.path}/audio_$timestamp.m4a';
        
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: path,
        );
        
        setState(() {
          _isRecording = true;
          _recordingDuration = Duration.zero;
        });
        
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() {
              _recordingDuration = Duration(seconds: timer.tick);
            });
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting recording: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      _recordingTimer?.cancel();
      final path = await _audioRecorder.stop();
      
      if (path != null && mounted) {
        setState(() {
          _isRecording = false;
          _recordingDuration = Duration.zero;
        });
        
        // Insert audio into document
        await _insertAudioToDocument(path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error stopping recording: $e')),
        );
      }
    }
  }

  Future<void> _insertAudioToDocument(String audioPath) async {
    try {
      // Copy audio to app documents directory for persistent storage
      final appDir = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${appDir.path}/audio');
      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
      }
      
      final fileName = audioPath.split('/').last;
      final permanentPath = '${audioDir.path}/$fileName';
      await File(audioPath).copy(permanentPath);
      
      // Get relative path for storage in database
      final relativePath = 'audio/$fileName';
      
      // Insert audio as embed directly into QuillEditor
      final index = _controller.selection.baseOffset;
      _controller.document.insert(index, BlockEmbed.custom(AudioEmbed(relativePath)));
      
      // Move cursor after inserted audio
      _controller.updateSelection(
        TextSelection.collapsed(offset: index + 1),
        ChangeSource.local,
      );
      
      _dirty = true;
      _schedulePush();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Audio recorded and inserted'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error inserting audio: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final args = ModalRoute.of(context)!.settings.arguments as Map;
    if (!_initialized) {
      _title.text = (args['title'] as String?) ?? '';
      _noteId = args['id'] as int?;
      _remoteId = args['remoteId'] as String?;
      _tagIds = List<int>.from((args['tags'] as List?) ?? const []);
      _controller = QuillController(document: _fromContent((args['content'] as String?) ?? ''), selection: const TextSelection.collapsed(offset: 0));
      _initialized = true;
    }
    _ensureControllerListener();
    _ensureSub();

    return WillPopScope(
      onWillPop: () async {
        if (_dirty) {
          final result = <String, dynamic>{
            'title': _title.text,
            'content': _toContent(),
            'tags': _tagIds,
            'id': _noteId,
            'remoteId': _remoteId,
          };
          Navigator.pop(context, result);
        } else {
          Navigator.pop(context, null);
        }
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: theme.colorScheme.primary,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('Note', style: TextStyle(color: Colors.white)),
          actions: [
            IconButton(
              icon: const Icon(Icons.play_circle_outline, color: Colors.white),
              tooltip: 'View Note',
              onPressed: () async {
                await Navigator.pushNamed(
                  context,
                  '/view',
                  arguments: {
                    'title': _title.text,
                    'content': _toContent(),
                    'id': _noteId,
                    'remoteId': _remoteId,
                    'tags': _tagIds,
                  },
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: TextField(
                controller: _title,
                autofocus: _title.text.isEmpty,
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'Title'),
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 20),
                textInputAction: TextInputAction.next,
                onChanged: (_) { _dirty = true; _schedulePush(); },
                onSubmitted: (_) => _editorFocus.requestFocus(),
              ),
            ),
            // editor below
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: QuillEditor(
                  controller: _controller,
                  focusNode: _editorFocus,
                  scrollController: _scrollController,
                  config: QuillEditorConfig(
                    placeholder: '',
                    padding: EdgeInsets.zero,
                    embedBuilders: [
                      AudioEmbedBuilder(),
                    ],
                  ),
                ),
              ),
            ),
            // Move toolbar inside body so it sits above the keyboard
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                height: 56,
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Bold',
                      icon: Icon(Icons.format_bold, color: _isActive(Attribute.bold) ? Theme.of(context).colorScheme.primary : null),
                      onPressed: () => _toggleAttribute(Attribute.bold),
                      style: IconButton.styleFrom(
                        backgroundColor: _isActive(Attribute.bold) ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : null,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Italic',
                      icon: Icon(Icons.format_italic, color: _isActive(Attribute.italic) ? Theme.of(context).colorScheme.primary : null),
                      onPressed: () => _toggleAttribute(Attribute.italic),
                      style: IconButton.styleFrom(
                        backgroundColor: _isActive(Attribute.italic) ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : null,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Underline',
                      icon: Icon(Icons.format_underline, color: _isActive(Attribute.underline) ? Theme.of(context).colorScheme.primary : null),
                      onPressed: () => _toggleAttribute(Attribute.underline),
                      style: IconButton.styleFrom(
                        backgroundColor: _isActive(Attribute.underline) ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : null,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Strikethrough',
                      icon: Icon(Icons.format_strikethrough, color: _isActive(Attribute.strikeThrough) ? Theme.of(context).colorScheme.primary : null),
                      onPressed: () => _toggleAttribute(Attribute.strikeThrough),
                      style: IconButton.styleFrom(
                        backgroundColor: _isActive(Attribute.strikeThrough) ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const VerticalDivider(width: 1),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: _isRecording ? 'Stop Recording' : 'Record Audio',
                      icon: Icon(
                        _isRecording ? Icons.stop_circle : Icons.mic,
                        color: _isRecording ? Colors.red : Theme.of(context).colorScheme.primary,
                      ),
                      onPressed: _isRecording ? _stopRecording : _startRecording,
                      style: IconButton.styleFrom(
                        backgroundColor: _isRecording ? Colors.red.withOpacity(0.1) : Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      ),
                    ),
                    if (_isRecording)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '${_recordingDuration.inMinutes}:${(_recordingDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


