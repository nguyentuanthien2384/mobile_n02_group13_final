import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/screen/notes_home_screen.dart';
import 'package:todoapp/screen/folder_screen.dart';
import 'package:todoapp/screen/shared_notes_screen.dart';
import 'package:todoapp/screen/profile_screen.dart';
import 'package:todoapp/sync/note_sync.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _online = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _setupConnectivity();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _setupConnectivity() async {
    final connectivity = Connectivity();
    final initial = await connectivity.checkConnectivity();
    if (!mounted) return;
    setState(
      () => _online = initial.any((item) => item != ConnectivityResult.none),
    );
    _connectivitySub = connectivity.onConnectivityChanged.listen((results) {
      final online = results.any((item) => item != ConnectivityResult.none);
      if (mounted) setState(() => _online = online);
      if (online) _syncNow();
    });
    if (_online) await _syncNow();
  }

  Future<void> _syncNow() async {
    if (_syncing || !_online) return;
    setState(() => _syncing = true);
    try {
      final db = await DatabaseHelper.database();
      final notes = await NoteDatabase.getNotes(db);
      await NoteSyncService.syncAll(db, notes);
      final refreshed = await NoteDatabase.getNotes(db);
      if (mounted) {
        Provider.of<NoteProvider>(context, listen: false).setNotes(refreshed);
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  int _sharedTick = 0; // đổi key để màn Chia sẻ nạp lại khi mở tab

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final screens = <Widget>[
      const NotesHomeScreen(),
      const FolderScreen(),
      SharedNotesScreen(key: ValueKey('shared_$_sharedTick')),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: _online
                ? theme.colorScheme.secondaryContainer
                : theme.colorScheme.errorContainer,
            child: InkWell(
              onTap: _online && !_syncing ? _syncNow : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _online
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _syncing
                          ? 'Đang đồng bộ…'
                          : _online
                          ? 'Đã đồng bộ · Chạm để thử lại'
                          : 'Ngoại tuyến · Dữ liệu vẫn được lưu trên thiết bị',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                  if (index == 2) _sharedTick++; // nạp lại danh sách chia sẻ
                });
              },
              type: BottomNavigationBarType.fixed,
              backgroundColor: theme.colorScheme.surface,
              selectedItemColor: theme.colorScheme.primary,
              unselectedItemColor: theme.colorScheme.outline,
              selectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 12),
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.note_alt_outlined),
                  activeIcon: Icon(Icons.note_alt),
                  label: 'Ghi chú',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.folder_open_outlined),
                  activeIcon: Icon(Icons.folder),
                  label: 'Thư mục',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.people_outline),
                  activeIcon: Icon(Icons.people),
                  label: 'Chia sẻ',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  activeIcon: Icon(Icons.person),
                  label: 'Cá nhân',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
