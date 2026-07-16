import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:todoapp/sync/note_sync.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/helper/vietnamese_telex.dart';
import 'package:todoapp/screen/rich_detail_screen_audio.dart';
import 'package:record/record.dart'
    if (dart.library.io) 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:todoapp/services/api_service.dart';
import 'package:todoapp/screen/share_dialog.dart';
import 'package:todoapp/screen/comments_sheet.dart';

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
  bool _suppressLocalChange =
      false; // Flag to prevent push when updating from remote
  List<int> _tagIds = const [];
  String _noteType = 'note';
  final ScrollController _scrollController = ScrollController();

  // Audio recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;
  bool _showVirtualKeyboard = false;

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
      await NoteSyncService.pushUpdated(
        Note(
          id: _noteId!,
          title: _title.text,
          content: _toContent(),
          createdAt: DateTime.now(),
          editedAt: DateTime.now(),
          pinned: false,
          remoteId: _remoteId,
          tagIds: _tagIds,
          noteType: _noteType,
        ),
      );
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
    _dirty = true;
    _schedulePush();
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
          const SnackBar(
            content: Text('Microphone permission is required to record audio'),
          ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error starting recording: $e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error stopping recording: $e')));
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
      _controller.document.insert(
        index,
        BlockEmbed.custom(AudioEmbed(relativePath)),
      );

      // Move cursor after inserted audio
      _controller.updateSelection(
        TextSelection.collapsed(offset: index + 1),
        ChangeSource.local,
      );

      _dirty = true;
      _schedulePush();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio recorded and inserted'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error inserting audio: $e')));
      }
    }
  }

  void _onVirtualKeyTap(String key) {
    final index = _controller.selection.baseOffset;
    final length = _controller.selection.extentOffset - index;
    if (index >= 0) {
      _controller.replaceText(index, length, key, null);
      _controller.updateSelection(
        TextSelection.collapsed(offset: index + key.length),
        ChangeSource.local,
      );
      _dirty = true;
      _schedulePush();
    }
  }

  void _onVirtualBackspace() {
    final index = _controller.selection.baseOffset;
    final length = _controller.selection.extentOffset - index;
    if (length > 0) {
      _controller.replaceText(index, length, '', null);
      _controller.updateSelection(
        TextSelection.collapsed(offset: index),
        ChangeSource.local,
      );
      _dirty = true;
      _schedulePush();
    } else if (index > 0) {
      _controller.replaceText(index - 1, 1, '', null);
      _controller.updateSelection(
        TextSelection.collapsed(offset: index - 1),
        ChangeSource.local,
      );
      _dirty = true;
      _schedulePush();
    }
  }

  void _onVirtualSpace() {
    _onVirtualKeyTap(' ');
  }

  void _onVirtualEnter() {
    _onVirtualKeyTap('\n');
  }

  Future<void> _uploadImage() async {
    try {
      File? imageFile;

      final source = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Chọn từ bộ sưu tập (Điện thoại)'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.computer),
                title: const Text('Chọn từ máy tính / File explorer'),
                onTap: () => Navigator.pop(context, 'computer'),
              ),
            ],
          ),
        ),
      );

      if (source == null) return;

      if (source == 'gallery') {
        final picker = ImagePicker();
        final pickedFile = await picker.pickImage(source: ImageSource.gallery);
        if (pickedFile == null) return;
        imageFile = File(pickedFile.path);
      } else if (source == 'computer') {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
        );
        if (result == null || result.files.single.path == null) return;
        imageFile = File(result.files.single.path!);
      }

      if (imageFile == null) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đang tải ảnh lên...'),
            duration: Duration(seconds: 1),
          ),
        );
      }

      final url = await ApiService.uploadImage(imageFile);
      if (url == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tải ảnh thất bại!'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final index = _controller.selection.baseOffset;
      _controller.document.insert(index, BlockEmbed.image(url));
      _controller.updateSelection(
        TextSelection.collapsed(offset: index + 1),
        ChangeSource.local,
      );

      _dirty = true;
      _schedulePush();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã chèn ảnh thành công!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi tải ảnh: $e')));
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
      final requestedType = args['noteType'] as String?;
      _noteType = {'note', 'reminder', 'shopping'}.contains(requestedType)
          ? requestedType!
          : 'note';
      _controller = QuillController(
        document: _fromContent((args['content'] as String?) ?? ''),
        selection: const TextSelection.collapsed(offset: 0),
      );
      _initialized = true;
    }
    _ensureControllerListener();
    _ensureSub();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_dirty) {
          final data = <String, dynamic>{
            'title': _title.text,
            'content': _toContent(),
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
          title: const Text('Note', style: TextStyle(color: Colors.white)),
          actions: [
            if (_remoteId != null) ...[
              IconButton(
                icon: const Icon(Icons.share_outlined, color: Colors.white),
                tooltip: 'Chia sẻ',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => ShareDialog(
                      noteRemoteId: _remoteId!,
                      note: Note(
                        id: _noteId ?? 0,
                        title: _title.text,
                        content: _toContent(),
                        createdAt: DateTime.now(),
                        editedAt: DateTime.now(),
                        remoteId: _remoteId,
                        tagIds: _tagIds,
                      ),
                    ),
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
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    builder: (context) =>
                        CommentsSheet(noteRemoteId: _remoteId!),
                  );
                },
              ),
            ],
            IconButton(
              icon: const Icon(Icons.play_circle_outline, color: Colors.white),
              tooltip: 'Xem trước',
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
                inputFormatters: const [VietnameseTelexFormatter()],
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Title',
                ),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  _dirty = true;
                  _schedulePush();
                },
                onSubmitted: (_) => _editorFocus.requestFocus(),
              ),
            ),
            // editor below
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: QuillEditor(
                  controller: _controller,
                  focusNode: _editorFocus,
                  scrollController: _scrollController,
                  config: QuillEditorConfig(
                    placeholder: '',
                    padding: EdgeInsets.zero,
                    embedBuilders: [AudioEmbedBuilder(), ImageEmbedBuilder()],
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
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Bold',
                      icon: Icon(
                        Icons.format_bold,
                        color: _isActive(Attribute.bold)
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      onPressed: () => _toggleAttribute(Attribute.bold),
                      style: IconButton.styleFrom(
                        backgroundColor: _isActive(Attribute.bold)
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.1)
                            : null,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Italic',
                      icon: Icon(
                        Icons.format_italic,
                        color: _isActive(Attribute.italic)
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      onPressed: () => _toggleAttribute(Attribute.italic),
                      style: IconButton.styleFrom(
                        backgroundColor: _isActive(Attribute.italic)
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.1)
                            : null,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Underline',
                      icon: Icon(
                        Icons.format_underline,
                        color: _isActive(Attribute.underline)
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      onPressed: () => _toggleAttribute(Attribute.underline),
                      style: IconButton.styleFrom(
                        backgroundColor: _isActive(Attribute.underline)
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.1)
                            : null,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Strikethrough',
                      icon: Icon(
                        Icons.format_strikethrough,
                        color: _isActive(Attribute.strikeThrough)
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      onPressed: () =>
                          _toggleAttribute(Attribute.strikeThrough),
                      style: IconButton.styleFrom(
                        backgroundColor: _isActive(Attribute.strikeThrough)
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.1)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const VerticalDivider(width: 1),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: _isRecording ? 'Stop Recording' : 'Record Audio',
                      icon: Icon(
                        _isRecording ? Icons.stop_circle : Icons.mic,
                        color: _isRecording
                            ? Colors.red
                            : Theme.of(context).colorScheme.primary,
                      ),
                      onPressed: _isRecording
                          ? _stopRecording
                          : _startRecording,
                      style: IconButton.styleFrom(
                        backgroundColor: _isRecording
                            ? Colors.red.withValues(alpha: 0.1)
                            : Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Upload Image',
                      icon: Icon(
                        Icons.image,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onPressed: _uploadImage,
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.1),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Bàn phím ảo',
                      icon: Icon(
                        _showVirtualKeyboard
                            ? Icons.keyboard_hide
                            : Icons.keyboard,
                        color: _showVirtualKeyboard
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      onPressed: () {
                        setState(() {
                          _showVirtualKeyboard = !_showVirtualKeyboard;
                          if (_showVirtualKeyboard) {
                            FocusScope.of(context).unfocus();
                          }
                        });
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: _showVirtualKeyboard
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.1)
                            : null,
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
            if (_showVirtualKeyboard)
              VirtualKeyboard(
                onKeyTap: _onVirtualKeyTap,
                onBackspace: _onVirtualBackspace,
                onSpace: _onVirtualSpace,
                onEnter: _onVirtualEnter,
              ),
          ],
        ),
      ),
    );
  }
}

class ImageEmbedBuilder extends EmbedBuilder {
  @override
  String get key => 'image';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final embed = embedContext.node.value;
    String? source;

    if (embed.data is String) {
      source = embed.data as String;
    } else if (embed.data is Map) {
      final dataMap = embed.data as Map;
      source =
          dataMap['value'] as String? ??
          dataMap['source'] as String? ??
          dataMap['image'] as String?;
    }

    if (source == null || source.isEmpty) {
      return const SizedBox.shrink();
    }

    // Check if it's a relative asset or a network URL
    final isNetworkUrl =
        source.startsWith('http://') || source.startsWith('https://');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: isNetworkUrl
            ? Image.network(
                source,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    height: 200,
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 100,
                    color: Colors.grey[200],
                    child: const Center(
                      child: Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  );
                },
              )
            : Image.file(
                File(source),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 100,
                    color: Colors.grey[200],
                    child: const Center(
                      child: Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  );
                },
              ),
      ),
    );
  }

  @override
  String toPlainText(Embed node) {
    return '[Image]';
  }
}

class VirtualKeyboard extends StatefulWidget {
  final Function(String) onKeyTap;
  final VoidCallback onBackspace;
  final VoidCallback onSpace;
  final VoidCallback onEnter;

  const VirtualKeyboard({
    super.key,
    required this.onKeyTap,
    required this.onBackspace,
    required this.onSpace,
    required this.onEnter,
  });

  @override
  State<VirtualKeyboard> createState() => _VirtualKeyboardState();
}

class _VirtualKeyboardState extends State<VirtualKeyboard> {
  bool _isShift = false;
  bool _isSymbols = false;

  final List<List<String>> _qwertyLower = [
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
  ];

  final List<List<String>> _qwertyUpper = [
    ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
    ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
    ['Z', 'X', 'C', 'V', 'B', 'N', 'M'],
  ];

  final List<List<String>> _symbols = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['-', '/', ':', ';', '(', ')', '\$', '&', '@', '"'],
    ['.', ',', '?', '!', '\''],
  ];

  Widget _buildKey(
    String label,
    VoidCallback onTap, {
    double widthFactor = 1.0,
    Color? color,
  }) {
    return Expanded(
      flex: (widthFactor * 10).toInt(),
      child: Padding(
        padding: const EdgeInsets.all(3.0),
        child: Material(
          color: color ?? Colors.grey.shade200,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentRows = _isSymbols
        ? _symbols
        : (_isShift ? _qwertyUpper : _qwertyLower);
    final theme = Theme.of(context);

    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: currentRows[0]
                .map((k) => _buildKey(k, () => widget.onKeyTap(k)))
                .toList(),
          ),
          Row(
            children: [
              const Spacer(flex: 5),
              ...currentRows[1].map(
                (k) => _buildKey(k, () => widget.onKeyTap(k)),
              ),
              const Spacer(flex: 5),
            ],
          ),
          Row(
            children: [
              _buildKey(
                _isSymbols ? '#+=' : (_isShift ? '⇪' : '⇧'),
                () {
                  setState(() {
                    if (!_isSymbols) {
                      _isShift = !_isShift;
                    }
                  });
                },
                widthFactor: 1.5,
                color: _isShift ? Colors.blue.shade100 : Colors.grey.shade300,
              ),
              ...currentRows[2].map(
                (k) => _buildKey(k, () => widget.onKeyTap(k)),
              ),
              _buildKey(
                '⌫',
                widget.onBackspace,
                widthFactor: 1.5,
                color: Colors.grey.shade300,
              ),
            ],
          ),
          Row(
            children: [
              _buildKey(
                _isSymbols ? 'ABC' : '?123',
                () {
                  setState(() {
                    _isSymbols = !_isSymbols;
                  });
                },
                widthFactor: 1.5,
                color: Colors.grey.shade300,
              ),
              _buildKey('Khoảng trắng', widget.onSpace, widthFactor: 5.5),
              _buildKey(
                'Nhập',
                widget.onEnter,
                widthFactor: 2.0,
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
