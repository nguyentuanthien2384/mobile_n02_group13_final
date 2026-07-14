import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/helper/note_text.dart';

/// Compact landing dashboard built from the active local account's notes.
class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  bool _isToday(DateTime value) {
    final now = DateTime.now();
    return value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
  }

  bool _hasUncheckedItem(Note note) =>
      note.isChecklist &&
      RegExp(r'"done"\s*:\s*false').hasMatch(note.content ?? '');

  @override
  Widget build(BuildContext context) {
    final notes = context.watch<NoteProvider>().notes;
    final dueToday = notes.where((note) {
      final reminder = note.reminderAt;
      if (reminder == null) return false;
      return note.reminderRepeat == 'daily' || _isToday(reminder);
    }).toList();
    final incomplete = notes.where(_hasUncheckedItem).toList();
    final pinned = notes.where((note) => note.pinned).toList();
    final recent = List<Note>.from(notes)
      ..sort(
        (a, b) =>
            (b.editedAt ?? b.createdAt).compareTo(a.editedAt ?? a.createdAt),
      );

    return Scaffold(
      appBar: AppBar(title: const Text('Tổng quan hôm nay')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(
            context,
            'Việc đến hạn hôm nay',
            Icons.today_outlined,
            dueToday,
          ),
          _section(
            context,
            'Checklist còn dang dở',
            Icons.checklist_outlined,
            incomplete,
          ),
          _section(context, 'Ghi chú đã ghim', Icons.push_pin_outlined, pinned),
          _section(
            context,
            'Ghi chú gần đây',
            Icons.history_outlined,
            recent.take(5).toList(),
          ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    IconData icon,
    List<Note> notes,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text(
                '${notes.length}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (notes.isEmpty)
            const Card(child: ListTile(title: Text('Không có mục nào')))
          else
            ...notes
                .take(5)
                .map(
                  (note) => Card(
                    child: ListTile(
                      title: Text(
                        (note.title?.isNotEmpty ?? false)
                            ? note.title!
                            : (noteContentToPlainText(note).isEmpty
                                  ? '(Không có tiêu đề)'
                                  : noteContentToPlainText(note)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: note.reminderAt == null
                          ? null
                          : Text(
                              'Nhắc lúc ${TimeOfDay.fromDateTime(note.reminderAt!).format(context)}',
                            ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}
