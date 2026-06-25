import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:todoapp/screen/rich_detail_screen_audio.dart';

class NoteViewScreen extends StatelessWidget {
  const NoteViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final args = ModalRoute.of(context)!.settings.arguments as Map;
    final title = args['title'] as String? ?? '';
    final content = args['content'] as String? ?? '';
    
    // Parse quill content to display with audio players
    Widget contentWidget = _buildQuillContent(context, content);
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Note', style: TextStyle(color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  title,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            contentWidget,
          ],
        ),
      ),
    );
  }

  Widget _buildQuillContent(BuildContext context, String contentJson) {
    try {
      final data = jsonDecode(contentJson);
      if (data is! List) return const SizedBox.shrink();
      
      final theme = Theme.of(context);
      final textBuffer = StringBuffer();
      
      // First, collect all text from quill delta operations
      // Quill may split text across multiple operations, so we concatenate all inserts
      for (final op in data) {
        if (op is Map) {
          final insert = op['insert'];
          if (insert is String) {
            textBuffer.write(insert);
          } else if (insert is Map) {
            // Handle embeds or special inserts
            if (insert.containsKey('audio')) {
              // If audio is embedded, we still add it to text buffer for parsing
              textBuffer.write('🔊AUDIO:${insert['audio']}🔊');
            }
          }
        }
      }
      
      // Now parse the complete text to find audio markers
      final fullText = textBuffer.toString();
      
      // Debug: print the full text to see what we're working with
      print('[NoteViewScreen] Full text: $fullText');
      
      final audioRegex = RegExp(r'🔊AUDIO:(.+?)🔊', dotAll: true);
      final audioPaths = <String>[];
      
      // Extract all audio paths
      for (final match in audioRegex.allMatches(fullText)) {
        final path = match.group(1);
        if (path != null && path.isNotEmpty) {
          audioPaths.add(path.trim());
          print('[NoteViewScreen] Found audio path: $path');
        }
      }
      
      // Remove audio markers from text to display clean text
      final cleanText = fullText.replaceAll(audioRegex, '');
      
      // Build widgets for text and audio players
      final widgets = <Widget>[];
      
      if (cleanText.trim().isNotEmpty) {
        widgets.add(
          Text(
            cleanText,
            style: theme.textTheme.bodyLarge,
          ),
        );
      }
      
      if (audioPaths.isNotEmpty) {
        if (cleanText.trim().isNotEmpty) {
          widgets.add(const SizedBox(height: 16));
        }
        for (final audioPath in audioPaths) {
          print('[NoteViewScreen] Rendering AudioPlayerWidget with path: $audioPath');
          widgets.add(
            AudioPlayerWidget(source: audioPath),
          );
          widgets.add(const SizedBox(height: 8));
        }
      } else {
        // Debug: if no audio found, show the full text (which may contain the marker)
        if (fullText.contains('🔊')) {
          print('[NoteViewScreen] Warning: Found 🔊 marker but regex did not match');
          widgets.add(
            Text(
              'Audio marker found but not parsed: $fullText',
              style: TextStyle(color: Colors.orange),
            ),
          );
        }
      }
      
      if (widgets.isEmpty) {
        return const SizedBox.shrink();
      }
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widgets,
      );
    } catch (e, stackTrace) {
      print('[NoteViewScreen] Error: $e\n$stackTrace');
      return Text(
        'Error displaying content: $e',
        style: const TextStyle(color: Colors.red),
      );
    }
  }
}

