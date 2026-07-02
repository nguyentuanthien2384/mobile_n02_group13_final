import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todoapp/services/api_service.dart';

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
      _apiUrlController.text = prefs.getString('api_base_url') ?? ApiService.baseUrl;
      _darkMode = prefs.getBool('dark_mode') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', _apiUrlController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu cấu hình. Vui lòng khởi động lại ứng dụng để áp dụng.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: theme.colorScheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Hệ thống',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            'Máy chủ & Kết nối',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _saveSettings,
                      child: const Text('Lưu máy chủ'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Thông tin',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
