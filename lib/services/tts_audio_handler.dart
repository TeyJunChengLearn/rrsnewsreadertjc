// lib/services/tts_audio_handler.dart
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:rxdart/rxdart.dart';

/// Audio handler for TTS background playback
class TtsAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final FlutterTts _tts = FlutterTts();
  final BehaviorSubject<int> _currentLineSubject = BehaviorSubject.seeded(0);
  final BehaviorSubject<List<String>> _linesSubject = BehaviorSubject.seeded([]);

  List<String> _lines = [];
  int _currentLine = 0;
  bool _isPlaying = false;
  String _articleId = '';
  String _articleTitle = '';

  // Callbacks for position saving and article navigation
  Function(String articleId, int position)? onPositionChanged;
  Function(String articleId)? onMarkAsRead;
  Function()? onNavigateNext;
  Function()? onNavigatePrevious;

  TtsAudioHandler() {
    _init();
  }

  Future<void> _init() async {
    // Initialize TTS
    await _tts.setSharedInstance(true);
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);

    // Set iOS audio category for background playback
    await _tts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        IosTextToSpeechAudioCategoryOptions.duckOthers,
      ],
      IosTextToSpeechAudioMode.voicePrompt,
    );

    // TTS completion handler
    _tts.setCompletionHandler(() async {
      if (!_isPlaying) return;
      await _speakNextLine();
    });

    // TTS cancel handler
    _tts.setCancelHandler(() {
      _updatePlaybackState(playing: false);
    });

    // Initial playback state
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  /// Load article content for TTS
  Future<void> loadArticle({
    required String articleId,
    required String title,
    required List<String> lines,
    int initialLine = 0,
  }) async {
    _articleId = articleId;
    _articleTitle = title;
    _lines = lines;
    _currentLine = initialLine.clamp(0, lines.length - 1);

    _linesSubject.add(_lines);
    _currentLineSubject.add(_currentLine);

    // Update media item
    mediaItem.add(MediaItem(
      id: articleId,
      title: title,
      displayDescription: _lines.isNotEmpty ? _lines[_currentLine] : '',
      extras: {
        'currentLine': _currentLine,
        'totalLines': _lines.length,
      },
    ));

    _updatePlaybackState(playing: false);
  }

  /// Set TTS language
  Future<void> setLanguage(String languageCode) async {
    await _tts.setLanguage(languageCode);
  }

  /// Set TTS speech rate
  Future<void> setSpeechRate(double rate) async {
    await _tts.setSpeechRate(rate);
  }

  Future<void> _speakCurrentLine() async {
    if (_lines.isEmpty || _currentLine >= _lines.length || _currentLine < 0) {
      return;
    }

    final text = _lines[_currentLine].trim();
    if (text.isEmpty) {
      await _speakNextLine();
      return;
    }

    // Mark article as read on first play
    if (_currentLine == 0 && onMarkAsRead != null) {
      onMarkAsRead!(_articleId);
    }

    // Update media item with current line
    mediaItem.add(MediaItem(
      id: _articleId,
      title: _articleTitle,
      displayDescription: text.length > 100 ? '${text.substring(0, 97)}...' : text,
      extras: {
        'currentLine': _currentLine,
        'totalLines': _lines.length,
      },
    ));

    _updatePlaybackState(playing: true);

    // Save position
    if (onPositionChanged != null) {
      onPositionChanged!(_articleId, _currentLine);
    }

    try {
      await _tts.speak(text);
    } catch (_) {
      _updatePlaybackState(playing: false);
    }
  }

  Future<void> _speakNextLine() async {
    if (_lines.isEmpty) return;

    final nextLine = _currentLine + 1;

    if (nextLine >= _lines.length) {
      // Reached end of article
      _updatePlaybackState(playing: false);

      // Notify to navigate to next article
      if (onNavigateNext != null) {
        onNavigateNext!();
      }
      return;
    }

    _currentLine = nextLine;
    _currentLineSubject.add(_currentLine);

    await _speakCurrentLine();
  }

  Future<void> _speakPrevLine() async {
    if (_lines.isEmpty) return;

    final prevLine = _currentLine - 1;

    if (prevLine < 0) {
      // At beginning, notify to go to previous article
      await stop();
      if (onNavigatePrevious != null) {
        onNavigatePrevious!();
      }
      return;
    }

    _currentLine = prevLine;
    _currentLineSubject.add(_currentLine);

    await _speakCurrentLine();
  }

  void _updatePlaybackState({required bool playing}) {
    _isPlaying = playing;

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      processingState: AudioProcessingState.ready,
      playing: playing,
      updatePosition: Duration(seconds: _currentLine),
    ));
  }

  // Audio Service overrides

  @override
  Future<void> play() async {
    await _speakCurrentLine();
  }

  @override
  Future<void> pause() async {
    await _tts.stop();
    _updatePlaybackState(playing: false);

    // Save position
    if (onPositionChanged != null) {
      onPositionChanged!(_articleId, _currentLine);
    }
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
    _updatePlaybackState(playing: false);

    // Save position
    if (onPositionChanged != null) {
      onPositionChanged!(_articleId, _currentLine);
    }
  }

  @override
  Future<void> skipToNext() async {
    await _tts.stop();
    await _speakNextLine();
  }

  @override
  Future<void> skipToPrevious() async {
    await _tts.stop();
    await _speakPrevLine();
  }

  @override
  Future<void> seek(Duration position) async {
    final newLine = position.inSeconds.clamp(0, _lines.length - 1);
    _currentLine = newLine;
    _currentLineSubject.add(_currentLine);

    if (_isPlaying) {
      await _tts.stop();
      await _speakCurrentLine();
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    // Save position when task is removed
    if (onPositionChanged != null) {
      onPositionChanged!(_articleId, _currentLine);
    }
    await stop();
  }

  // Getters for reactive streams
  Stream<int> get currentLineStream => _currentLineSubject.stream;
  Stream<List<String>> get linesStream => _linesSubject.stream;

  int get currentLine => _currentLine;
  List<String> get lines => _lines;

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'setLines':
        if (extras != null && extras['lines'] is List<String>) {
          _lines = extras['lines'] as List<String>;
          _linesSubject.add(_lines);
        }
        break;
      case 'setCurrentLine':
        if (extras != null && extras['line'] is int) {
          _currentLine = (extras['line'] as int).clamp(0, _lines.length - 1);
          _currentLineSubject.add(_currentLine);
        }
        break;
    }
  }
}
