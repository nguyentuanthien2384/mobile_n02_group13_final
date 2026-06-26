import 'package:flutter/foundation.dart';
import 'package:todoapp/class/folder.dart';

class FolderProvider extends ChangeNotifier {
  final List<Folder> _folders = [];

  List<Folder> get folders => List.unmodifiable(_folders);

  void setFolders(List<Folder> folders) {
    _folders
      ..clear()
      ..addAll(folders);
    notifyListeners();
  }

  void addFolder(Folder folder) {
    _folders.insert(0, folder);
    notifyListeners();
  }

  void updateFolder(Folder folder) {
    final idx = _folders.indexWhere((f) => f.id == folder.id);
    if (idx != -1) {
      _folders[idx] = folder;
      notifyListeners();
    }
  }

  void removeFolder(int id) {
    _folders.removeWhere((f) => f.id == id);
    notifyListeners();
  }

  Folder? getById(int id) {
    return _folders.cast<Folder?>().firstWhere((f) => f?.id == id, orElse: () => null);
  }
}
