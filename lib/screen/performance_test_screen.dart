import 'package:flutter/material.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/helper/note_search.dart';

class PerformanceTestScreen extends StatefulWidget {
  const PerformanceTestScreen({super.key});

  @override
  State<PerformanceTestScreen> createState() => _PerformanceTestScreenState();
}

class _PerformanceTestScreenState extends State<PerformanceTestScreen> {
  bool _running = false;
  _PerformanceResult? _result;
  String? _error;

  Future<void> _runCheck() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
    });

    try {
      final db = await DatabaseHelper.database();

      final loadWatch = Stopwatch()..start();
      final notes = await NoteDatabase.getNotes(db);
      loadWatch.stop();

      // Đo thao tác tìm kiếm thực tế trên danh sách đã tải; không ghi dữ liệu.
      final searchWatch = Stopwatch()..start();
      final matches = notes
          .where(
            (note) => matchesNoteSearch(
              query: 'a',
              title: note.title,
              content: note.content,
            ),
          )
          .length;
      searchWatch.stop();

      // Đọc lại để phát hiện độ chậm khi mở danh sách sau lần đầu.
      final reloadWatch = Stopwatch()..start();
      await NoteDatabase.getNotes(db);
      reloadWatch.stop();

      if (!mounted) return;
      setState(() {
        _result = _PerformanceResult(
          noteCount: notes.length,
          matchCount: matches,
          loadMs: loadWatch.elapsedMilliseconds,
          searchMs: searchWatch.elapsedMilliseconds,
          reloadMs: reloadWatch.elapsedMilliseconds,
          checkedAt: DateTime.now(),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _formatDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  String _rating(int milliseconds) {
    if (milliseconds < 100) return 'Rất tốt';
    if (milliseconds < 400) return 'Tốt';
    if (milliseconds < 1000) return 'Cần theo dõi';
    return 'Chậm';
  }

  Color _ratingColor(int milliseconds) {
    if (milliseconds < 400) return Colors.green;
    if (milliseconds < 1000) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kiểm tra hiệu năng'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: theme.colorScheme.primaryContainer,
            child: const ListTile(
              leading: Icon(Icons.verified_user_outlined),
              title: Text('An toàn cho dữ liệu của bạn'),
              subtitle: Text(
                'Kiểm tra chỉ đọc dữ liệu trên máy: không tạo, xóa hoặc gửi ghi chú lên máy chủ.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _running ? null : _runCheck,
            icon: _running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.speed),
            label: Text(_running ? 'Đang kiểm tra…' : 'Chạy kiểm tra'),
          ),
          const SizedBox(height: 20),
          if (result == null && _error == null)
            const _EmptyResult()
          else if (result != null) ...[
            Text('Kết quả', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Lần chạy: ${_formatDate(result.checkedAt)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _MetricCard(
              icon: Icons.notes_outlined,
              title: 'Tải danh sách ghi chú',
              value: '${result.loadMs} ms',
              detail: '${result.noteCount} ghi chú đang hoạt động',
              rating: _rating(result.loadMs),
              ratingColor: _ratingColor(result.loadMs),
            ),
            _MetricCard(
              icon: Icons.search,
              title: 'Tìm kiếm trong ghi chú',
              value: '${result.searchMs} ms',
              detail:
                  'Tìm thấy ${result.matchCount}/${result.noteCount} ghi chú',
              rating: _rating(result.searchMs),
              ratingColor: _ratingColor(result.searchMs),
            ),
            _MetricCard(
              icon: Icons.refresh,
              title: 'Tải lại danh sách',
              value: '${result.reloadMs} ms',
              detail: 'Đo tốc độ đọc lại cơ sở dữ liệu cục bộ',
              rating: _rating(result.reloadMs),
              ratingColor: _ratingColor(result.reloadMs),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Không thể kiểm tra: $_error',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PerformanceResult {
  const _PerformanceResult({
    required this.noteCount,
    required this.matchCount,
    required this.loadMs,
    required this.searchMs,
    required this.reloadMs,
    required this.checkedAt,
  });

  final int noteCount;
  final int matchCount;
  final int loadMs;
  final int searchMs;
  final int reloadMs;
  final DateTime checkedAt;
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 56),
    child: Column(
      children: [
        Icon(Icons.analytics_outlined, size: 54, color: Colors.grey),
        SizedBox(height: 12),
        Text('Chưa có kết quả kiểm tra'),
        SizedBox(height: 4),
        Text('Nhấn “Chạy kiểm tra” để đo tốc độ ứng dụng.'),
      ],
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    required this.rating,
    required this.ratingColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final String rating;
  final Color ratingColor;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(detail),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(rating, style: TextStyle(color: ratingColor, fontSize: 12)),
        ],
      ),
    ),
  );
}
