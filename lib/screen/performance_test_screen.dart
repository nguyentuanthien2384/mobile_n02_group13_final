import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:todoapp/helper/database.dart';
import 'package:todoapp/database/note_database.dart';
import 'package:todoapp/database/tag_database.dart';
import 'package:todoapp/sync/note_sync.dart';
import 'package:todoapp/sync/tag_sync.dart';
import 'package:todoapp/class/note.dart';
import 'package:todoapp/provider/tag_provider.dart';
import 'dart:math';

class PerformanceTestScreen extends StatefulWidget {
  const PerformanceTestScreen({super.key});

  @override
  State<PerformanceTestScreen> createState() => _PerformanceTestScreenState();
}

class _PerformanceTestScreenState extends State<PerformanceTestScreen> {
  bool _isRunning = false;
  String _status = 'Ready';
  int _notesCreated = 0;
  int _tagsCreated = 0;
  String _error = '';

  String? _targetUid;
  
  @override
  void initState() {
    super.initState();
    // Use current user's UID, or fallback to the hardcoded UID
    final user = FirebaseAuth.instance.currentUser;
    _targetUid = user?.uid ?? '9GPp05z3d6e3K0RB5yx0JG5VVYF2';
  }
  final int _noteCount = 1000;
  final int _tagCount = 100;

  final Random _random = Random();
  final List<String> _sampleTitles = [
    'Meeting Notes',
    'Shopping List',
    'Project Ideas',
    'Daily Reminder',
    'Important Task',
    'Quick Note',
    'Meeting Summary',
    'Ideas Collection',
    'Todo Items',
    'Random Thoughts',
  ];

  final List<String> _sampleContents = [
    'This is a sample note content for testing performance.',
    'Lorem ipsum dolor sit amet, consectetur adipiscing elit.',
    'Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.',
    'Ut enim ad minim veniam, quis nostrud exercitation.',
    'Duis aute irure dolor in reprehenderit in voluptate.',
  ];

  final List<String> _sampleTagNames = [
    'Work', 'Personal', 'Important', 'Urgent', 'Ideas',
    'Shopping', 'Projects', 'Meeting', 'Todo', 'Notes',
    'Home', 'Family', 'Health', 'Finance', 'Travel',
    'Study', 'Reading', 'Cooking', 'Sports', 'Music',
  ];

  Future<void> _createTestData() async {
    if (_isRunning || _targetUid == null) return;

    setState(() {
      _isRunning = true;
      _status = 'Starting...';
      _notesCreated = 0;
      _tagsCreated = 0;
      _error = '';
    });

    try {
      final now = DateTime.now();
      final db = FirebaseFirestore.instance;

      // Create tags first
      setState(() {
        _status = 'Creating $_tagCount tags...';
      });

      final List<String> tagRemoteIds = [];
      var tagsBatch = db.batch();
      int batchCount = 0;
      const batchSize = 500; // Firestore batch limit is 500

      for (int i = 0; i < _tagCount; i++) {
        final tagName = i < _sampleTagNames.length
            ? _sampleTagNames[i]
            : 'Tag ${i + 1}';

        final tagRef = db
            .collection('users')
            .doc(_targetUid)
            .collection('tags')
            .doc();

        tagRemoteIds.add(tagRef.id);

        tagsBatch.set(tagRef, {
          'name': tagName,
          'createdAt': now.subtract(Duration(hours: _random.nextInt(720))).toIso8601String(),
          'localId': i + 1,
        });

        batchCount++;
        if (batchCount >= batchSize) {
          await tagsBatch.commit();
          setState(() {
            _tagsCreated += batchSize;
            _status = 'Created $_tagsCreated/$_tagCount tags...';
          });
          tagsBatch = db.batch();
          batchCount = 0;
        }
      }

      if (batchCount > 0) {
        await tagsBatch.commit();
        setState(() {
          _tagsCreated = _tagCount;
          _status = 'Created $_tagsCreated/$_tagCount tags...';
        });
      }

      // Create notes
      setState(() {
        _status = 'Creating $_noteCount notes...';
      });

      var notesBatch = db.batch();
      batchCount = 0;

      for (int i = 0; i < _noteCount; i++) {
        final title = '${_sampleTitles[_random.nextInt(_sampleTitles.length)]} ${i + 1}';
        final content = _sampleContents[_random.nextInt(_sampleContents.length)];
        final isChecklist = _random.nextBool();
        final pinned = _random.nextDouble() < 0.1; // 10% pinned

        // Assign 1-3 random tags to each note
        final selectedTagCount = 1 + _random.nextInt(3);
        final selectedTags = <String>[];
        for (int j = 0; j < selectedTagCount && j < tagRemoteIds.length; j++) {
          selectedTags.add(tagRemoteIds[_random.nextInt(tagRemoteIds.length)]);
        }

        final noteRef = db
            .collection('users')
            .doc(_targetUid)
            .collection('notes')
            .doc();

        notesBatch.set(noteRef, {
          'title': title,
          'content': isChecklist ? '[{"text":"Task 1","done":false},{"text":"Task 2","done":true}]' : content,
          'createdAt': now.subtract(Duration(hours: _random.nextInt(720))).toIso8601String(),
          'editedAt': now.subtract(Duration(hours: _random.nextInt(720))).toIso8601String(),
          'pinned': pinned,
          'localId': i + 1,
          'isChecklist': isChecklist,
          'tags': selectedTags,
        });

        batchCount++;
        if (batchCount >= batchSize) {
          await notesBatch.commit();
          setState(() {
            _notesCreated += batchSize;
            _status = 'Created $_notesCreated/$_noteCount notes...';
          });
          notesBatch = db.batch();
          batchCount = 0;
        }
      }

      if (batchCount > 0) {
        await notesBatch.commit();
        setState(() {
          _notesCreated = _noteCount;
          _status = 'Created $_notesCreated/$_noteCount notes...';
        });
      }

      setState(() {
        _status = 'Completed!';
        _isRunning = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Error occurred';
        _error = e.toString();
        _isRunning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance Test'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Target UID:',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      _targetUid!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (_targetUid != FirebaseAuth.instance.currentUser?.uid) ...[
                      const SizedBox(height: 8),
                      Text(
                        '⚠️ Data will be created for this UID, not current user!',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.orange,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Test Configuration:',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text('• Notes: $_noteCount'),
                    Text('• Tags: $_tagCount'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton.icon(
                onPressed: _isRunning ? null : _createTestData,
                icon: _isRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_isRunning ? 'Running...' : 'Start Test'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status:',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    if (_tagsCreated > 0 || _notesCreated > 0) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: (_tagsCreated + _notesCreated) / (_tagCount + _noteCount),
                      ),
                      const SizedBox(height: 8),
                      Text('Tags: $_tagsCreated/$_tagCount'),
                      Text('Notes: $_notesCreated/$_noteCount'),
                    ],
                  ],
                ),
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Error:',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.red.shade700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (!_isRunning && _status == 'Completed!') ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _refreshData();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh Notes from Firestore'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _refreshData() async {
    try {
      final db = await DatabaseHelper.database();
      
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Syncing from Firestore...')),
        );
      }

      // Sync tags
      var localTags = await TagDatabase.getTags(db);
      await TagSyncService.syncAll(db, localTags);
      localTags = await TagDatabase.getTags(db);
      if (!mounted) return;
      Provider.of<TagProvider>(context, listen: false).setTags(localTags);

      // Sync notes
      var localNotes = await NoteDatabase.getNotes(db);
      await NoteSyncService.syncAll(db, localNotes);
      localNotes = await NoteDatabase.getNotes(db);
      if (!mounted) return;
      Provider.of<NoteProvider>(context, listen: false).setNotes(localNotes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Synced! Loaded ${localNotes.length} notes and ${localTags.length} tags.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error syncing: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

