import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sqflite/sqflite.dart';
import 'package:provider/provider.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/provider/tag_provider.dart';
import 'package:todoapp/provider/theme_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Database? _db;

  @override
  void initState() {
    super.initState();
    _initDb();
  }

  Future<void> _initDb() async {
    final db = await DatabaseHelper.database();
    if (mounted) setState(() => _db = db);
  }

  /// Hỏi xác nhận trước khi đăng xuất; chỉ đăng xuất khi người dùng đồng ý.
  Future<void> _confirmAndSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Đăng xuất'),
        content: const Text('Bạn có chắc muốn đăng xuất khỏi tài khoản này không?'),
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
    // Xóa dữ liệu trong provider trước khi đăng xuất.
    Provider.of<NoteProvider>(context, listen: false).clearNotes();
    Provider.of<TagProvider>(context, listen: false).setTags([]);

    // Xóa cache DB (sẽ nạp lại khi có người dùng khác đăng nhập).
    await DatabaseHelper.clearCache();

    // Đăng xuất Google + Firebase.
    try { await GoogleSignIn().signOut(); } catch (_) {}
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    final user = FirebaseAuth.instance.currentUser;
    final photo = user?.photoURL;
    final name = user?.displayName ?? 'User';
    final email = user?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Profile', style: TextStyle(color: Colors.white)),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Center(
              child: CircleAvatar(
                radius: 48,
                backgroundImage: (photo != null && photo.isNotEmpty) ? NetworkImage(photo) : null,
                child: (photo == null || photo.isEmpty)
                    ? Text(
                        (name.isNotEmpty ? name[0] : '?'),
                        style: const TextStyle(fontSize: 32, color: Colors.white),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            Text(name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            if (email.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(email, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
            ],
            const SizedBox(height: 24),
            Card(
              child: SwitchListTile(
                secondary: Icon(themeProvider.isDark
                    ? Icons.dark_mode
                    : Icons.light_mode),
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
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  final db = _db ?? await DatabaseHelper.database();
                  if (!mounted) return;
                  Navigator.pushNamed(context, '/tags', arguments: {'db': db});
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
    );
  }
}
