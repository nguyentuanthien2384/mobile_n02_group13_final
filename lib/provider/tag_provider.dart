import 'package:flutter/foundation.dart';
import 'package:todoapp/class/tag.dart';

class TagProvider extends ChangeNotifier {
  final List<Tag> _tags = [];

  List<Tag> get tags => List.unmodifiable(_tags);

  void setTags(List<Tag> tags) {
    _tags
      ..clear()
      ..addAll(tags);
    notifyListeners();
  }

  void addTag(Tag tag) {
    _tags.add(tag);
    notifyListeners();
  }

  void updateTag(Tag tag) {
    final idx = _tags.indexWhere((t) => t.id == tag.id);
    if (idx != -1) {
      _tags[idx] = tag;
      notifyListeners();
    }
  }

  void removeTag(int id) {
    _tags.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  void setTagRemoteId(int id, String remoteId) {
    final idx = _tags.indexWhere((t) => t.id == id);
    if (idx != -1) {
      final tag = _tags[idx];
      _tags[idx] = tag.copyWith(remoteId: remoteId);
      notifyListeners();
    }
  }

  void attachNote(int tagId, int noteId) {
    final idx = _tags.indexWhere((t) => t.id == tagId);
    if (idx != -1 && !_tags[idx].noteIds.contains(noteId)) {
      final updated = _tags[idx].copyWith(noteIds: {..._tags[idx].noteIds, noteId});
      _tags[idx] = updated;
      notifyListeners();
    }
  }

  void detachNote(int tagId, int noteId) {
    final idx = _tags.indexWhere((t) => t.id == tagId);
    if (idx != -1 && _tags[idx].noteIds.contains(noteId)) {
      final updatedNoteIds = Set<int>.from(_tags[idx].noteIds)..remove(noteId);
      _tags[idx] = _tags[idx].copyWith(noteIds: updatedNoteIds);
      notifyListeners();
    }
  }

  Tag? getById(int id) {
    return _tags.cast<Tag?>().firstWhere((t) => t?.id == id, orElse: () => null);
  }
}
