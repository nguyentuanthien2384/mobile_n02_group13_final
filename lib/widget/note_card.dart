import 'package:flutter/material.dart';
import 'package:todoapp/class/note.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:todoapp/provider/tag_provider.dart';

class NoteCard extends StatefulWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.delete,
    this.onTogglePin,
    this.onManageLabels,
    this.onShare,
    this.onSetReminder,
    this.onMoveToFolder,
    this.onToggleFavorite,
    this.onChangeColor,
    this.onArchive,
  });

  final Note note;
  final Future<void> Function(Note note) onTap;
  final Future<void> Function(int id) delete;
  final Future<void> Function(bool pinned)? onTogglePin;
  final Future<void> Function(Note note)? onManageLabels;
  final Future<void> Function(Note note)? onShare;
  final Future<void> Function(Note note)? onSetReminder;
  final Future<void> Function(Note note)? onMoveToFolder;
  final Future<void> Function(Note note)? onToggleFavorite;
  final Future<void> Function(Note note)? onChangeColor;
  final Future<void> Function(Note note)? onArchive;

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  late final Future<void> Function(Note note) _onTap;
  late final Future<void> Function(int id) _delete;

  @override
  void initState() {
    super.initState();
    _onTap = widget.onTap;
    _delete = widget.delete;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = widget.note.color != 0
        ? Color(widget.note.color)
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = widget.note.color != 0
        ? (ThemeData.estimateBrightnessForColor(Color(widget.note.color)) ==
                  Brightness.dark
              ? Colors.white
              : Colors.black87)
        : theme.textTheme.bodyMedium?.color;

    return Card(
      color: cardColor,
      elevation: 3,
      margin: const EdgeInsets.symmetric(horizontal: 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          title: (widget.note.title == null || widget.note.title!.isEmpty)
              ? (widget.note.reminderAt != null || widget.note.isFavorite
                    ? Row(
                        children: [
                          if (widget.note.isFavorite)
                            const Icon(
                              Icons.star,
                              size: 16,
                              color: Colors.amber,
                            ),
                          if (widget.note.reminderAt != null) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.alarm,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _formatReminder(widget.note.reminderAt!),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ],
                      )
                    : null)
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.note.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge!.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: textColor,
                        ),
                      ),
                    ),
                    if (widget.note.isFavorite)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.star, size: 18, color: Colors.amber),
                      ),
                    if (widget.note.reminderAt != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.alarm,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                  ],
                ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.note.isChecklist)
                _ChecklistPreview(contentJson: widget.note.content)
              else if (widget.note.content != null &&
                  widget.note.content!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _plainPreview(widget.note.content!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: textColor,
                    ),
                  ),
                ),
              ..._buildTagWidgets(context),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _formatDdMmYyyy(widget.note.editedAt),
                  style: theme.textTheme.bodySmall!.copyWith(
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                    color: widget.note.color != 0
                        ? textColor?.withValues(alpha: 0.7)
                        : theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
          onTap: () async => await _onTap(widget.note),
          trailing: PopupMenuButton<String>(
            icon: Icon(
              PhosphorIconsDuotone.dotsThreeVertical,
              color: widget.note.color != 0
                  ? textColor
                  : theme.colorScheme.primary,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            onSelected: (value) async {
              switch (value) {
                case 'pin':
                  if (widget.onTogglePin != null)
                    await widget.onTogglePin!(true);
                  break;
                case 'unpin':
                  if (widget.onTogglePin != null)
                    await widget.onTogglePin!(false);
                  break;
                case 'labels':
                  if (widget.onManageLabels != null)
                    await widget.onManageLabels!(widget.note);
                  break;
                case 'reminder':
                  if (widget.onSetReminder != null)
                    await widget.onSetReminder!(widget.note);
                  break;
                case 'favorite':
                  if (widget.onToggleFavorite != null)
                    await widget.onToggleFavorite!(widget.note);
                  break;
                case 'folder':
                  if (widget.onMoveToFolder != null)
                    await widget.onMoveToFolder!(widget.note);
                  break;
                case 'color':
                  if (widget.onChangeColor != null)
                    await widget.onChangeColor!(widget.note);
                  break;
                case 'share':
                  if (widget.onShare != null)
                    await widget.onShare!(widget.note);
                  break;
                case 'delete':
                  await _delete(widget.note.id);
                  break;
                case 'archive':
                  if (widget.onArchive != null)
                    await widget.onArchive!(widget.note);
                  break;
                default:
              }
            },
            itemBuilder: (context) {
              final isPinned = Provider.of<NoteProvider>(
                context,
                listen: false,
              ).isPinned(widget.note.id);
              final itemTextStyle = theme.textTheme.bodySmall;
              return [
                if (!isPinned)
                  PopupMenuItem(
                    value: 'pin',
                    child: Row(
                      children: [
                        Icon(PhosphorIconsDuotone.pushPin),
                        const SizedBox(width: 8),
                        Text('Ghim', style: itemTextStyle),
                      ],
                    ),
                  )
                else
                  PopupMenuItem(
                    value: 'unpin',
                    child: Row(
                      children: [
                        Icon(PhosphorIconsDuotone.pushPin),
                        const SizedBox(width: 8),
                        Text('Bỏ Ghim', style: itemTextStyle),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'labels',
                  child: Row(
                    children: [
                      const Icon(Icons.label_outline),
                      const SizedBox(width: 8),
                      Text('Thêm nhãn', style: itemTextStyle),
                    ],
                  ),
                ),
                if (widget.onSetReminder != null)
                  PopupMenuItem(
                    value: 'reminder',
                    child: Row(
                      children: [
                        Icon(
                          widget.note.reminderAt != null
                              ? Icons.alarm_on
                              : Icons.alarm_add,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.note.reminderAt != null
                              ? 'Sửa nhắc nhở'
                              : 'Đặt nhắc nhở',
                          style: itemTextStyle,
                        ),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'favorite',
                  child: Row(
                    children: [
                      Icon(
                        widget.note.isFavorite ? Icons.star : Icons.star_border,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.note.isFavorite ? 'Bỏ yêu thích' : 'Yêu thích',
                        style: itemTextStyle,
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'folder',
                  child: Row(
                    children: [
                      const Icon(Icons.folder_open_outlined),
                      const SizedBox(width: 8),
                      Text('Đưa vào thư mục', style: itemTextStyle),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'color',
                  child: Row(
                    children: [
                      const Icon(Icons.color_lens_outlined),
                      const SizedBox(width: 8),
                      Text('Đổi màu sắc', style: itemTextStyle),
                    ],
                  ),
                ),
                if (widget.onShare != null)
                  PopupMenuItem(
                    value: 'share',
                    child: Row(
                      children: [
                        const Icon(Icons.share_outlined),
                        const SizedBox(width: 8),
                        Text('Chia sẻ', style: itemTextStyle),
                      ],
                    ),
                  ),
                if (widget.onArchive != null)
                  PopupMenuItem(
                    value: 'archive',
                    child: Row(
                      children: [
                        const Icon(Icons.archive_outlined),
                        const SizedBox(width: 8),
                        Text('Lưu trữ', style: itemTextStyle),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(PhosphorIconsDuotone.trash, color: Colors.red),
                      const SizedBox(width: 8),
                      Text(
                        'Xóa',
                        style: itemTextStyle?.copyWith(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ];
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTagWidgets(BuildContext context) {
    if (widget.note.tagIds.isEmpty) return const [];
    final tagProvider = Provider.of<TagProvider>(context, listen: false);
    final chips = widget.note.tagIds
        .map((id) => tagProvider.getById(id)?.name)
        .whereType<String>()
        .where((name) => name.trim().isNotEmpty)
        .map(
          (name) => Chip(
            label: Text(
              name,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          ),
        )
        .toList();
    if (chips.isEmpty) return const [];
    return [
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 4, children: chips),
    ];
  }
}

String _plainPreview(String content) {
  try {
    final obj = jsonDecode(content);
    if (obj is List) {
      // Handle quill delta as list or checklist
      if (obj.isNotEmpty) {
        if (obj.first is Map) {
          final firstMap = obj.first as Map;
          // Check if it's checklist format
          if (firstMap.containsKey('text') && firstMap.containsKey('done')) {
            return (firstMap['text'] as String?) ?? '';
          }
          // Otherwise treat as quill delta ops
          final buffer = StringBuffer();
          for (final op in obj) {
            if (op is Map) {
              final ins = op['insert'];
              if (ins is String) buffer.write(ins);
            }
          }
          return buffer.toString().split('\n').first;
        }
      }
    }
    if (obj is Map && obj['ops'] is List) {
      final ops = obj['ops'] as List;
      final buffer = StringBuffer();
      for (final op in ops) {
        final ins = (op as Map)['insert'];
        if (ins is String) buffer.write(ins);
      }
      return buffer.toString().split('\n').first;
    }
  } catch (_) {}
  return content;
}

class _ChecklistPreview extends StatelessWidget {
  const _ChecklistPreview({required this.contentJson});
  final String? contentJson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String text = '';
    bool done = false;
    try {
      if (contentJson != null && contentJson!.isNotEmpty) {
        final list = (jsonDecode(contentJson!) as List);
        if (list.isNotEmpty) {
          final first = list.first as Map<String, dynamic>;
          text = (first['text'] as String?) ?? '';
          done = (first['done'] as bool?) ?? false;
        }
      }
    } catch (_) {}
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_box : Icons.check_box_outline_blank,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDdMmYyyy(DateTime? dt) {
  if (dt == null) return '';
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final y = dt.year.toString();
  return '$d/$m/$y';
}

String _formatReminder(DateTime dt) {
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$d/$m $hh:$mm';
}
