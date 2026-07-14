import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/provider/tag_provider.dart';
import 'package:todoapp/provider/folder_provider.dart';
import 'package:todoapp/provider/theme_provider.dart';
import 'package:todoapp/services/api_service.dart';
import 'package:todoapp/services/user_api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Database? _db;
  String _displayName = '';
  String _bio = '';
  String _photoUrl = '';

  static String _bioPreferenceKey(String uid) => 'profile_bio_$uid';

  @override
  void initState() {
    super.initState();
    _initDb();
    _loadProfile();
  }

  Future<void> _initDb() async {
    final db = await DatabaseHelper.database();
    if (mounted) setState(() => _db = db);
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final profile = await UserApiService.fetchProfile();
    if (!mounted) return;
    setState(() {
      _displayName =
          profile?['displayName'] as String? ?? user?.displayName ?? '';
      _bio =
          profile?['bio'] as String? ??
          (user == null
              ? ''
              : prefs.getString(_bioPreferenceKey(user.uid)) ?? '');
      _photoUrl = profile?['photoURL'] as String? ?? user?.photoURL ?? '';
    });
  }

  Future<void> _editProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final nameController = TextEditingController(
      text: _displayName.isNotEmpty ? _displayName : (user.displayName ?? ''),
    );
    final bioController = TextEditingController(text: _bio);
    File? selectedPhoto;
    var saving = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Chỉnh sửa hồ sơ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundImage: selectedPhoto != null
                          ? FileImage(selectedPhoto!)
                          : (_photoUrl.isNotEmpty
                                    ? NetworkImage(_photoUrl)
                                    : null)
                                as ImageProvider?,
                      child: selectedPhoto == null && _photoUrl.isEmpty
                          ? Text(
                              nameController.text.isNotEmpty
                                  ? nameController.text[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(fontSize: 28),
                            )
                          : null,
                    ),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: IconButton.filled(
                        tooltip: 'Chọn ảnh đại diện',
                        icon: const Icon(Icons.camera_alt),
                        onPressed: saving
                            ? null
                            : () async {
                                final picked = await ImagePicker().pickImage(
                                  source: ImageSource.gallery,
                                  imageQuality: 85,
                                );
                                if (picked != null) {
                                  setDialogState(
                                    () => selectedPhoto = File(picked.path),
                                  );
                                }
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Tên hiển thị',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                TextField(
                  controller: bioController,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 2,
                  maxLines: 3,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'Giới thiệu',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.short_text),
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final displayName = nameController.text.trim();
                      if (displayName.isEmpty) {
                        setDialogState(
                          () => error = 'Vui lòng nhập tên hiển thị.',
                        );
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });

                      var photoUrl = _photoUrl;
                      if (selectedPhoto != null) {
                        final uploaded = await ApiService.uploadAvatar(
                          selectedPhoto!,
                        );
                        if (uploaded == null) {
                          setDialogState(() {
                            saving = false;
                            error = 'Không thể tải ảnh đại diện. Hãy thử lại.';
                          });
                          return;
                        }
                        photoUrl = uploaded;
                      }

                      final updated = await UserApiService.updateProfile(
                        displayName: displayName,
                        bio: bioController.text.trim(),
                      );
                      if (updated == null) {
                        setDialogState(() {
                          saving = false;
                          error = 'Không thể lưu hồ sơ. Hãy thử lại.';
                        });
                        // The Firebase/device update below is allowed to
                        // continue when the optional backend is unavailable.
                      }

                      await user.updateDisplayName(displayName);
                      if (photoUrl.isNotEmpty)
                        await user.updatePhotoURL(photoUrl);
                      await user.reload();
                      final bio = bioController.text.trim();
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString(_bioPreferenceKey(user.uid), bio);
                      if (!mounted) return;
                      setState(() {
                        _displayName =
                            updated?['displayName'] as String? ?? displayName;
                        _bio = updated?['bio'] as String? ?? bio;
                        _photoUrl = photoUrl;
                      });
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Đã cập nhật hồ sơ')),
                      );
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Lưu thay đổi'),
            ),
          ],
        ),
      ),
    );
    // The dialog route may still be completing its exit animation when
    // showDialog resolves. Its TextFields are disposed by that route, so do
    // not dispose these controllers here or Flutter can hit
    // `dependencies.isEmpty` while an EditableText is still attached.
  }

  /// Hỏi xác nhận trước khi đăng xuất; chỉ đăng xuất khi người dùng đồng ý.
  Future<void> _confirmAndSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Đăng xuất'),
        content: const Text(
          'Bạn có chắc muốn đăng xuất khỏi tài khoản này không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Không'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _signOut();
  }

  Future<void> _signOut() async {
    // Xóa toàn bộ dữ liệu trong provider trước khi đăng xuất.
    Provider.of<NoteProvider>(context, listen: false).clearNotes();
    Provider.of<TagProvider>(context, listen: false).setTags([]);
    Provider.of<FolderProvider>(context, listen: false).setFolders([]);

    // Xóa cache DB (sẽ nạp lại khi có người dùng khác đăng nhập).
    await DatabaseHelper.clearCache();

    // Đăng xuất Google + Firebase.
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final user = FirebaseAuth.instance.currentUser;
    final photo = _photoUrl.isNotEmpty ? _photoUrl : user?.photoURL;
    final name = _displayName.isNotEmpty
        ? _displayName
        : (user?.displayName ?? 'User');
    final email = user?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Profile', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            tooltip: 'Chỉnh sửa hồ sơ',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editProfile,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Center(
                child: CircleAvatar(
                  radius: 48,
                  backgroundImage: (photo != null && photo.isNotEmpty)
                      ? NetworkImage(photo)
                      : null,
                  child: (photo == null || photo.isEmpty)
                      ? Text(
                          (name.isNotEmpty ? name[0] : '?'),
                          style: const TextStyle(
                            fontSize: 32,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                name,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  email,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
              if (_bio.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _bio,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _editProfile,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Chỉnh sửa hồ sơ'),
              ),
              const SizedBox(height: 24),
              Card(
                child: SwitchListTile(
                  secondary: Icon(
                    themeProvider.isDark ? Icons.dark_mode : Icons.light_mode,
                  ),
                  title: const Text('Dark mode'),
                  value: themeProvider.isDark,
                  onChanged: (value) => themeProvider.toggleDark(value),
                ),
              ),
              const SizedBox(height: 4),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.bar_chart),
                  title: const Text('Statistics'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/statistics'),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Trash'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/trash'),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: const Text('Đã lưu trữ'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/archived'),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Khóa ứng dụng'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/security'),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Cài đặt'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/settings'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    final db = _db ?? await DatabaseHelper.database();
                    if (!mounted) return;
                    Navigator.pushNamed(
                      context,
                      '/tags',
                      arguments: {'db': db},
                    );
                  },
                  child: const Text('Manage tags'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/performance-test');
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                  ),
                  child: const Text('Performance Test'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _confirmAndSignOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Đăng xuất'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
