part of 'article_webview_page.dart';

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

// ============ Public TTS Control API ============
// These functions allow other pages to control background TTS playback

/// Check if TTS is currently playing
bool isGlobalTtsPlaying() => _TtsState.instance.isPlaying;

/// Get the title of the article currently being read
String getGlobalTtsArticleTitle() => _TtsState.instance.articleTitle;

/// Get the ID of the article currently being read
String getGlobalTtsArticleId() => _TtsState.instance.articleId;

/// Get current reading progress as "line/total"
String getGlobalTtsProgress() {
  final state = _TtsState.instance;
  if (state.lines.isEmpty) return '';
  return '${state.currentLine + 1}/${state.lines.length}';
}

/// Stop TTS playback and clear notification
Future<void> stopGlobalTts() async {
  final state = _TtsState.instance;
  state.isPlaying = false;
  await _globalTts.stop();
  await _globalNotifications.cancel(0); // Cancel reading notification
}

/// Stop TTS playback if the provided article is currently being read.
Future<void> stopGlobalTtsForArticle(String articleId) async {
  final state = _TtsState.instance;
  if (articleId.isEmpty || state.articleId != articleId) return;

  state.isPlaying = false;
  state.currentLine = 0;
  state.lines = [];
  state.articleId = '';
  state.articleTitle = '';
  state.sourceTitle = '';
  state.isTranslatedContent = false;
  await _globalTts.stop();
  await _globalNotifications.cancel(0); // Cancel reading notification
}

/// Pause/Resume TTS playback
Future<void> toggleGlobalTts() async {
  final state = _TtsState.instance;
  if (state.isPlaying) {
    state.isPlaying = false;
    await _globalTts.stop();
    // Update notification to show paused state
    if (state.lines.isNotEmpty && state.currentLine >= 0 && state.currentLine < state.lines.length) {
      unawaited(_showReadingNotificationGlobal(state.lines[state.currentLine]));
    }
  } else {
    await _speakCurrentLineGlobal();
  }
}

/// Apply speech rate to the global TTS instance (for background playback updates).
Future<void> applyGlobalTtsSpeechRate(double rate) async {
  await _globalTts.setSpeechRate(rate);
}

/// Apply speech rate based on current global TTS state and settings.
Future<void> applyGlobalTtsSpeechRateFromSettings(
  SettingsProvider settings,
) async {
  final state = _TtsState.instance;
  final rate = settings.getSpeedForArticle(
    state.sourceTitle,
    state.isTranslatedContent,
  );
  await _globalTts.setSpeechRate(rate);
}

// ============ End Public TTS Control API ============

// Global state for background playback
class _TtsState {
  List<String> lines = [];
  int currentLine = 0;
  bool isPlaying = false;
  String articleId = '';
  String articleTitle = '';
  String sourceTitle = ''; // Feed/source title for per-feed speed settings
  bool isTranslatedContent = false; // Whether currently reading translated content
  bool notificationsInitialized = false;
  bool ttsInitialized = false;
  bool readerModeOn = false; // Remember reader mode state
  bool autoTranslateEnabled = false;
  String translateLangCode = 'off';

  // Translation cache: articleId -> {translated: List<String>, original: List<String>}
  final Map<String, Map<String, List<String>>> translationCache = {};

  // Article list for continuous reading
  List<FeedItem> allArticles = [];
  int currentArticleIndex = -1;

  // Database access for loading next articles
  ArticleDao? articleDao;
  RssProvider? rssProvider;

  // Callback for widget-specific actions (set by current widget instance)
  void Function(String actionId)? widgetActionHandler;

  // Callback for widget-specific completion handling (highlighting, etc.)
  Future<bool> Function()? widgetCompletionHandler;

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

  if (state.rssProvider != null) {
    final currentArticle = state.allArticles[state.currentArticleIndex];
    if (currentArticle.isRead < 1) {
      try {
        state.rssProvider!.markRead(currentArticle, read: 1);
      } catch (_) {
        // Ignore errors
      }
    }
  }

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
        .split(RegExp(r'\n+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final combined = <String>[];
    final header = nextArticle.title.trim();
    if (header.isNotEmpty) {
      combined.add(header);
    }
    combined.addAll(rawParagraphs);

    if (combined.isEmpty) return false;

    // Update global state with next article
    state.lines = combined;
    state.currentLine = 0;
    state.articleId = nextArticle.id;
    state.articleTitle = nextArticle.title;
    state.sourceTitle = nextArticle.sourceTitle;
    state.isTranslatedContent = false; // Reset to original content for new article
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

  // If at end of article, attempt to load next article (auto-advance)
  if (state.currentLine >= state.lines.length - 1) {
    if (auto) {
      // Try to load next article and continue reading
      final loaded = await _loadNextArticleGlobal();
      if (loaded) {
        await _speakCurrentLineGlobal(auto: true);
      } else {
        // No more articles - stop
        state.isPlaying = false;
        await _globalTts.stop();
        await _globalNotifications.cancel(0);
      }
    } else {
      state.isPlaying = false;
      await _globalTts.stop();
      await _globalNotifications.cancel(0);
    }
    return;
  }

  state.currentLine++;
  await _speakCurrentLineGlobal(auto: auto);
}

// Global function to speak current line (works even when widget is disposed)
Future<void> _speakCurrentLineGlobal({bool auto = false}) async {
  final state = _TtsState.instance;
  if (state.lines.isEmpty) return;
  if (state.currentLine < 0 || state.currentLine >= state.lines.length) return;

  // If widget is still active, let it handle TTS to preserve highlighting
  if (state.widgetCompletionHandler != null && !auto) {
    try {
      final handled = await state.widgetCompletionHandler!();
      if (handled) return;
    } catch (_) {
      // Fall back to global handling
    }
  }

  state.isPlaying = true;
  final text = state.lines[state.currentLine];
  unawaited(_showReadingNotificationGlobal(text));
  // Only stop TTS when starting fresh (not auto-advancing)
  // When auto-advancing, TTS has already completed so no need to stop
  if (!auto) {
    await _globalTts.stop();
  }

  await _globalTts.speak(text);
}

Future<void> _showReadingNotificationGlobal(String lineText) async {
  final state = _TtsState.instance;
  final title = state.articleTitle.isNotEmpty ? state.articleTitle : 'Reading article';

  // Show line position and optionally article progress
  String position = '${state.currentLine + 1}/${state.lines.length}';
  if (state.allArticles.isNotEmpty && state.articleId.isNotEmpty) {
    final index = state.allArticles.indexWhere((a) => a.id == state.articleId);
    if (index >= 0) {
      position += ' • Article ${index + 1}/${state.allArticles.length}';
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
    0,
    title,
    displayText,
    NotificationDetails(android: android, iOS: ios),
  );
}
