import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/provider/tag_provider.dart';
import 'package:todoapp/helper/note_text.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  @override
  void initState() {
    super.initState();
    // Nạp lại từ DB mỗi khi mở màn thống kê để phản ánh mọi thay đổi
    // (thêm/xóa/sửa ghi chú, checklist) từ bất kỳ màn nào khác.
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final db = await DatabaseHelper.database();
      final notes = await NoteDatabase.getNotes(db);
      if (!mounted) return;
      Provider.of<NoteProvider>(context, listen: false).setNotes(notes);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // watch → tự cập nhật ngay khi NoteProvider/TagProvider thay đổi.
    final notes = context.watch<NoteProvider>().notes;
    final tags = context.watch<TagProvider>().tags;

    final total = notes.length;
    final pinned = notes.where((n) => n.pinned).length;
    final checklistNotes = notes.where((n) => n.isChecklist).toList();
    final textNotes = total - checklistNotes.length;
    final withReminder = notes.where((n) => n.reminderAt != null).length;

    int checklistItems = 0;
    int checklistDone = 0;
    for (final n in checklistNotes) {
      final p = checklistProgress(n);
      checklistItems += p.total;
      checklistDone += p.done;
    }

    final now = DateTime.now();
    final last7 = notes
        .where((n) => (n.editedAt ?? n.createdAt)
            .isAfter(now.subtract(const Duration(days: 7))))
        .length;

    final progress = checklistItems == 0 ? 0.0 : checklistDone / checklistItems;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Statistics', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Làm mới',
            onPressed: _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text('Overview',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _StatCard(
                  icon: Icons.sticky_note_2_outlined,
                  label: 'Total notes',
                  value: '$total',
                  color: Colors.blue),
              _StatCard(
                  icon: Icons.notes,
                  label: 'Text notes',
                  value: '$textNotes',
                  color: Colors.teal),
              _StatCard(
                  icon: Icons.checklist,
                  label: 'Checklists',
                  value: '${checklistNotes.length}',
                  color: Colors.deepPurple),
              _StatCard(
                  icon: Icons.push_pin_outlined,
                  label: 'Pinned',
                  value: '$pinned',
                  color: Colors.orange),
              _StatCard(
                  icon: Icons.label_outline,
                  label: 'Tags',
                  value: '${tags.length}',
                  color: Colors.green),
              _StatCard(
                  icon: Icons.alarm,
                  label: 'Reminders',
                  value: '$withReminder',
                  color: Colors.redAccent),
            ],
          ),
          const SizedBox(height: 20),
          Text('Checklist progress',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('$checklistDone / $checklistItems done',
                          style: theme.textTheme.bodyLarge),
                      Text('${(progress * 100).toStringAsFixed(0)}%',
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.update),
              title: const Text('Edited in last 7 days'),
              trailing: Text('$last7',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Notes per tag',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...tags.map(
              (t) => Card(
                child: ListTile(
                  leading: const Icon(Icons.label),
                  title: Text(t.name),
                  trailing: Text(
                      '${notes.where((n) => n.tagIds.contains(t.id)).length}',
                      style: theme.textTheme.titleMedium),
                ),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const Spacer(),
            Text(value,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}
