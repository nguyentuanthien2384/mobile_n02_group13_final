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
  final List<int> tagIds;

  Note({
    required this.id,
    this.title,
    this.content,
    required this.createdAt,
    this.editedAt,
    this.pinned = false,
    this.remoteId,
    this.isChecklist = false,
    List<int>? tagIds,
  }) : tagIds = List<int>.from(tagIds ?? const []);

  // factory Note.fromJson(Map<String, dynamic> json) {
  //   return Note(
  //     id: json['id'],
  //     title: json['title'],
  //     content: json['content'],
  //     date: DateTime.parse(json['date']),
  //   );
  // }

  Map<String, Object?> toMap() {
    return {
      'title': title,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'editedAt': editedAt?.toIso8601String(),
      'pinned': pinned ? 1 : 0,
      'remoteId': remoteId,
      'isChecklist': isChecklist ? 1 : 0,
    };
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
      }
    }
  }

//   NoteManager({List<Note>? notes}) {
//     _notes = notes ?? [];
//   }
//
//   factory NoteManager.fromJson(List<dynamic> json) {
//     List<Note> notes = json.map((note) => Note.fromJson(note)).toList();
//     return NoteManager(notes: notes);
//   }
//
//   void addNote(Note note) {
//     _notes.add(note);
//   }
//
//   void removeNote(String id) {
//     _notes.removeWhere((note) => note.id == id);
//   }
//
//   void editNote({
//     required String id,
//     required String? newTitle,
//     required String? newContent,
//     required DateTime? date,
//   }) {
//     for (var note in _notes) {
//       if (note.id == id) {
//         note.title = newTitle;
//         note.content = newContent;
//         note.date = date;
//       }
//     }
//   }
//
//   List<Map<String, dynamic>> toJson() {
//     return _notes.map((note) => note.toJson()).toList();
//   }
}
//
// class NoteStorage {
//   static const _key = 'note';
//
//   static Future<void> saveNotes(NoteManager noteManager) async {
//     final prefs = await SharedPreferences.getInstance();
//     final jsonList = noteManager.toJson();
//     final encoded = jsonEncode(jsonList);
//     await prefs.setString(_key, encoded);
//   }
//
//   static Future<NoteManager> loadNotes() async {
//     final prefs = await SharedPreferences.getInstance();
//     final jsonList = prefs.getString(_key);
//     if (jsonList == null || jsonList.isEmpty) {
//       return NoteManager();
//     }
//     return NoteManager.fromJson(jsonDecode(jsonList));
//   }
// }

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
      _notes[idx] = Note(
        id: note.id,
        title: note.title,
        content: note.content,
        createdAt: note.createdAt,
        editedAt: note.editedAt,
        pinned: note.pinned,
        remoteId: note.remoteId,
        isChecklist: note.isChecklist,
        tagIds: List<int>.from(tags),
      );
      notifyListeners();
    }
  }

  void addTagToNote(int noteId, int tagId) {
    final idx = _notes.indexWhere((n) => n.id == noteId);
    if (idx != -1) {
      final note = _notes[idx];
      if (!note.tagIds.contains(tagId)) {
        final updatedTags = List<int>.from(note.tagIds)..add(tagId);
        _notes[idx] = Note(
          id: note.id,
          title: note.title,
          content: note.content,
          createdAt: note.createdAt,
          editedAt: note.editedAt,
          pinned: note.pinned,
          remoteId: note.remoteId,
          isChecklist: note.isChecklist,
          tagIds: updatedTags,
        );
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
        _notes[idx] = Note(
          id: note.id,
          title: note.title,
          content: note.content,
          createdAt: note.createdAt,
          editedAt: note.editedAt,
          pinned: note.pinned,
          remoteId: note.remoteId,
          isChecklist: note.isChecklist,
          tagIds: updatedTags,
        );
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
