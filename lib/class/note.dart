// import 'package:shared_preferences/shared_preferences.dart';
// import 'dart:convert';
import 'package:flutter/foundation.dart';

class Note {
  final int id;
  String? title;
  String? content;
  final DateTime createdAt;
  DateTime? editedAt;
  bool pinned;
  String? remoteId; // Firestore document id for cross-device sync
  bool isChecklist;
  DateTime? reminderAt; // local reminder time (managed locally, not synced)
  final List<int> tagIds;
  int color; // Color code (0 for default, or color int values)
  int? folderId; // Associated folder ID (null if not in folder)
  bool isFavorite; // Is marked as favorite note
  final List<String> collaborators; // List of user emails collaborating on this note
  // ─── Social / state fields (synced from backend; not stored in local toMap) ──
  bool isPublished;
  int likesCount;
  int commentsCount;
  bool archived;
  bool deleted;
  // ─── UI fields for the 3 note modes (My Notes / Reminder / Shopping) ──
  String noteType; // 'note' | 'reminder' | 'shopping'
  String? price;   // used by shopping items (e.g. "30k")
  String? imagePath; // local cover image path (My Notes cards)

  Note({
    required this.id,
    this.title,
    this.content,
    required this.createdAt,
    this.editedAt,
    this.pinned = false,
    this.remoteId,
    this.isChecklist = false,
    this.reminderAt,
    List<int>? tagIds,
    this.color = 0,
    this.folderId,
    this.isFavorite = false,
    List<String>? collaborators,
    this.isPublished = false,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.archived = false,
    this.deleted = false,
    this.noteType = 'note',
    this.price,
    this.imagePath,
  })  : tagIds = List<int>.from(tagIds ?? const []),
        collaborators = List<String>.from(collaborators ?? const []);

  Map<String, Object?> toMap() {
    return {
      'title': title,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'editedAt': editedAt?.toIso8601String(),
      'pinned': pinned ? 1 : 0,
      'remoteId': remoteId,
      'isChecklist': isChecklist ? 1 : 0,
      'color': color,
      'folderId': folderId,
      'isFavorite': isFavorite ? 1 : 0,
      'noteType': noteType,
      'price': price,
      'imagePath': imagePath,
    };
  }

  Note copyWith({
    int? id,
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? editedAt,
    bool? pinned,
    String? remoteId,
    bool? isChecklist,
    DateTime? reminderAt,
    List<int>? tagIds,
    int? color,
    int? folderId,
    bool? isFavorite,
    List<String>? collaborators,
    bool? isPublished,
    int? likesCount,
    int? commentsCount,
    bool? archived,
    bool? deleted,
    String? noteType,
    String? price,
    String? imagePath,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      editedAt: editedAt ?? this.editedAt,
      pinned: pinned ?? this.pinned,
      remoteId: remoteId ?? this.remoteId,
      isChecklist: isChecklist ?? this.isChecklist,
      reminderAt: reminderAt ?? this.reminderAt,
      tagIds: tagIds ?? this.tagIds,
      color: color ?? this.color,
      folderId: folderId ?? this.folderId,
      isFavorite: isFavorite ?? this.isFavorite,
      collaborators: collaborators ?? this.collaborators,
      isPublished: isPublished ?? this.isPublished,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      archived: archived ?? this.archived,
      deleted: deleted ?? this.deleted,
      noteType: noteType ?? this.noteType,
      price: price ?? this.price,
      imagePath: imagePath ?? this.imagePath,
    );
  }
}

class NoteManager {
  List<Note> _notes = [];

  set notes(List<Note> notes) => _notes = notes;
  List<Note> get notes => _notes;
  int get quantity => _notes.length;

  void addNote(Note note) {
    _notes.add(note);
  }

  void addNoteAll(List<Note> notes) {
    _notes.addAll(notes);
  }

  void deleteNote(int id) {
    _notes.removeWhere((e) => e.id == id);
  }

  void deleteNoteAll() {
    _notes.clear();
  }

  void updateNote(Note note) {
    for (var _note in _notes) {
      if (_note.id == note.id) {
        _note.title = note.title;
        _note.content = note.content;
        _note.editedAt = note.editedAt;
        _note.pinned = note.pinned;
        _note.color = note.color;
        _note.folderId = note.folderId;
        _note.isFavorite = note.isFavorite;
      }
    }
  }
}

class NoteProvider extends ChangeNotifier {
  final List<Note> _notes = [];
  final Set<int> _pinnedNoteIds = {};
  List<Note> get notes => _notes;

  void setNotes(List<Note> notes) {
    _notes.clear();
    _notes.addAll(notes);
    _pinnedNoteIds
      ..clear()
      ..addAll(notes.where((n) => n.pinned).map((n) => n.id));
    notifyListeners();
  }

  void addNote(Note note) {
    _notes.insert(0, note);
    if (note.pinned) _pinnedNoteIds.add(note.id);
    notifyListeners();
  }

  void updateNote(Note newNote) {
    final idx = _notes.indexWhere((n) => n.id == newNote.id);
    if (idx != -1) {
      _notes[idx] = newNote;
      if (newNote.pinned) {
        _pinnedNoteIds.add(newNote.id);
      } else {
        _pinnedNoteIds.remove(newNote.id);
      }
      notifyListeners();
    }
  }

  void setNoteTags(int noteId, Iterable<int> tags) {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx != -1) {
      final note = _notes[idx];
      _notes[idx] = note.copyWith(tagIds: List<int>.from(tags));
      notifyListeners();
    }
  }

  void addTagToNote(int noteId, int tagId) {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx != -1) {
      final note = _notes[idx];
      if (!note.tagIds.contains(tagId)) {
        final updatedTags = List<int>.from(note.tagIds)..add(tagId);
        _notes[idx] = note.copyWith(tagIds: updatedTags);
        notifyListeners();
      }
    }
  }

  void removeTagFromNote(int noteId, int tagId) {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx != -1) {
      final note = _notes[idx];
      if (note.tagIds.contains(tagId)) {
        final updatedTags = List<int>.from(note.tagIds)..remove(tagId);
        _notes[idx] = note.copyWith(tagIds: updatedTags);
        notifyListeners();
      }
    }
  }

  void removeNote(int id) {
    _notes.removeWhere((e) => e.id == id);
    _pinnedNoteIds.remove(id);
    notifyListeners();
  }

  void clearNotes() {
    _notes.clear();
    _pinnedNoteIds.clear();
    notifyListeners();
  }

  // Pin logic
  void pinNote(int id) {
    _pinnedNoteIds.add(id);
    final idx = _notes.indexWhere((n) => n.id == id);
    if (idx != -1) _notes[idx].pinned = true;
    notifyListeners();
  }

  void unpinNote(int id) {
    _pinnedNoteIds.remove(id);
    final idx = _notes.indexWhere((n) => n.id == id);
    if (idx != -1) _notes[idx].pinned = false;
    notifyListeners();
  }

  bool isPinned(int id) => _pinnedNoteIds.contains(id);

  List<Note> get pinnedNotes => _notes.where((n) => _pinnedNoteIds.contains(n.id)).toList();
  List<Note> get unpinnedNotes => _notes.where((n) => !_pinnedNoteIds.contains(n.id)).toList();

  List<Note> search(String query) {
    final txt = query.trim().toLowerCase();
    if (txt.isEmpty) return List<Note>.from(_notes);
    return _notes.where((n) => ((n.title ?? '').toLowerCase().contains(txt) || (n.content ?? '').toLowerCase().contains(txt))).toList();
  }
}
