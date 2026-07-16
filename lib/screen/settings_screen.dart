import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:todoapp/services/api_service.dart';
import 'package:todoapp/services/backup_service.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/database/tag_database.dart';
import 'package:todoapp/database/folder_database.dart';
import 'package:todoapp/class/note.dart';
import 'package:provider/provider.dart';
import 'package:todoapp/provider/tag_provider.dart';
import 'package:todoapp/provider/folder_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiUrlController = TextEditingController();
  bool _darkMode = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiUrlController.text =
          prefs.getString('api_base_url') ?? ApiService.baseUrl;
      _darkMode = prefs.getBool('dark_mode') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    await ApiService.setBaseUrl(_apiUrlController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Đã lưu cấu hình. Vui lòng khởi động lại ứng dụng để áp dụng.',
          ),
        ),
      );
    }
  }

  Future<void> _testServer() async {
    await ApiService.setBaseUrl(_apiUrlController.text.trim());
    final reachable = await ApiService.isServerReachable();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          reachable
              ? 'Đã kết nối được máy chủ. Bạn có thể đồng bộ và chia sẻ.'
              : 'Không kết nối được máy chủ. Kiểm tra URL API hoặc mạng.',
        ),
      ),
    );
  }

  Future<void> _exportBackup() async {
    try {
      final db = await DatabaseHelper.database();
      final file = await BackupService.exportJson(db);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Sao lưu My Notes',
          text: 'Tệp sao lưu ghi chú JSON',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Không thể xuất sao lưu: $e')));
      }
    }
  }

  Future<void> _importBackup() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      final path = picked?.files.single.path;
      if (path == null) return;
      final source = await File(path).readAsString();
      final db = await DatabaseHelper.database();
      final result = await BackupService.importJson(db, source);
      if (!mounted) return;
      final notes = await NoteDatabase.getNotes(db);
      final tags = await TagDatabase.getTags(db);
      final folders = await FolderDatabase.getFolders(db);
      if (!mounted) return;
      Provider.of<NoteProvider>(context, listen: false).setNotes(notes);
      Provider.of<TagProvider>(context, listen: false).setTags(tags);
      Provider.of<FolderProvider>(context, listen: false).setFolders(folders);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã nhập ${result.notes} ghi chú, ${result.folders} thư mục và ${result.tags} nhãn.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Không thể nhập sao lưu: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Cài đặt',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: theme.colorScheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Hệ thống',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Chế độ tối'),
                  subtitle: const Text('Thay đổi chủ đề ứng dụng'),
                  value: _darkMode,
                  onChanged: (bool value) async {
                    setState(() {
                      _darkMode = value;
                    });
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('dark_mode', value);
                    // Trigger theme change in app
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Sao lưu dữ liệu',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('Xuất sao lưu JSON'),
                  subtitle: const Text(
                    'Ghi chú, thư mục và nhãn trên thiết bị này',
                  ),
                  onTap: _exportBackup,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Nhập sao lưu JSON'),
                  subtitle: const Text(
                    'Thêm dữ liệu từ tệp sao lưu vào tài khoản hiện tại',
                  ),
                  onTap: _importBackup,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Máy chủ & Kết nối',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Đường dẫn API:',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _apiUrlController,
                    decoration: InputDecoration(
                      hintText: 'http://localhost:3000/api',
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _saveSettings,
                      child: const Text('Lưu máy chủ'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _testServer,
                      icon: const Icon(Icons.wifi_tethering_outlined),
                      label: const Text('Kiểm tra kết nối máy chủ'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Thông tin',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              children: [
                ListTile(
                  title: Text('Phiên bản'),
                  trailing: Text('1.0.0 (Chuyên nghiệp)'),
                ),
                Divider(height: 1),
                ListTile(
                  title: Text('Nhà phát triển'),
                  trailing: Text('N02 Group 13'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
