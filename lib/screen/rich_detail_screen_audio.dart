import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

// Custom block embed for audio
class AudioEmbed extends CustomBlockEmbed {
  const AudioEmbed(String value) : super('audio', value);
  
  String get source => data;
  
  static AudioEmbed? fromJson(Map<String, dynamic> json) {
    final value = json['value'] as String?;
    if (value == null) return null;
    return AudioEmbed(value);
  }
}

// EmbedBuilder for audio embeds - hiển thị AudioPlayerWidget trong editor
class AudioEmbedBuilder extends EmbedBuilder {
  @override
  String get key => 'audio';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final embed = embedContext.node.value;
    String? source;
    
    if (embed is AudioEmbed) {
      source = embed.source;
    } else if (embed.data is String) {
      source = embed.data as String;
    } else if (embed.data is Map) {
      final dataMap = embed.data as Map;
      source = dataMap['value'] as String? ?? dataMap['source'] as String? ?? dataMap['audio'] as String?;
    }
    
    if (source == null || source.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: AudioPlayerWidget(source: source),
    );
  }

  @override
  String toPlainText(Embed embed) {
    return '[Audio]';
  }
}

// Helper function to extract audio paths from content
List<String> extractAudioPaths(String content) {
  final regex = RegExp(r'🔊AUDIO:(.+?)🔊');
  final matches = regex.allMatches(content);
  return matches.map((m) => m.group(1) ?? '').toList();
}

class AudioPlayerWidget extends StatefulWidget {
  final String source;

  const AudioPlayerWidget({super.key, required this.source});

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      _audioPlayer.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state == PlayerState.playing;
          });
        }
      });

      _audioPlayer.onDurationChanged.listen((duration) {
        if (mounted) {
          setState(() {
            _duration = duration;
          });
        }
      });

      _audioPlayer.onPositionChanged.listen((position) {
        if (mounted) {
          setState(() {
            _position = position;
          });
        }
      });

      // Listen for completion event
      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _position = Duration.zero;
            _isPlaying = false;
          });
        }
      });
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _togglePlay() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        final audioPath = '${appDir.path}/${widget.source}';
        
        // If position is at or beyond duration (audio finished), restart from beginning
        if (_duration > Duration.zero && _position >= _duration) {
          await _audioPlayer.seek(Duration.zero);
          await _audioPlayer.play(DeviceFileSource(audioPath));
        } else if (_position == Duration.zero || _duration == Duration.zero) {
          // Play from beginning
          await _audioPlayer.play(DeviceFileSource(audioPath));
        } else {
          // Resume from current position
          await _audioPlayer.resume();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing audio: $e')),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: _togglePlay,
            color: Theme.of(context).colorScheme.primary,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: _duration.inMilliseconds > 0
                      ? _position.inMilliseconds / _duration.inMilliseconds
                      : 0,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      _formatDuration(_duration),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.mic, size: 20, color: Theme.of(context).colorScheme.primary),
        ],
      ),
    );
  }
}

