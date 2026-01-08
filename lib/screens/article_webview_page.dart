// lib/screens/article_webview_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../providers/settings_provider.dart';
import '../providers/rss_provider.dart';
import '../services/article_dao.dart';
import '../services/readability_service.dart';
import '../models/feed_item.dart';

/// Map MLKit TranslateLanguage -> BCP-47 (for model downloads)
String bcpFromTranslateLanguage(TranslateLanguage lang) {
  switch (lang) {
    case TranslateLanguage.english:
      return 'en';
    case TranslateLanguage.malay:
      return 'ms';
    case TranslateLanguage.chinese:
      return 'zh-CN';
    case TranslateLanguage.japanese:
      return 'ja';
    case TranslateLanguage.korean:
      return 'ko';
    case TranslateLanguage.indonesian:
      return 'id';
    case TranslateLanguage.thai:
      return 'th';
    case TranslateLanguage.vietnamese:
      return 'vi';
    case TranslateLanguage.arabic:
      return 'ar';
    case TranslateLanguage.french:
      return 'fr';
    case TranslateLanguage.spanish:
      return 'es';
    case TranslateLanguage.german:
      return 'de';
    case TranslateLanguage.portuguese:
      return 'pt';
    case TranslateLanguage.italian:
      return 'it';
    case TranslateLanguage.russian:
      return 'ru';
    case TranslateLanguage.hindi:
      return 'hi';
    default:
      // Fallback for languages we don't map explicitly (e.g. afrikaans)
      return 'en';
  }
}

/// Choose concrete TTS locale from short language code
String _ttsLocaleForCode(String code) {
  // Handle already-BCP47 codes (e.g., "en-US", "zh-CN")
  if (code.contains('-')) return code;

  switch (code) {
    case 'en':
      return 'en-US';
    case 'ms':
      return 'ms-MY';
    case 'zh':
      return 'zh-CN';
    case 'ja':
      return 'ja-JP';
    case 'ko':
      return 'ko-KR';
    case 'id':
      return 'id-ID';
    case 'th':
      return 'th-TH';
    case 'vi':
      return 'vi-VN';
    case 'ar':
      return 'ar-SA';
    case 'fr':
      return 'fr-FR';
    case 'es':
      return 'es-ES';
    case 'de':
      return 'de-DE';
    case 'pt':
      return 'pt-PT';
    case 'it':
      return 'it-IT';
    case 'ru':
      return 'ru-RU';
    case 'hi':
      return 'hi-IN';
    default:
      return 'en-US';
  }
}

/// Extract short language code from BCP-47 code (e.g., "zh-CN" -> "zh")
String _extractShortLangCode(String bcpCode) {
  if (!bcpCode.contains('-')) return bcpCode;
  return bcpCode.split('-').first;
}

// ---------- Chinese number helper (for TTS) ----------

String _toChineseNumber(String rawDigits) {
  int n = int.tryParse(rawDigits) ?? 0;
  if (n == 0) return '零';

  const smallUnits = ['', '十', '百', '千'];
  const bigUnits = ['', '万', '亿'];
  const digits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

  String sectionToCn(int sec) {
    String res = '';
    int unitPos = 0;
    bool zero = false;
    while (sec > 0) {
      final v = sec % 10;
      if (v == 0) {
        if (!zero && res.isNotEmpty) {
          res = '零$res';
        }
        zero = true;
      } else {
        res = digits[v] + smallUnits[unitPos] + res;
        zero = false;
      }
      unitPos++;
      sec ~/= 10;
    }
    return res;
  }

  String result = '';
  int unitPos = 0;
  while (n > 0) {
    int section = n % 10000;
    if (section != 0) {
      String sectionStr = sectionToCn(section) + bigUnits[unitPos];
      result = sectionStr + result;
    } else {
      if (!result.startsWith('零')) {
        result = '零$result';
      }
    }
    unitPos++;
    n ~/= 10000;
  }

  result = result.replaceAll(RegExp(r'零+$'), '');
  result = result.replaceAll('零零', '零');
  return result;
}

/// Normalize numbers, date/time etc for TTS in target language
String _normalizeForTts(String text, String langCode) {
  String s = text;

  if (langCode.startsWith('zh')) {
    // 2025-10-30 -> 2025年10月30日
    s = s.replaceAllMapped(
      RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'),
      (m) =>
          '${_toChineseNumber(m[1]!)}年${_toChineseNumber(m[2]!)}月${_toChineseNumber(m[3]!)}日',
    );
    // 14:05 -> 14点05分
    s = s.replaceAllMapped(
      RegExp(r'(\d{1,2}):(\d{2})'),
      (m) => '${_toChineseNumber(m[1]!)}点${_toChineseNumber(m[2]!)}分',
    );
    // 12% -> 百分之十二
    s = s.replaceAllMapped(
      RegExp(r'(\d+)%'),
      (m) => '百分之${_toChineseNumber(m[1]!)}',
    );
    // units & currency
    s = s.replaceAll('km/h', '公里每小时').replaceAll(RegExp(r'\bkm\b'), '公里');
    s = s.replaceAll('USD', '美元').replaceAll(RegExp(r'\$'), '美元');
    // generic numbers
    s = s.replaceAllMapped(
      RegExp(r'\d+'),
      (m) => _toChineseNumber(m[0]!),
    );
  } else if (langCode == 'ja') {
    s = s.replaceAllMapped(
      RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'),
      (m) => '${m[1]}年${m[2]}月${m[3]}日',
    );
    s = s.replaceAllMapped(
      RegExp(r'(\d{1,2}):(\d{2})'),
      (m) => '${m[1]}時${m[2]}分',
    );
    s = s.replaceAll('km/h', 'キロ毎時').replaceAll(RegExp(r'\bkm\b'), 'キロ');
    s = s.replaceAll('USD', '米ドル').replaceAll(RegExp(r'\$'), 'ドル');
  } else if (langCode == 'ko') {
    s = s.replaceAllMapped(
      RegExp(r'(\d{1,2}):(\d{2})'),
      (m) => '${m[1]}시 ${m[2]}분',
    );
    s = s.replaceAll('km/h', '시속 킬로미터').replaceAll(RegExp(r'\bkm\b'), '킬로미터');
    s = s.replaceAll('USD', '미 달러').replaceAll(RegExp(r'\$'), '달러');
  }

  return s;
}

// =================== Widget ===================

class ArticleWebviewPage extends StatefulWidget {
  final String url;
  final String? title; // optional RSS/article title to include in reading
  final String? articleId;
  final String? initialMainText;
  final String? initialImageUrl;

  // List of articles from news page (respects sort order and filters, excludes hidden)
  final List<FeedItem> allArticles;

  // Auto-play when opened from auto-advance
  final bool autoPlay;

  const ArticleWebviewPage({
    super.key,
    required this.url,
    this.title,
    this.articleId,
    this.initialMainText,
    this.initialImageUrl,
    this.allArticles = const [],
    this.autoPlay = false,
  });

  @override
  State<ArticleWebviewPage> createState() => _ArticleWebviewPageState();
}

// Global TTS instance that persists across widget rebuilds (lazy initialization)
FlutterTts? _globalTtsInstance;
FlutterLocalNotificationsPlugin? _globalNotificationsInstance;

FlutterTts get _globalTts {
  if (_globalTtsInstance == null) {
    _globalTtsInstance = FlutterTts();
    _globalTtsInstance!.setSharedInstance(true);
  }
  return _globalTtsInstance!;
}

FlutterLocalNotificationsPlugin get _globalNotifications {
  if (_globalNotificationsInstance == null) {
    _globalNotificationsInstance = FlutterLocalNotificationsPlugin();
  }
  return _globalNotificationsInstance!;
}

// Global state for background playback
class _TtsState {
  List<String> lines = [];
  int currentLine = 0;
  bool isPlaying = false;
  String articleId = '';
  String articleTitle = '';
  bool notificationsInitialized = false;
  bool ttsInitialized = false;
  bool readerModeOn = false; // Remember reader mode state
  bool autoTranslateEnabled = false;
  String translateLangCode = 'off';

  // Article list for continuous reading
  List<FeedItem> allArticles = [];
  int currentArticleIndex = -1;

  // Database access for loading next articles
  ArticleDao? articleDao;
  RssProvider? rssProvider;

  // Callback for widget-specific actions (set by current widget instance)
  void Function(String actionId)? widgetActionHandler;

  // Callback for widget-specific completion handling (highlighting, etc.)
  Future<void> Function()? widgetCompletionHandler;

  // Callback for auto-translate (set by current widget instance)
  Future<void> Function(List<String> lines)? autoTranslateCallback;

  static final _TtsState instance = _TtsState._internal();
  _TtsState._internal();
}

// Global notification action handler (works even when widget is disposed)
@pragma('vm:entry-point')
void _handleGlobalNotificationAction(NotificationResponse response) {
  final actionId = response.actionId ?? '';
  final state = _TtsState.instance;

  // Try to delegate to widget-specific handler first (if widget is active)
  if (state.widgetActionHandler != null) {
    try {
      state.widgetActionHandler!(actionId);
      return;
    } catch (_) {
      // Widget handler failed, fall back to global handler
    }
  }

  // Global handler for background playback
  switch (actionId) {
    case 'play_pause':
      if (state.isPlaying) {
        _globalTts.stop();
        state.isPlaying = false;
        if (state.lines.isNotEmpty && state.currentLine >= 0 && state.currentLine < state.lines.length) {
          unawaited(_showReadingNotificationGlobal(state.lines[state.currentLine]));
        }
      } else {
        unawaited(_speakCurrentLineGlobal());
      }
      break;
    case 'previous':
      _globalTts.stop();
      if (state.currentLine > 0) {
        state.currentLine--;
        unawaited(_speakCurrentLineGlobal());
      }
      break;
    case 'next':
      _globalTts.stop();
      unawaited(_speakNextLineGlobal());
      break;
    default:
      break;
  }
}

// Global function to load next article content from database
Future<bool> _loadNextArticleGlobal() async {
  final state = _TtsState.instance;

  // Check if we have a next article
  if (state.allArticles.isEmpty || state.currentArticleIndex < 0) return false;

  final nextIndex = state.currentArticleIndex + 1;
  if (nextIndex >= state.allArticles.length) return false;

  final nextArticle = state.allArticles[nextIndex];

  // Try to load cached content from database
  if (state.articleDao == null) return false;

  try {
    final row = await state.articleDao!.findById(nextArticle.id);
    if (row == null) return false;

    final text = (row.mainText ?? '').trim();
    if (text.isEmpty) return false;

    // Build lines list: header + content
    final rawParagraphs = text
        .split('\n\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // Group paragraphs into chunks for smoother TTS reading
    final chunkedLines = <String>[];
    const chunkSize = 3; // Speak 3 paragraphs at a time
    for (int i = 0; i < rawParagraphs.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, rawParagraphs.length);
      final chunk = rawParagraphs.sublist(i, end).join(' '); // Join with space for continuous reading
      chunkedLines.add(chunk);
    }

    final combined = <String>[];
    final header = nextArticle.title.trim();
    if (header.isNotEmpty) {
      combined.add(header);
    }
    combined.addAll(chunkedLines);

    if (combined.isEmpty) return false;

    // Update global state with next article
    state.lines = combined;
    state.currentLine = 0;
    state.articleId = nextArticle.id;
    state.articleTitle = nextArticle.title;
    state.currentArticleIndex = nextIndex;

    // Mark article as read
    if (state.rssProvider != null) {
      try {
        state.rssProvider!.markRead(nextArticle, read: 1);
      } catch (_) {
        // Ignore errors
      }
    }

    // Save position for new article
    try {
      await state.articleDao!.updateReadingPosition(nextArticle.id, 0);
    } catch (_) {
      // Ignore errors
    }

    // Call auto-translate callback if available
    if (state.autoTranslateCallback != null) {
      try {
        await state.autoTranslateCallback!(state.lines);
      } catch (_) {
        // Ignore translation errors
      }
    }

    return true;
  } catch (_) {
    return false;
  }
}

// Global function to speak next line (works even when widget is disposed)
Future<void> _speakNextLineGlobal({bool auto = false}) async {
  final state = _TtsState.instance;
  if (state.lines.isEmpty) return;

  final nextLine = state.currentLine + 1;

  if (nextLine >= state.lines.length) {
    // Reached end of current article
    // Try to load and play next article automatically
    final loaded = await _loadNextArticleGlobal();
    if (loaded) {
      // Successfully loaded next article, continue playing
      await _speakCurrentLineGlobal();
    } else {
      // No more articles, stop playing
      state.isPlaying = false;
      if (state.lines.isNotEmpty && state.currentLine >= 0 && state.currentLine < state.lines.length) {
        unawaited(_showReadingNotificationGlobal(state.lines[state.currentLine]));
      }
    }
    return;
  }

  state.currentLine = nextLine;
  await _speakCurrentLineGlobal();
}

// Global function to speak current line
Future<void> _speakCurrentLineGlobal() async {
  final state = _TtsState.instance;
  if (state.lines.isEmpty || state.currentLine >= state.lines.length || state.currentLine < 0) {
    return;
  }

  final text = state.lines[state.currentLine].trim();
  if (text.isEmpty) {
    await _speakNextLineGlobal(auto: true);
    return;
  }

  state.isPlaying = true;
  await _showReadingNotificationGlobal(text);
  await _globalTts.stop();
  // Speech rate should already be set by the widget, but ensure it's set
  // (The rate persists in _globalTts once set, so this is just a safety check)
  await _globalTts.speak(text);
}

// Global function to show notification
Future<void> _showReadingNotificationGlobal(String lineText) async {
  final state = _TtsState.instance;
  final title = state.articleTitle.isNotEmpty ? state.articleTitle : 'Reading article';

  // Show line position and optionally article progress
  String position = '${state.currentLine + 1}/${state.lines.length}';
  if (state.allArticles.isNotEmpty && state.currentArticleIndex >= 0) {
    position += ' • Article ${state.currentArticleIndex + 1}/${state.allArticles.length}';
  }

  final displayText = lineText.length > 100
      ? '${lineText.substring(0, 97)}...'
      : lineText;

  final List<AndroidNotificationAction> actions = [
    const AndroidNotificationAction(
      'previous',
      'Previous',
      icon: DrawableResourceAndroidBitmap('ic_skip_previous'),
      showsUserInterface: false,
    ),
    AndroidNotificationAction(
      'play_pause',
      state.isPlaying ? 'Pause' : 'Play',
      icon: DrawableResourceAndroidBitmap(state.isPlaying ? 'ic_pause' : 'ic_play'),
      showsUserInterface: false,
    ),
    const AndroidNotificationAction(
      'next',
      'Next',
      icon: DrawableResourceAndroidBitmap('ic_skip_next'),
      showsUserInterface: false,
    ),
  ];

  final android = AndroidNotificationDetails(
    'reading_channel',
    'Reading',
    channelDescription: 'Controls for text-to-speech reading.',
    importance: Importance.low,
    priority: Priority.low,
    ongoing: true,
    onlyAlertOnce: true,
    autoCancel: false,
    showWhen: true,
    usesChronometer: state.isPlaying,
    styleInformation: const MediaStyleInformation(
      htmlFormatContent: true,
      htmlFormatTitle: true,
    ),
    actions: actions,
    subText: position,
    ticker: 'Reading: $title',
  );

  const ios = DarwinNotificationDetails(
    presentAlert: false,
    presentSound: false,
    presentBadge: false,
  );

  await _globalNotifications.show(
    22,
    title,
    displayText,
    NotificationDetails(android: android, iOS: ios),
  );
}

class _ArticleWebviewPageState extends State<ArticleWebviewPage> with WidgetsBindingObserver {
  late final WebViewController _controller;

  bool _disposed = false;

  bool _isLoading = true;
  bool _readerOn = false;
  bool _paywallLikely = false;
  bool _readerHintVisible = false;
  bool _readerHintDismissed = false;
  // Reader content (one line per highlightable/speakable chunk)
  final List<String> _lines = [];
  List<String>? _originalLinesCache; // for reverse after translation
  // Hero image from Readability result (used in reader HTML)
  String? _heroImageUrl;

  // Language detection cache: maps line index to detected language code
  final Map<int, String> _languageCache = {};

  // Use global state for TTS (persists after dispose)
  _TtsState get _ttsState => _TtsState.instance;
  int get _currentLine => _ttsState.currentLine;
  set _currentLine(int value) => _ttsState.currentLine = value;
  bool get _isPlaying => _ttsState.isPlaying;
  set _isPlaying(bool value) => _ttsState.isPlaying = value;

  // Auto-advance state
  Timer? _autoAdvanceTimer;

  // Periodic position save timer
  Timer? _periodicSaveTimer;

  // Periodic highlight sync timer
  Timer? _periodicHighlightSyncTimer;
  int _lastSyncedLine = -1;

  // Translation state
  bool _isTranslating = false;
  bool _isTranslatedView = false;
  TranslateLanguage? _srcLangDetected;
  String? _articlePrimaryLanguage; // Primary language for this article (detected once, used throughout)
  SettingsProvider? _settings;
  VoidCallback? _settingsListener;
  static const int _readingNotificationId = 22;
  String? _webHighlightText;

  // Highlight operation tracking (to cancel stale highlights during rapid navigation)
  int _highlightSequence = 0;

  Future<void> _highlightCurrentLineAfterDelay() async {
    if (!mounted) return;
    if (_lines.isEmpty || _currentLine < 0 || _currentLine >= _lines.length) {
      return;
    }

    // Use longer delays to ensure webview is fully loaded when navigating back
    final delay = _readerOn
        ? const Duration(milliseconds: 500)
        : const Duration(milliseconds: 1200);

    await Future.delayed(delay);
    if (!mounted) return;

    // Use immediate highlighting mode (pass force parameter)
    await _highlightLineImmediate(_currentLine);
  }

  /// Highlight line immediately without checking _isPlaying state
  /// Used when returning to the article from navigation
  Future<void> _highlightLineImmediate(int index) async {
    if (!mounted) return;

    final settings = context.read<SettingsProvider>();
    if (!settings.highlightText) return;

    _highlightSequence++;

    if (_readerOn) {
      if (_webHighlightText != null) {
        setState(() => _webHighlightText = null);
      }

      // Immediate highlight without retries
      try {
        await _controller.runJavaScript(
          'window.flutterHighlightLine && window.flutterHighlightLine($index);',
        );
      } catch (e) {
        // Silently continue
      }
    } else {
      // Web mode highlighting
      if (index < 0 || index >= _lines.length) return;
      final text = _lines[index].trim();
      if (text.isEmpty) return;

      if (mounted) {
        setState(() => _webHighlightText = text);
      }

      try {
        await _highlightInWebPage(text);
      } catch (e) {
        // Silently continue
      }
    }
  }

  Future<bool> _handleBackNavigation() async {
    if (!mounted) return true;

    // Save reading position before leaving
    await _saveReadingPosition();

    // Allow back navigation without stopping reading
    // TTS will continue in background, controlled via notification
    return true;
  }

  void _initTtsHandlers() {
    final state = _TtsState.instance;

    // Only initialize handlers once globally
    if (state.ttsInitialized) {
      // Handlers already initialized, but update speech rate from current settings
      unawaited(_applySpeechRateFromSettings());
      return;
    }

    // Set default values (will be overridden by settings)
    _globalTts.setSpeechRate(0.5);
    _globalTts.setPitch(1.0);

    // Enable background audio
    _globalTts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        IosTextToSpeechAudioCategoryOptions.duckOthers,
      ],
      IosTextToSpeechAudioMode.voicePrompt,
    );

    _globalTts.setCompletionHandler(() async {
      final s = _TtsState.instance;

      // Continue playing in background using global function
      if (!s.isPlaying) {
        // Update notification to paused
        if (s.lines.isNotEmpty && s.currentLine >= 0 && s.currentLine < s.lines.length) {
          unawaited(_showReadingNotificationGlobal(s.lines[s.currentLine]));
        }
        return;
      }

      // Try to use widget-specific completion handler first (includes highlighting)
      if (s.widgetCompletionHandler != null) {
        try {
          await s.widgetCompletionHandler!();
          return;
        } catch (_) {
          // Widget handler failed, fall back to global handler
        }
      }

      // Fallback: global handler for background playback (no highlighting)
      await _speakNextLineGlobal(auto: true);
    });

    _globalTts.setCancelHandler(() {
      // Don't set isPlaying = false here, as we often call stop() to skip to next line
      // isPlaying will be managed by the play/stop button handlers
      // Update notification when cancelled
      final s = _TtsState.instance;
      if (!s.isPlaying && s.lines.isNotEmpty && s.currentLine >= 0 && s.currentLine < s.lines.length) {
        unawaited(_showReadingNotificationGlobal(s.lines[s.currentLine]));
      }
    });

    state.ttsInitialized = true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initWebView();

    // Initialize TTS handlers only once globally
    _initTtsHandlers();

    // Register this widget's notification action handler
    _ttsState.widgetActionHandler = _handleWidgetNotificationAction;

    // Register this widget's completion handler (for highlighting during continuous playback)
    _ttsState.widgetCompletionHandler = _handleWidgetCompletion;

    // Register auto-translate callback for background TTS
    _ttsState.autoTranslateCallback = _handleGlobalAutoTranslate;

    // Provide database and provider access to global state for continuous reading
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ttsState.articleDao = context.read<ArticleDao>();
      _ttsState.rssProvider = context.read<RssProvider>();
    });

    // Update global article list and current index for continuous reading
    _ttsState.allArticles = widget.allArticles;
    if (widget.articleId != null && widget.allArticles.isNotEmpty) {
      final index = widget.allArticles.indexWhere((a) => a.id == widget.articleId);
      if (index >= 0) {
        _ttsState.currentArticleIndex = index;
      }
    }

    // Check if opening a different article - if so, stop TTS and clear state
    final currentArticleId = widget.articleId ?? '';
    final globalArticleId = _ttsState.articleId;
    final isDifferentArticle = globalArticleId.isNotEmpty &&
                                currentArticleId.isNotEmpty &&
                                globalArticleId != currentArticleId;

    if (isDifferentArticle) {
      // Stop TTS playback for the previous article
      _globalTts.stop();
      _ttsState.isPlaying = false;
      _ttsState.currentLine = 0;
      _ttsState.lines.clear();
      _ttsState.articleId = '';
      _ttsState.articleTitle = '';
      _ttsState.readerModeOn = false; // Reset reader mode for new article
      // Clear the notification
      unawaited(_clearReadingNotification());

      // Clear article language cache for new article
      _articlePrimaryLanguage = null;
      _languageCache.clear();
    }

    _attachSettingsListener();
    unawaited(_initNotifications());
    // Preload Readability text in background so TTS/translate work in both modes
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Determine initial view mode
      final settings = context.read<SettingsProvider>();
      final bool shouldOpenInReaderMode;

      // If returning to the same article, restore previous reader mode state
      final isSameArticle = currentArticleId.isNotEmpty &&
                            globalArticleId.isNotEmpty &&
                            globalArticleId == currentArticleId;

      if (isSameArticle) {
        // Restore reader mode from global state
        shouldOpenInReaderMode = _ttsState.readerModeOn;
      } else {
        // New article - use settings preference
        shouldOpenInReaderMode = settings.displaySummary;
      }

      if (shouldOpenInReaderMode) {
        // Open in reader mode (summary view)
        setState(() => _readerOn = true);
        await _loadReaderContent();
      }

      await _ensureLinesLoaded();

      // Auto-translate if enabled (after lines are loaded)
      await _autoTranslateIfEnabled();

      final hasValidLine =
          _lines.isNotEmpty && _currentLine >= 0 && _currentLine < _lines.length;

      // If TTS is already running in the background, immediately show the
      // highlight at the active line when returning to this page.
      if (hasValidLine && _isPlaying) {
        // Initialize sync tracker with current global line
        _lastSyncedLine = _currentLine;
        await _highlightCurrentLineAfterDelay();
        // Start syncing highlights with global state during playback
        _startPeriodicHighlightSync();
      }

      // Auto-start playing if requested (e.g., from auto-advance)
      if (widget.autoPlay && hasValidLine) {
        await _speakCurrentLine();
      } else if (hasValidLine && !_isPlaying) {
        // If returning to a saved position (or starting fresh), show highlight
        await _highlightCurrentLineAfterDelay();
      }
    });
  }
  void _attachSettingsListener() {
    // Apply speech rate immediately on init (synchronously)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _settings = context.read<SettingsProvider>();
      _settingsListener = () {
        // When settings change, apply immediately
        if (mounted) {
          _ttsState.autoTranslateEnabled = _settings?.autoTranslate ?? false;
          _ttsState.translateLangCode = _settings?.translateLangCode ?? 'off';
          unawaited(_applySpeechRateFromSettings());
        }
      };
      _ttsState.autoTranslateEnabled = _settings?.autoTranslate ?? false;
      _ttsState.translateLangCode = _settings?.translateLangCode ?? 'off';
      // Apply initial speech rate from settings
      unawaited(_applySpeechRateFromSettings());
      // Add listener for future changes
      _settings?.addListener(_settingsListener!);
    });
  }

  Future<void> _applySpeechRateFromSettings({bool restartIfPlaying = true}) async {
    if (!mounted) return;
    try {
      final settings = _settings ?? context.read<SettingsProvider>();
      _settings ??= settings;
      final rate = settings.ttsSpeechRate;

      debugPrint('🔊 Applying TTS speech rate: $rate (playing: $_isPlaying)');

      // Always apply the speech rate to the global TTS instance
      // The new rate will apply to the next line when it starts speaking
      await _globalTts.setSpeechRate(rate);

      debugPrint('✅ TTS speech rate set to: $rate');

      // Don't restart current line - let it finish at old speed
      // New speed will apply automatically on next line
    } catch (e) {
      debugPrint('❌ Error applying TTS speech rate: $e');
      // Context might not be available yet, try again later
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_applySpeechRateFromSettings(restartIfPlaying: restartIfPlaying));
        }
      });
    }
  }
  /// Choose a concrete voice for the BCP language code (e.g., 'zh-CN')
  /// Choose a concrete voice for the BCP language code (e.g., 'zh-CN')
  Future<void> _applyTtsLocale(String bcpCode) async {
    await _globalTts.setLanguage(_ttsLocaleForCode(bcpCode));
    try {
      final List<dynamic>? voices = await _globalTts.getVoices;
      if (voices == null || voices.isEmpty) return;

      final lc = bcpCode.toLowerCase();
      final base = lc.split('-').first;

      // Normalize voices into a list of Map<String, dynamic>
      final List<Map<String, dynamic>> parsed =
          voices.whereType<Map>().map<Map<String, dynamic>>((m) {
        final map = <String, dynamic>{};
        (m as Map).forEach((key, value) {
          map[key.toString()] = value;
        });
        return map;
      }).toList();

      if (parsed.isEmpty) return;

      Map<String, dynamic> chosen = parsed.firstWhere(
        (v) => (v['locale'] ?? '').toString().toLowerCase() == lc,
        orElse: () => parsed.firstWhere(
          (v) => (v['locale'] ?? '').toString().toLowerCase().startsWith(base),
          orElse: () => parsed.first,
        ),
      );

      if (chosen.isEmpty) return;

      await _globalTts.setVoice({
        'name': chosen['name'],
        'locale': chosen['locale'],
      });
    } catch (_) {
      // ignore if voices are not supported or any error occurs
    }
  }

  // ---------------- WebView + Reader ----------------

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted || _disposed) return;
            setState(() => _isLoading = true);
          },
          onPageFinished: (url) async {
            if (!mounted || _disposed) return;
            setState(() => _isLoading = false);

            // Automatically remove paywall overlays when page finishes loading
            // This helps user see full content even when not in reader mode
            await Future.delayed(const Duration(milliseconds: 1000));
            if (!mounted || _disposed) return;
            await _removePaywallOverlays();
          },
        ),
      );

    // Default: show full website
    _controller.loadRequest(Uri.parse(widget.url));
  }

  Future<void> _initNotifications() async {
    // Only initialize once globally to avoid delays
    if (_TtsState.instance.notificationsInitialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _globalNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _handleGlobalNotificationAction,
      onDidReceiveBackgroundNotificationResponse: _handleGlobalNotificationAction,
    );

    _TtsState.instance.notificationsInitialized = true;
  }

  void _handleWidgetNotificationAction(String actionId) {
    // Widget-specific notification action handler (called from global handler)
    // Only handles actions when widget is mounted and active
    if (!mounted || _disposed) return;

    final state = _TtsState.instance;

    switch (actionId) {
      case 'play_pause':
        if (state.isPlaying) {
          unawaited(_stopSpeaking());
        } else {
          unawaited(_speakCurrentLine());
        }
        setState(() {});
        break;
      case 'previous':
        unawaited(_speakPrevLine());
        break;
      case 'next':
        _globalTts.stop();
        unawaited(_speakNextLine());
        break;
      default:
        break;
    }
  }

  Future<void> _handleWidgetCompletion() async {
    // Widget-specific completion handler (called from global TTS completion handler)
    // This enables highlighting during continuous playback even after navigation
    if (!mounted || _disposed) return;

    // Call the instance method which includes highlighting
    await _speakNextLine(auto: true);
  }

  Future<void> _loadReaderContent() async {
    final shouldShowLoading = _lines.isEmpty;
    if (shouldShowLoading) {
      setState(() {
        _isLoading = true;
      });
    }

    await _ensureLinesLoaded();
    if (_lines.isEmpty) {
      if (mounted) {
        _readerOn = false;
        _isLoading = false;
      }
      await _controller.loadRequest(Uri.parse(widget.url));
      return;
    }

    final html = _buildReaderHtml(_lines, _heroImageUrl);
    await _controller.loadRequest(
      Uri.dataFromString(html, mimeType: 'text/html', encoding: utf8),
    );

    if (mounted && shouldShowLoading) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Highlight the current line in our reader HTML.
  /// Only in Reader mode AND when highlightText setting is ON.
  Future<void> _highlightLine(int index) async {
    if (!mounted) return;

    final settings = context.read<SettingsProvider>();
    if (!settings.highlightText) return;

    // Increment sequence to cancel any in-progress highlight operations
    _highlightSequence++;
    final currentSequence = _highlightSequence;

    if (_readerOn) {
      // Clear any lingering overlay highlight when we switch to reader mode
      if (_webHighlightText != null) {
        setState(() => _webHighlightText = null);
      }

      // During active playback, highlight immediately without retries
      // This prevents delays from interfering with continuous playback
      if (_isPlaying) {
        // Immediate highlight during playback - no retries, no delays
        try {
          await _controller.runJavaScript(
            'window.flutterHighlightLine && window.flutterHighlightLine($index);',
          );
        } catch (e) {
          // Silently continue - next line will try again
        }
      } else {
        // When not playing, use retry logic for initial load reliability
        for (int attempt = 0; attempt < 3; attempt++) {
          // Check if this highlight operation has been superseded
          if (!mounted || !_readerOn || _highlightSequence != currentSequence) break;

          try {
            // Small delay to ensure DOM is ready (only on retry)
            if (attempt > 0) {
              await Future.delayed(Duration(milliseconds: 100 * attempt));
              // Check again after delay
              if (_highlightSequence != currentSequence) break;
            }

            final result = await _controller.runJavaScriptReturningResult(
              'window.flutterHighlightLine && window.flutterHighlightLine($index);',
            );

            // Check if the JavaScript function returned true (found the element)
            if (result == true || result.toString() == 'true') {
              break; // Success - exit retry loop
            }
          } catch (e) {
            // Continue to next attempt on error
          }
        }
      }
    } else {
      // Web mode highlighting with overlay
      if (index < 0 || index >= _lines.length) return;
      final text = _lines[index].trim();
      if (text.isEmpty) return;

      if (mounted) {
        setState(() => _webHighlightText = text);
      }

      // During active playback, highlight immediately without delay
      if (_isPlaying) {
        try {
          await _highlightInWebPage(text);
        } catch (e) {
          // Silently continue - next line will try again
        }
      } else {
        // When not playing, add delay for page load
        await Future.delayed(const Duration(milliseconds: 100));
        // Check if this operation has been superseded
        if (mounted && !_readerOn && _highlightSequence == currentSequence) {
          try {
            await _highlightInWebPage(text);
          } catch (e) {
            // Silently continue
          }
        }
      }
    }
  }

  Future<void> _highlightInWebPage(String text) async {
    try {
      final escaped = jsonEncode(text);
      final script = '''
(function(txt){
  if(!txt){return;}
  const cls='flutter-tts-highlight';

  // Remove old highlights
  document.querySelectorAll('mark.'+cls).forEach(m=>{
    const parent=m.parentNode;
    if(!parent){return;}
    parent.replaceChild(document.createTextNode(m.textContent||''), m);
    parent.normalize();
  });

  // Normalize search text (remove extra whitespace)
  const searchText = txt.trim().replace(/\\s+/g, ' ').toLowerCase();

  // Find all text-containing elements (paragraphs, divs, articles, etc.)
  const containers = Array.from(document.querySelectorAll('p, div, article, section, main, li, td, th, span, a, h1, h2, h3, h4, h5, h6'));

  for(let container of containers){
    // Get the combined text content of this container
    const containerText = container.textContent || '';
    const normalizedText = containerText.trim().replace(/\\s+/g, ' ').toLowerCase();

    // Check if search text is in this container
    const startIndex = normalizedText.indexOf(searchText);
    if(startIndex === -1) continue;

    // Found a match! Now highlight it
    try {
      // Create a tree walker to find all text nodes
      const walker = document.createTreeWalker(
        container,
        NodeFilter.SHOW_TEXT,
        null,
        false
      );

      let textNodes = [];
      let node;
      while(node = walker.nextNode()){
        if(node.nodeValue && node.nodeValue.trim()){
          textNodes.push(node);
        }
      }

      // Calculate character positions
      let charCount = 0;
      let startNode = null, startOffset = 0;
      let endNode = null, endOffset = 0;
      let searchEndIndex = startIndex + searchText.length;

      for(let textNode of textNodes){
        const nodeText = textNode.nodeValue || '';
        const nodeLength = nodeText.length;

        // Check if this node contains the start
        if(startNode === null && charCount + nodeLength > startIndex){
          startNode = textNode;
          startOffset = startIndex - charCount;
        }

        // Check if this node contains the end
        if(endNode === null && charCount + nodeLength >= searchEndIndex){
          endNode = textNode;
          endOffset = searchEndIndex - charCount;
          break;
        }

        charCount += nodeLength;
      }

      // Create range and highlight
      if(startNode && endNode){
        const range = document.createRange();
        range.setStart(startNode, Math.max(0, startOffset));
        range.setEnd(endNode, Math.min(endNode.nodeValue.length, endOffset));

        const mark = document.createElement('mark');
        mark.className = cls;
        mark.style.backgroundColor = 'rgba(255,235,59,0.4)';
        mark.style.padding = '2px 0';

        range.surroundContents(mark);
        mark.scrollIntoView({behavior:'smooth', block:'center'});
        return; // Found and highlighted, exit
      }
    } catch(e) {
      // If highlighting fails for this container, continue to next
      console.log('Highlight error:', e);
    }
  }

  // Fallback: Try simple text node search (original method)
  function simpleWalk(node){
    if(!node){return false;}
    if(node.nodeType===3){
      const nodeText = (node.data || '').toLowerCase();
      const searchLower = searchText.toLowerCase();
      const index = nodeText.indexOf(searchLower);
      if(index !== -1){
        try{
          const range = document.createRange();
          range.setStart(node, index);
          range.setEnd(node, index + searchText.length);
          const mark = document.createElement('mark');
          mark.className = cls;
          mark.style.backgroundColor = 'rgba(255,235,59,0.4)';
          range.surroundContents(mark);
          mark.scrollIntoView({behavior:'smooth', block:'center'});
          return true;
        }catch(e){}
      }
    }
    const children = Array.from(node.childNodes||[]);
    for(let i=0; i<children.length; i++){
      if(simpleWalk(children[i])) return true;
    }
    return false;
  }
  simpleWalk(document.body);
})($escaped);
''';
      await _controller.runJavaScript(script);
    } catch (_) {
      // ignore failures silently
    }
  }

  Future<void> _reloadReaderHtml({bool showLoading = false}) async {
    if (!_readerOn) return;
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }

    final html = _buildReaderHtml(_lines, _heroImageUrl);

    await _controller.loadRequest(
      Uri.dataFromString(html, mimeType: 'text/html', encoding: utf8),
    );

    if (showLoading && mounted) {
      setState(() => _isLoading = false);
    }

    // Highlight current line after reload (whether playing or not)
    if (_lines.isNotEmpty && _currentLine >= 0 && _currentLine < _lines.length) {
      // Small delay to let the HTML render
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted && _readerOn) {
        await _highlightLine(_currentLine);
      }
    }
  }

  String _buildReaderHtml(List<String> lines, String? heroUrl) {
    final buffer = StringBuffer();
    buffer.writeln('<html><head>'
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">');
    buffer.writeln('<style>'
        'body{margin:0;background:#fff;font-family:-apple-system,BlinkMacSystemFont,system-ui,Roboto,"Segoe UI",sans-serif;}'
        '.wrap{max-width:760px;margin:0 auto;padding:16px;}'
        'img.hero{width:100%;height:auto;border-radius:8px;margin-bottom:16px;object-fit:cover;}'
        'p{font-size:1.02rem;line-height:1.7;margin:0 0 1rem 0;}'
        'p.hl{background-color:rgba(255,235,59,0.4);}'
        // treat first line (index 0) as header
        'p[data-idx="0"]{font-size:1.25rem;font-weight:600;margin-bottom:1.2rem;}'
        '</style>');
    buffer.writeln('<script>'
        'window.flutterHighlightLine=function(index){'
        'try{'
        'var paras=document.querySelectorAll("p[data-idx]");'
        'var found=false;'
        'for(var i=0;i<paras.length;i++){'
        'var el=paras[i];'
        'var idx=parseInt(el.getAttribute("data-idx")||"-1");'
        'if(idx===index){'
        'el.classList.add("hl");'
        // Cancel any ongoing smooth scroll and use instant scroll for rapid navigation
        'if(window.scrollTimeout){clearTimeout(window.scrollTimeout);}'
        'el.scrollIntoView({behavior:"instant",block:"center"});'
        // Then apply a smooth scroll after a brief delay for better UX
        'window.scrollTimeout=setTimeout(function(){'
        'if(el.classList.contains("hl")){'
        'el.scrollIntoView({behavior:"smooth",block:"center"});'
        '}'
        '},50);'
        'found=true;'
        '}else{'
        'el.classList.remove("hl");'
        '}'
        '}'
        'return found;'
        '}catch(e){'
        'console.error("Highlight error:",e);'
        'return false;'
        '}'
        '};'
        '</script>');
    buffer.writeln('</head><body><div class="wrap">');

    if (heroUrl != null && heroUrl.isNotEmpty) {
      buffer.writeln('<img src="$heroUrl" class="hero" />');
    }

    for (var i = 0; i < lines.length; i++) {
      final p = lines[i];
      final escaped = p
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;');
      buffer.writeln('<p data-idx="$i">$escaped</p>');
    }

    buffer.writeln('</div></body></html>');
    return buffer.toString();
  }
  bool _isLikelyPreviewText(String text, bool pagePaywalled) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    final lower = trimmed.toLowerCase();
    final wordCount =
        trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    final previewMarkers = [
      'continue reading',
      'read more',
      'subscribe to read',
      'to continue reading',
      'log in to read',
      'sign in to continue',
      'unlock full article',
    ];

    // Check if markers appear at the END (last 200 chars), not anywhere in text
    final last200 = trimmed.length > 200 ? lower.substring(lower.length - 200) : lower;
    final hasMarkersAtEnd = previewMarkers.any(last200.contains);
    final trailingEllipsis = RegExp(r'(\.\.\.|…)$').hasMatch(trimmed);

    // Only consider it preview if markers at end OR ellipsis with short content
    if (hasMarkersAtEnd && wordCount < 200) return true;
    if (trailingEllipsis && wordCount < 150) return true;

    // Lowered from 180 to 100 - be more lenient for authenticated users
    // After paywall removal, even short content should be considered valid
    if (pagePaywalled && wordCount < 100) return true;

    return false;
  }
  // --------------- Translation helpers ---------------

  TranslateLanguage? _translateLanguageFromCode(String code) {
    switch (code) {
      case 'en':
        return TranslateLanguage.english;
      case 'ms':
        return TranslateLanguage.malay;
      case 'zh-CN':
      case 'zh-TW':
        return TranslateLanguage.chinese;
      case 'ja':
        return TranslateLanguage.japanese;
      case 'ko':
        return TranslateLanguage.korean;
      case 'id':
        return TranslateLanguage.indonesian;
      case 'th':
        return TranslateLanguage.thai;
      case 'vi':
        return TranslateLanguage.vietnamese;
      case 'ar':
        return TranslateLanguage.arabic;
      case 'fr':
        return TranslateLanguage.french;
      case 'es':
        return TranslateLanguage.spanish;
      case 'de':
        return TranslateLanguage.german;
      case 'pt':
        return TranslateLanguage.portuguese;
      case 'it':
        return TranslateLanguage.italian;
      case 'ru':
        return TranslateLanguage.russian;
      case 'hi':
        return TranslateLanguage.hindi;
      default:
        return null;
    }
  }

  Future<TranslateLanguage> _detectSourceLang() async {
    if (_srcLangDetected != null) return _srcLangDetected!;
    final sample = _lines.take(6).join(' ');
    final id = LanguageIdentifier(confidenceThreshold: 0.4);
    try {
      final code =
          await id.identifyLanguage(sample.isNotEmpty ? sample : 'Hello');
      TranslateLanguage lang = TranslateLanguage.english;
      if (code.startsWith('ms')) {
        lang = TranslateLanguage.malay;
      } else if (code.startsWith('zh')) {
        lang = TranslateLanguage.chinese;
      } else if (code.startsWith('ja')) {
        lang = TranslateLanguage.japanese;
      } else if (code.startsWith('ko')) {
        lang = TranslateLanguage.korean;
      } else if (code.startsWith('id')) {
        lang = TranslateLanguage.indonesian;
      } else if (code.startsWith('th')) {
        lang = TranslateLanguage.thai;
      } else if (code.startsWith('vi')) {
        lang = TranslateLanguage.vietnamese;
      } else if (code.startsWith('ar')) {
        lang = TranslateLanguage.arabic;
      } else if (code.startsWith('fr')) {
        lang = TranslateLanguage.french;
      } else if (code.startsWith('es')) {
        lang = TranslateLanguage.spanish;
      } else if (code.startsWith('de')) {
        lang = TranslateLanguage.german;
      } else if (code.startsWith('pt')) {
        lang = TranslateLanguage.portuguese;
      } else if (code.startsWith('it')) {
        lang = TranslateLanguage.italian;
      } else if (code.startsWith('ru')) {
        lang = TranslateLanguage.russian;
      } else if (code.startsWith('hi')) {
        lang = TranslateLanguage.hindi;
      }
      _srcLangDetected = lang;
      return lang;
    } catch (_) {
      return TranslateLanguage.english;
    } finally {
      id.close();
    }
  }

  /// Detect the primary language of the entire article (by analyzing first few lines)
  /// This language will be used consistently throughout the article for the same voice
  Future<String> _detectArticlePrimaryLanguage() async {
    // If already detected for this article, return cached value
    if (_articlePrimaryLanguage != null) {
      return _articlePrimaryLanguage!;
    }

    // Use first 5-10 lines (or all if fewer) to detect primary language
    final sampleLines = _lines.take(10).where((line) => line.trim().isNotEmpty).take(5);
    final sampleText = sampleLines.join(' ');

    if (sampleText.isEmpty) {
      _articlePrimaryLanguage = 'en-US';
      return 'en-US';
    }

    // Detect language using ML Kit
    final id = LanguageIdentifier(confidenceThreshold: 0.4);
    try {
      final code = await id.identifyLanguage(sampleText);

      // Map ML Kit language codes to BCP-47 codes
      String bcpCode = 'en-US'; // Default to English
      if (code.startsWith('ms')) {
        bcpCode = 'ms-MY';
      } else if (code.startsWith('zh')) {
        bcpCode = 'zh-CN';
      } else if (code.startsWith('ja')) {
        bcpCode = 'ja-JP';
      } else if (code.startsWith('ko')) {
        bcpCode = 'ko-KR';
      } else if (code.startsWith('id')) {
        bcpCode = 'id-ID';
      } else if (code.startsWith('th')) {
        bcpCode = 'th-TH';
      } else if (code.startsWith('vi')) {
        bcpCode = 'vi-VN';
      } else if (code.startsWith('ar')) {
        bcpCode = 'ar-SA';
      } else if (code.startsWith('fr')) {
        bcpCode = 'fr-FR';
      } else if (code.startsWith('es')) {
        bcpCode = 'es-ES';
      } else if (code.startsWith('de')) {
        bcpCode = 'de-DE';
      } else if (code.startsWith('pt')) {
        bcpCode = 'pt-PT';
      } else if (code.startsWith('it')) {
        bcpCode = 'it-IT';
      } else if (code.startsWith('ru')) {
        bcpCode = 'ru-RU';
      } else if (code.startsWith('hi')) {
        bcpCode = 'hi-IN';
      } else if (code.startsWith('en')) {
        bcpCode = 'en-US';
      }

      // Cache the result for this article
      _articlePrimaryLanguage = bcpCode;
      return bcpCode;
    } catch (_) {
      // On error, default to English
      _articlePrimaryLanguage = 'en-US';
      return 'en-US';
    } finally {
      id.close();
    }
  }

  Future<void> _toggleTranslateToSetting() async {
    final settings = context.read<SettingsProvider>();
    final code = settings.translateLangCode;

    if (code == 'off') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Translation disabled in Settings.')),
      );
      return;
    }

    await _ensureLinesLoaded();
    if (_lines.isEmpty) return;

    // already translated -> back to original
    if (_isTranslatedView) {
      if (_originalLinesCache != null) {
        final wasPlaying = _isPlaying;
        setState(() {
          _lines
            ..clear()
            ..addAll(_originalLinesCache!);
          _isTranslatedView = false;
          // Keep current line position when reverting translation
          _webHighlightText = null;
        });
        // Reset article language detection when un-translating
        _articlePrimaryLanguage = null;

        await _reloadReaderHtml(showLoading: true);
        await _applyTtsLocale('en');

        // If was playing before reverting translation, continue playing with original language
        if (wasPlaying && _lines.isNotEmpty && _currentLine >= 0 && _currentLine < _lines.length) {
          await _speakCurrentLine();
        }
      }
      return;
    }

    setState(() => _isTranslating = true);

    final target = _translateLanguageFromCode(code);
    if (target == null) {
      setState(() => _isTranslating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unsupported target language: $code')),
      );
      return;
    }

    // Detect source language from the article text
    final src = await _detectSourceLang();

    // ✅ Let OnDeviceTranslator handle model download internally
    final translator =
        OnDeviceTranslator(sourceLanguage: src, targetLanguage: target);

    _originalLinesCache ??= List<String>.from(_lines);
    final translated = <String>[];

    for (int i = 0; i < _lines.length; i++) {
      final line = _lines[i];

      // image marker line (we’re not using this right now, but keep logic)
      if (line.startsWith('__IMG__|')) {
        translated.add(line);
        continue;
      }

      final t = await translator.translateText(line);
      translated.add(t);
    }

    await translator.close();

    if (!mounted) return;

    final wasPlaying = _isPlaying;
    setState(() {
      _lines
        ..clear()
        ..addAll(translated);
      _isTranslatedView = true;
      _isTranslating = false;
      // Keep current line position when translating
      _webHighlightText = null;
    });
    // Reset article language detection when translating
    // This ensures the translated language is used consistently
    _articlePrimaryLanguage = null;

    await _reloadReaderHtml(showLoading: true);
    await _applyTtsLocale(code);

    // If was playing before translation, continue playing with new language
    if (wasPlaying && _lines.isNotEmpty && _currentLine >= 0 && _currentLine < _lines.length) {
      await _speakCurrentLine();
    }
  }

  /// Handle auto-translate for global TTS (background playback)
  /// This is called when loading next article during background TTS
  Future<void> _handleGlobalAutoTranslate(List<String> lines) async {
    final bool autoTranslateEnabled;
    final String translateLangCode;
    if (mounted) {
      final settings = context.read<SettingsProvider>();
      autoTranslateEnabled = settings.autoTranslate;
      translateLangCode = settings.translateLangCode;
    } else {
      autoTranslateEnabled = _ttsState.autoTranslateEnabled;
      translateLangCode = _ttsState.translateLangCode;
    }

    // Check if auto-translate is enabled AND translation language is set
    if (!autoTranslateEnabled || translateLangCode == 'off') {
      return;
    }

    if (lines.isEmpty) return;

    final code = translateLangCode;
    final target = _translateLanguageFromCode(code);
    if (target == null) return;

    try {
      // Detect source language from the first few lines
      final sampleText = lines.take(5).join(' ');
      final id = LanguageIdentifier(confidenceThreshold: 0.4);
      String mlKitCode = await id.identifyLanguage(sampleText);
      id.close();

      // Map ML Kit codes to TranslateLanguage
      TranslateLanguage src = TranslateLanguage.english;
      if (mlKitCode.startsWith('ms')) {
        src = TranslateLanguage.malay;
      } else if (mlKitCode.startsWith('zh')) {
        src = TranslateLanguage.chinese;
      } else if (mlKitCode.startsWith('ja')) {
        src = TranslateLanguage.japanese;
      } else if (mlKitCode.startsWith('ko')) {
        src = TranslateLanguage.korean;
      } else if (mlKitCode.startsWith('id')) {
        src = TranslateLanguage.indonesian;
      } else if (mlKitCode.startsWith('th')) {
        src = TranslateLanguage.thai;
      } else if (mlKitCode.startsWith('vi')) {
        src = TranslateLanguage.vietnamese;
      } else if (mlKitCode.startsWith('ar')) {
        src = TranslateLanguage.arabic;
      } else if (mlKitCode.startsWith('fr')) {
        src = TranslateLanguage.french;
      } else if (mlKitCode.startsWith('es')) {
        src = TranslateLanguage.spanish;
      } else if (mlKitCode.startsWith('de')) {
        src = TranslateLanguage.german;
      } else if (mlKitCode.startsWith('pt')) {
        src = TranslateLanguage.portuguese;
      } else if (mlKitCode.startsWith('it')) {
        src = TranslateLanguage.italian;
      } else if (mlKitCode.startsWith('ru')) {
        src = TranslateLanguage.russian;
      } else if (mlKitCode.startsWith('hi')) {
        src = TranslateLanguage.hindi;
      }

      // Create translator
      final translator = OnDeviceTranslator(sourceLanguage: src, targetLanguage: target);

      final translated = <String>[];
      for (final line in lines) {
        if (line.startsWith('__IMG__|')) {
          translated.add(line);
          continue;
        }
        final t = await translator.translateText(line);
        translated.add(t);
      }

      await translator.close();

      // Update global state with translated lines
      _ttsState.lines = translated;

      // Update TTS locale for the new language
      await _applyTtsLocale(code);
    } catch (_) {
      // Silent failure - auto-translate is optional
    }
  }

  /// Auto-translate article if autoTranslate setting is enabled
  /// Called automatically when opening article or switching to next article
  Future<void> _autoTranslateIfEnabled() async {
    if (!mounted) return;

    final settings = context.read<SettingsProvider>();

    // Check if auto-translate is enabled AND translation language is set
    if (!settings.autoTranslate || settings.translateLangCode == 'off') {
      return;
    }

    // Don't auto-translate if already translated
    if (_isTranslatedView) return;

    // Don't auto-translate if currently translating
    if (_isTranslating) return;

    await _ensureLinesLoaded();
    if (_lines.isEmpty) return;

    final code = settings.translateLangCode;
    final target = _translateLanguageFromCode(code);
    if (target == null) return;

    setState(() => _isTranslating = true);

    try {
      // Detect source language from the article text
      final src = await _detectSourceLang();

      // Create translator
      final translator =
          OnDeviceTranslator(sourceLanguage: src, targetLanguage: target);

      _originalLinesCache ??= List<String>.from(_lines);
      final translated = <String>[];

      for (int i = 0; i < _lines.length; i++) {
        final line = _lines[i];

        // image marker line (we're not using this right now, but keep logic)
        if (line.startsWith('__IMG__|')) {
          translated.add(line);
          continue;
        }

        final t = await translator.translateText(line);
        translated.add(t);
      }

      await translator.close();

      if (!mounted) return;

      final wasPlaying = _isPlaying;
      setState(() {
        _lines
          ..clear()
          ..addAll(translated);
        _isTranslatedView = true;
        _isTranslating = false;
        _webHighlightText = null;
      });

      // Reset article language detection when translating
      _articlePrimaryLanguage = null;

      await _reloadReaderHtml(showLoading: false); // Don't show loading spinner for auto-translate
      await _applyTtsLocale(code);

      // If was playing before translation, continue playing with new language
      if (wasPlaying && _lines.isNotEmpty && _currentLine >= 0 && _currentLine < _lines.length) {
        await _speakCurrentLine();
      }
    } catch (e) {
      // Silent failure - auto-translate is optional
      if (mounted) {
        setState(() => _isTranslating = false);
      }
    }
  }

  // --------------- TTS playback ---------------

  Future<int?> _loadSavedReadingPosition() async {
    final articleId = widget.articleId;
    if (articleId == null || articleId.isEmpty) return null;

    try {
      final dao = context.read<ArticleDao>();
      final row = await dao.findById(articleId);
      return row?.readingPosition;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveReadingPosition() async {
    final articleId = widget.articleId;
    if (articleId == null || articleId.isEmpty) return;

    try {
      final dao = context.read<ArticleDao>();
      await dao.updateReadingPosition(articleId, _currentLine);
    } catch (_) {
      // Ignore errors when saving position
    }
  }

  Future<ArticleReadabilityResult?> _loadCachedContent() async {
    final cachedText = widget.initialMainText?.trim() ?? '';
    final cachedImage = widget.initialImageUrl?.trim() ?? '';
    if (cachedText.isNotEmpty || cachedImage.isNotEmpty) {
      return ArticleReadabilityResult(
        mainText: cachedText.isNotEmpty ? cachedText : null,
        imageUrl: cachedImage.isNotEmpty ? cachedImage : null,
        pageTitle: widget.title,
      );
    }

    final articleId = widget.articleId;
    if (articleId == null || articleId.isEmpty) return null;

    try {
      final dao = context.read<ArticleDao>();
      final row = await dao.findById(articleId);
      if (row == null) return null;

      final storedText = row.mainText?.trim() ?? '';
      final storedImage = row.imageUrl?.trim() ?? '';
      if (storedText.isEmpty && storedImage.isEmpty) return null;

      return ArticleReadabilityResult(
        mainText: storedText.isNotEmpty ? storedText : null,
        imageUrl: storedImage.isNotEmpty ? storedImage : null,
        pageTitle: row.title,
      );
    } catch (_) {
      return null;
    }
  }

  /// Ensure we have cached article text (from background readability backfill)
  /// for TTS/translate, no matter which mode (reader vs full web) we are in.
  Future<void> _ensureLinesLoaded() async {
    if (_lines.isNotEmpty) return;

    final result = await _loadCachedContent();
    if (!mounted) return;

    final text = (result?.mainText ?? '').trim();
    final pagePaywalled = result?.isPaywalled ?? false;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reader text is still loading. Please wait while it finishes in the background.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      setState(() {
        _paywallLikely = false;
        _lines.clear();
        _currentLine = 0;
        _readerHintVisible = false;
      });
      return;
    }

    final previewOnly = _isLikelyPreviewText(text, pagePaywalled);
    final rawParagraphs = text.isEmpty
        ? <String>[]
        : text
            .split('\n\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

    // Group paragraphs into chunks for smoother TTS reading
    // Instead of speaking each paragraph separately with long pauses,
    // group 3-4 paragraphs together so TTS reads more continuously
    final chunkedLines = <String>[];
    const chunkSize = 3; // Speak 3 paragraphs at a time
    for (int i = 0; i < rawParagraphs.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, rawParagraphs.length);
      final chunk = rawParagraphs.sublist(i, end).join(' '); // Join with space for continuous reading
      chunkedLines.add(chunk);
    }

    // 👇 Build final lines list: optional header + article content
    final combined = <String>[];
    final header = ((widget.title ?? '').trim().isNotEmpty
            ? (widget.title ?? '').trim()
            : (result?.pageTitle ?? '').trim())
        .trim();
    if (header.isNotEmpty) {
      combined.add(header);
    }
    combined.addAll(chunkedLines);

    _heroImageUrl ??= result?.imageUrl;

     // Treat the page as paywalled only when the extracted text still looks
    // like a short preview. Some sites keep paywall markers in the DOM even
    // after login, so don't block full-text articles just because markers
    // exist.
    final looksPaywalled = previewOnly || (pagePaywalled && rawParagraphs.length <= 3);

    // Load saved reading position
    final savedPosition = await _loadSavedReadingPosition();
    final restoredLine = (savedPosition != null && savedPosition < combined.length)
        ? savedPosition
        : 0;

    // Check if we're returning to an article that's currently playing
    final isSameArticle = _ttsState.articleId == (widget.articleId ?? '');
    final isCurrentlyPlaying = _isPlaying && isSameArticle;

    // Prefer the last known global line when returning to the same article,
    // even if playback is currently paused. This keeps the UI in sync with
    // background TTS progress when navigating away and back.
    final globalLine = (isSameArticle && _ttsState.currentLine < combined.length)
        ? _ttsState.currentLine
        : null;

    setState(() {
      _paywallLikely = looksPaywalled;
      _lines
        ..clear()
        ..addAll(combined);
      // Only restore saved position if not currently playing
      // If playing, keep the global current line
      if (!isCurrentlyPlaying) {
        _currentLine = globalLine ?? restoredLine;
      }
      // If playing, sync global lines with loaded lines
      if (isCurrentlyPlaying) {
        _ttsState.lines = _lines;
      }
      _readerHintVisible = !_readerOn && !_readerHintDismissed;
    });

    // Show visual feedback if position was restored (but not if currently playing)
    if (!isCurrentlyPlaying && savedPosition != null && savedPosition > 0 && savedPosition < combined.length && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Resuming from line ${savedPosition + 1}/${combined.length}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Remove paywall overlays and unhide subscriber content in the live WebView
  Future<void> _removePaywallOverlays() async {
    try {
      // Execute JavaScript to clean up paywall elements
      await _controller.runJavaScript('''
        (function() {
          console.log('🔓 Removing paywall overlays...');

          // Remove common paywall UI elements
          const paywallSelectors = [
            '[class*="paywall"]', '[id*="paywall"]',
            '[class*="premium"]', '[class*="subscribe-modal"]',
            '[class*="subscribe-prompt"]', '[class*="subscription-wall"]',
            '.overlay', '.modal-backdrop', '.content-gate',
            '[class*="registration-wall"]', '[class*="meter-"]',
            '[class*="piano-"]', '[data-testid*="paywall"]'
          ];

          paywallSelectors.forEach(selector => {
            try {
              document.querySelectorAll(selector).forEach(el => {
                // Only remove if it's a small UI element (likely overlay, not content)
                const text = el.textContent?.trim() || '';
                if (text.length < 500 ||
                    text.toLowerCase().includes('subscribe') ||
                    text.toLowerCase().includes('sign in')) {
                  el.remove();
                  console.log('Removed:', selector);
                }
              });
            } catch(e) { }
          });

          // Remove blur/opacity effects
          document.querySelectorAll('*').forEach(el => {
            try {
              const style = window.getComputedStyle(el);
              if (style.filter && style.filter.includes('blur')) {
                el.style.filter = 'none';
                el.style.webkitFilter = 'none';
              }
              if (style.opacity === '0' || style.opacity < 0.3) {
                el.style.opacity = '1';
              }
            } catch(e) { }
          });

          // Unhide subscriber/premium content
          const contentSelectors = [
            '.subscriber-content', '.premium-content',
            '.locked-content', '.members-only',
            '[data-subscriber="true"]', '[data-premium="true"]',
            '[class*="subscriber-only"]', '[class*="premium-only"]',
            '[style*="display: none"]', '[style*="display:none"]'
          ];

          contentSelectors.forEach(selector => {
            try {
              document.querySelectorAll(selector).forEach(el => {
                el.style.display = 'block';
                el.style.visibility = 'visible';
                el.style.opacity = '1';
                el.style.height = 'auto';
                el.style.maxHeight = 'none';
              });
            } catch(e) { }
          });

          // Re-enable scrolling (paywalls often disable it)
          document.body.style.overflow = 'auto';
          document.documentElement.style.overflow = 'auto';

          // Remove position:fixed that might be blocking content
          document.querySelectorAll('[style*="position: fixed"], [style*="position:fixed"]').forEach(el => {
            const text = el.textContent?.trim() || '';
            if (text.length < 500 && (text.toLowerCase().includes('subscribe') || text.toLowerCase().includes('sign in'))) {
              el.remove();
            }
          });

          console.log('✓ Paywall cleanup complete');
        })();
      ''');
    } catch (e) {
      // Silently fail if JavaScript execution fails
      print('Failed to remove paywall overlays: $e');
    }
  }

  String? _normalizeJsString(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is String) return decoded;
      } catch (_) {
        // If it's already a plain string (not JSON-wrapped), use as-is.
      }
      return raw;
    }

    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is String) return decoded;
    } catch (_) {
      // Fallback to simple string conversion
    }
    return raw.toString();
  }
  Future<void> _speakCurrentLine() async {
    _cancelAutoAdvanceTimer();
    await _ensureLinesLoaded();
    if (_lines.isEmpty) return;
    if (_currentLine < 0 || _currentLine >= _lines.length) return;

    final settings = context.read<SettingsProvider>();
    final targetCode = _isTranslatedView ? settings.translateLangCode : 'off';

    String text = _lines[_currentLine].trim();

    if (text.isEmpty) {
      await _speakNextLine(auto: true);
      return;
    }

    // Determine which language to use for TTS voice
    String ttsLanguageCode;
    if (_isTranslatedView && targetCode != 'off') {
      // If translated view, use the translation language
      ttsLanguageCode = targetCode;
      text = _normalizeForTts(text, targetCode);
    } else {
      // Use the article's primary language (detected once, consistent throughout)
      ttsLanguageCode = await _detectArticlePrimaryLanguage();
      // Normalize text for the article's language
      text = _normalizeForTts(text, ttsLanguageCode);
    }

    // Set TTS language to match the article's primary language (or translation language)
    // This ensures the SAME voice is used throughout the entire article
    await _applyTtsLocale(ttsLanguageCode);

    // Mark article as read when starting to speak (first time)
    if (!_isPlaying && widget.articleId != null) {
      _markArticleAsRead();
    }

    // Highlight current line in reader mode (if setting ON)
    await _highlightLine(_currentLine);

    // Sync global state with local lines
    _ttsState.lines = _lines;
    _ttsState.articleId = widget.articleId ?? '';
    _ttsState.articleTitle = widget.title ?? '';
    _ttsState.readerModeOn = _readerOn; // Save reader mode state

    // Sync article list and current index for continuous reading
    _ttsState.allArticles = widget.allArticles;
    if (widget.articleId != null && widget.allArticles.isNotEmpty) {
      final index = widget.allArticles.indexWhere((a) => a.id == widget.articleId);
      if (index >= 0) {
        _ttsState.currentArticleIndex = index;
      }
    }

    // Stop any currently playing TTS first (before setting state)
    await _globalTts.stop();
    // Apply speech rate but don't restart (we're about to speak anyway)
    await _applySpeechRateFromSettings(restartIfPlaying: false);

    // Now set playing state and start speaking
    setState(() {
      _isPlaying = true;
      _webHighlightText = null;
    });

    // Enable WakeLock to keep screen on during TTS playback
    try {
      await WakelockPlus.enable();
      debugPrint('TTS: 🔒 WakeLock enabled - screen will stay on during playback');
    } catch (e) {
      debugPrint('TTS: ⚠️ Failed to enable WakeLock: $e');
    }

    // Start periodic position saving during playback
    _startPeriodicSave();
    // Start periodic highlight syncing to catch global state changes
    _startPeriodicHighlightSync();
    _lastSyncedLine = _currentLine;
    await _showReadingNotification(text);
    await _globalTts.speak(text);
  }

  void _markArticleAsRead() {
    if (widget.articleId == null) return;
    try {
      final rss = context.read<RssProvider>();
      final article = rss.items.firstWhere(
        (item) => item.id == widget.articleId,
        orElse: () => throw Exception('Article not found'),
      );
      rss.markRead(article, read: 1);
    } catch (_) {
      // Ignore errors if article not found in provider
    }
  }

  Future<void> _speakNextLine({bool auto = false}) async {
    // Cancel auto-advance timer when manually navigating
    if (!auto) {
      _cancelAutoAdvanceTimer();
    }

    await _ensureLinesLoaded();
    if (_lines.isEmpty) {
      setState(() => _isPlaying = false);
      // Disable WakeLock when stopping due to empty lines
      WakelockPlus.disable().catchError((e) => debugPrint('TTS: Failed to disable WakeLock: $e'));
      await _clearReadingNotification();
      return;
    }

    int i = _currentLine + 1;

    if (i >= _lines.length) {
      // If at the end of current article
      // Immediately go to next article (no delay) if available
      if (_hasNextArticle()) {
        _navigateToNextArticle();
        // WakeLock stays enabled - continuing to next article
      } else {
        // No more articles, just stop
        setState(() => _isPlaying = false);
        // Disable WakeLock when reaching end of all articles
        WakelockPlus.disable().catchError((e) => debugPrint('TTS: Failed to disable WakeLock: $e'));
        if (_lines.isNotEmpty && _currentLine >= 0 && _currentLine < _lines.length) {
          await _showReadingNotification(_lines[_currentLine]);
        }
      }
      return;
    }

    setState(() => _currentLine = i);
    // Auto-save position after moving to new line
    unawaited(_saveReadingPosition());
    await _speakCurrentLine();
  }

  Future<void> _speakPrevLine() async {
    _cancelAutoAdvanceTimer();
    await _ensureLinesLoaded();
    if (_lines.isEmpty) return;

    int i = _currentLine - 1;
    // Just stop if at beginning, don't wrap around
    if (i < 0) {
      // Stop speaking if currently playing
      if (_isPlaying) {
        await _stopSpeaking();
      }
      return;
    }

    setState(() => _currentLine = i);
    // Auto-save position after moving to previous line
    unawaited(_saveReadingPosition());
    await _speakCurrentLine();
  }

  Future<void> _stopSpeaking() async {
    _cancelAutoAdvanceTimer();
    _cancelPeriodicSave();
    _cancelPeriodicHighlightSync();
    await _globalTts.stop();
    if (mounted) {
      setState(() => _isPlaying = false);

      // Disable WakeLock when TTS stops
      try {
        await WakelockPlus.disable();
        debugPrint('TTS: 🔓 WakeLock disabled - screen can turn off now');
      } catch (e) {
        debugPrint('TTS: ⚠️ Failed to disable WakeLock: $e');
      }

      // Save position when stopping
      await _saveReadingPosition();
      // Update notification to show paused state instead of clearing
      if (_lines.isNotEmpty && _currentLine >= 0 && _currentLine < _lines.length) {
        await _showReadingNotification(_lines[_currentLine]);
        // Keep the highlight visible at the stopped position
        await _highlightLine(_currentLine);
      }
    }
  }

  void _startAutoAdvanceTimer() {
    _cancelAutoAdvanceTimer();

    // Show countdown snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Moving to next article in 5 seconds...'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Cancel',
            onPressed: _cancelAutoAdvanceTimer,
          ),
        ),
      );
    }

    _autoAdvanceTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _disposed) return;
      _navigateToNextArticle();
    });
  }

  void _cancelAutoAdvanceTimer() {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;
  }

  void _startPeriodicSave() {
    _cancelPeriodicSave();
    // Save position every 3 seconds during playback
    _periodicSaveTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _disposed) {
        _cancelPeriodicSave();
        return;
      }
      unawaited(_saveReadingPosition());
    });
  }

  void _cancelPeriodicSave() {
    _periodicSaveTimer?.cancel();
    _periodicSaveTimer = null;
  }

  void _startPeriodicHighlightSync() {
    _cancelPeriodicHighlightSync();
    // Sync highlight every 500ms during playback to catch global state changes
    _periodicHighlightSyncTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || _disposed) {
        _cancelPeriodicHighlightSync();
        return;
      }
      // Only sync if widget is active and playback is happening
      if (_isPlaying && _lines.isNotEmpty) {
        // Check if the global current line has changed from what we last synced
        if (_currentLine != _lastSyncedLine) {
          _lastSyncedLine = _currentLine;
          // Update highlight to match global state
          if (_currentLine >= 0 && _currentLine < _lines.length) {
            unawaited(_highlightLine(_currentLine));
          }
        }
      }
    });
  }

  void _cancelPeriodicHighlightSync() {
    _periodicHighlightSyncTimer?.cancel();
    _periodicHighlightSyncTimer = null;
  }

  bool _hasNextArticle() {
    if (widget.allArticles.isEmpty) return false;

    // Find the current article's index in the list
    final currentIndex = widget.allArticles.indexWhere(
      (article) => article.id == widget.articleId,
    );

    // Check if there's a next article
    return currentIndex >= 0 && currentIndex + 1 < widget.allArticles.length;
  }

  FeedItem? _getNextArticle() {
    if (!_hasNextArticle()) return null;

    final currentIndex = widget.allArticles.indexWhere(
      (article) => article.id == widget.articleId,
    );

    if (currentIndex >= 0 && currentIndex + 1 < widget.allArticles.length) {
      return widget.allArticles[currentIndex + 1];
    }

    return null;
  }

  bool _hasPreviousArticle() {
    if (widget.allArticles.isEmpty) return false;

    final currentIndex = widget.allArticles.indexWhere(
      (article) => article.id == widget.articleId,
    );

    // Check if there's a previous article
    return currentIndex > 0;
  }

  FeedItem? _getPreviousArticle() {
    if (!_hasPreviousArticle()) return null;

    final currentIndex = widget.allArticles.indexWhere(
      (article) => article.id == widget.articleId,
    );

    if (currentIndex > 0) {
      return widget.allArticles[currentIndex - 1];
    }

    return null;
  }

  void _navigateToNextArticle() {
    if (!mounted || _disposed) return;

    final nextArticle = _getNextArticle();
    if (nextArticle == null) return;

    // Keep using the same article list (maintains sort order and navigation position)
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ArticleWebviewPage(
          articleId: nextArticle.id,
          url: nextArticle.link ?? '',
          title: nextArticle.title,
          initialMainText: nextArticle.mainText,
          initialImageUrl: nextArticle.imageUrl,
          allArticles: widget.allArticles,
          autoPlay: true, // Auto-start playing the next article
        ),
      ),
    );
  }

  void _goToPreviousArticle() {
    _cancelAutoAdvanceTimer();
    if (!mounted || _disposed) return;

    final previousArticle = _getPreviousArticle();

    // If no previous article, go back to news page
    if (previousArticle == null) {
      Navigator.of(context).pop();
      return;
    }

    // Keep using the same article list (maintains sort order and navigation position)
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ArticleWebviewPage(
          articleId: previousArticle.id,
          url: previousArticle.link ?? '',
          title: previousArticle.title,
          initialMainText: previousArticle.mainText,
          initialImageUrl: previousArticle.imageUrl,
          allArticles: widget.allArticles,
          autoPlay: false, // Don't auto-play when going backwards
        ),
      ),
    );
  }

  void _goToNextArticleNow() {
    _cancelAutoAdvanceTimer();
    if (!mounted || _disposed) return;

    final nextArticle = _getNextArticle();
    if (nextArticle == null) return;

    // Keep using the same article list (maintains sort order and navigation position)
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ArticleWebviewPage(
          articleId: nextArticle.id,
          url: nextArticle.link ?? '',
          title: nextArticle.title,
          initialMainText: nextArticle.mainText,
          initialImageUrl: nextArticle.imageUrl,
          allArticles: widget.allArticles,
          autoPlay: true, // Auto-play when manually skipping to next article
        ),
      ),
    );
  }


  Future<void> _showReadingNotification(String lineText) async {
    final title =
        (widget.title?.isNotEmpty ?? false) ? widget.title! : 'Reading article';

    // Show line position and optionally article progress
    String position = '${_currentLine + 1}/${_lines.length}';
    if (widget.allArticles.isNotEmpty && widget.articleId != null) {
      final index = widget.allArticles.indexWhere((a) => a.id == widget.articleId);
      if (index >= 0) {
        position += ' • Article ${index + 1}/${widget.allArticles.length}';
      }
    }

    // Truncate line text if too long for notification
    final displayText = lineText.length > 100
        ? '${lineText.substring(0, 97)}...'
        : lineText;

    // Create notification actions
    final List<AndroidNotificationAction> actions = [
      const AndroidNotificationAction(
        'previous',
        'Previous',
        icon: DrawableResourceAndroidBitmap('ic_skip_previous'),
        showsUserInterface: false,
      ),
      AndroidNotificationAction(
        'play_pause',
        _isPlaying ? 'Pause' : 'Play',
        icon: DrawableResourceAndroidBitmap(_isPlaying ? 'ic_pause' : 'ic_play'),
        showsUserInterface: false,
      ),
      const AndroidNotificationAction(
        'next',
        'Next',
        icon: DrawableResourceAndroidBitmap('ic_skip_next'),
        showsUserInterface: false,
      ),
    ];

    final android = AndroidNotificationDetails(
      'reading_channel',
      'Reading',
      channelDescription: 'Controls for text-to-speech reading.',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      onlyAlertOnce: true,
      autoCancel: false,
      showWhen: true,
      usesChronometer: _isPlaying,
      styleInformation: MediaStyleInformation(
        htmlFormatContent: true,
        htmlFormatTitle: true,
      ),
      actions: actions,
      subText: position,
      ticker: 'Reading: $title',
    );
    const ios = DarwinNotificationDetails(
      presentAlert: false,
      presentSound: false,
      presentBadge: false,
    );

    await _globalNotifications.show(
      _readingNotificationId,
      title,
      displayText,
      NotificationDetails(android: android, iOS: ios),
    );
  }

  Future<void> _clearReadingNotification() async {
    await _globalNotifications.cancel(_readingNotificationId);
  }
  // --------------- UI ---------------

  Future<void> _toggleReader() async {
    setState(() {
      _readerOn = !_readerOn;
      if (_readerOn) {
        _readerHintVisible = false;
      } else if (_lines.isNotEmpty && !_readerHintDismissed) {
        _readerHintVisible = true;
      }
    });

    // Save reader mode state globally so it persists when returning to this article
    _ttsState.readerModeOn = _readerOn;

    if (_readerOn) {
      await _loadReaderContent();
      // Highlight current line in reader mode (whether playing or just viewing saved position)
      if (_lines.isNotEmpty && _currentLine >= 0 && _currentLine < _lines.length) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (mounted && _readerOn) {
          await _highlightLine(_currentLine);
        }
      }
    } else {
      // Go back to full website, but KEEP _lines so TTS still works
      // Don't stop speaking - allow TTS to continue uninterrupted
      await _controller.loadRequest(Uri.parse(widget.url));

      // Wait for page to load, then highlight current line in webview
      if (_lines.isNotEmpty && _currentLine >= 0 && _currentLine < _lines.length) {
        // Give webview a moment to render before injecting highlight
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted && !_readerOn) {
          await _highlightLine(_currentLine);
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
        // App going to background - save position
        unawaited(_saveReadingPosition());
        break;
      case AppLifecycleState.resumed:
        // App coming back to foreground - refresh notification and highlight
        if (_lines.isNotEmpty && _currentLine >= 0 && _currentLine < _lines.length) {
          if (_isPlaying) {
            unawaited(_showReadingNotification(_lines[_currentLine]));
            // If playing, use normal highlight (immediate mode)
            unawaited(_highlightLine(_currentLine));
          } else {
            // If not playing, use delayed immediate highlight to ensure page is ready
            Future.delayed(const Duration(milliseconds: 500)).then((_) {
              if (mounted) {
                unawaited(_highlightLineImmediate(_currentLine));
              }
            });
          }
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _cancelAutoAdvanceTimer();
    _cancelPeriodicSave();
    _cancelPeriodicHighlightSync();
    if (_settingsListener != null && _settings != null) {
      _settings!.removeListener(_settingsListener!);
    }

    // Disable WakeLock when navigating away (just in case)
    // This ensures screen can turn off even if TTS is still playing in background
    WakelockPlus.disable().catchError((e) {
      debugPrint('TTS: Failed to disable WakeLock on dispose: $e');
    });

    // Unregister widget-specific handlers
    // The global handlers will take over for background playback
    if (_ttsState.widgetActionHandler == _handleWidgetNotificationAction) {
      _ttsState.widgetActionHandler = null;
    }
    if (_ttsState.widgetCompletionHandler == _handleWidgetCompletion) {
      _ttsState.widgetCompletionHandler = null;
    }
    // TTS continues playing in background via global instance
    // Notification buttons remain functional via global handler
    // Highlighting will stop but audio continues
    unawaited(_saveReadingPosition());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final canTranslate = settings.translateLangCode != 'off';

    return WillPopScope(
      onWillPop: _handleBackNavigation,
      child: Scaffold(
        appBar: AppBar(
          title: const SizedBox.shrink(),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final shouldPop = await _handleBackNavigation();
              if (shouldPop && mounted) {
                Navigator.of(context).maybePop();
              }
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () {
                final title = widget.title ?? 'Check out this article';
                final url = widget.url;
                Share.share('$title\n\n$url', subject: title);
              },
              tooltip: 'Share article',
            ),
            IconButton(
              icon: Icon(_readerOn ? Icons.web : Icons.chrome_reader_mode),
              onPressed: _toggleReader,
              tooltip: _readerOn ? 'Show original page' : 'Reader mode',
            ),
            if (canTranslate)
              IconButton(
                icon: (_isLoading || _isTranslating)
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_isTranslatedView ? Icons.undo : Icons.g_translate),
                onPressed: (_isLoading || _isTranslating)
                    ? null
                    : _toggleTranslateToSetting,
                tooltip: _isTranslatedView ? 'Show original' : 'Translate',
              ),
            if (!_readerOn)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => _controller.reload(),
              ),
          ],
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              const LinearProgressIndicator(
                minHeight: 2,
              ),
            if (!_readerOn &&
                settings.highlightText &&
                (_webHighlightText?.isNotEmpty ?? false))
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: SafeArea(
                  child: IgnorePointer(
                    ignoring: true,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.yellow.shade100.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Text(
                          _webHighlightText ?? '',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_paywallLikely)
              Positioned(
                top: 16,
                left: 12,
                right: 12,
                child: SafeArea(
                  child: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.orange.shade50.withOpacity(0.95),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lock, color: Colors.orange),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Reader view only has a short preview. Sign in on the site (Add feed → "Requires login") '
                              'so your cookies can unlock the full article, then reload or open the original page.',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                    icon: const Icon(Icons.skip_previous),
                    onPressed: _goToPreviousArticle,
                    tooltip: 'Previous article'),
                IconButton(
                    icon: const Icon(Icons.fast_rewind),
                    onPressed: _speakPrevLine,
                    tooltip: 'Previous line'),
                IconButton(
                  icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                  onPressed: _isPlaying ? _stopSpeaking : _speakCurrentLine,
                  iconSize: 32,
                  tooltip: _isPlaying ? 'Stop' : 'Play',
                ),
                IconButton(
                    icon: const Icon(Icons.fast_forward),
                    onPressed: _speakNextLine,
                    tooltip: 'Next line'),
                IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: _goToNextArticleNow,
                    tooltip: 'Next article'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
