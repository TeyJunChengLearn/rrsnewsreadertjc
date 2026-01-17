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

part 'article_webview_page_helpers.dart';
part 'article_webview_page_reader.dart';
part 'article_webview_page_translation.dart';
part 'article_webview_page_tts_global.dart';

// =================== Widget ===================

class ArticleWebviewPage extends StatefulWidget {
  final String url;
  final String? title; // optional RSS/article title to include in reading
  final String? articleId;
  final String? sourceTitle; // Feed/source title for per-feed speed settings
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
    this.sourceTitle,
    this.initialMainText,
    this.initialImageUrl,
    this.allArticles = const [],
    this.autoPlay = false,
  });

  @override
  State<ArticleWebviewPage> createState() => _ArticleWebviewPageState();
}

class _ArticleWebviewPageState extends State<ArticleWebviewPage> with WidgetsBindingObserver {
  late final WebViewController _controller;

  bool _disposed = false;
  bool _isForeground = true;

  bool _isLoading = true;
  bool _readerOn = false;
  bool _paywallLikely = false;
  bool _articleUnavailable = false;
  String _articleUnavailableMessage = '';
  bool _articleLoadFailed = false; // Track if article failed to load (deleted/hidden)
  int _mainFrameLoadAttempts = 0;
  String? _lastRequestedUrl;
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

  /// Helper to get sourceTitle from allArticles when not provided directly
  String _getSourceTitleFromArticles() {
    if (widget.articleId == null || widget.allArticles.isEmpty) return '';
    final article = widget.allArticles.cast<FeedItem?>().firstWhere(
      (a) => a?.id == widget.articleId,
      orElse: () => null,
    );
    return article?.sourceTitle ?? '';
  }

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
  String? _cachedTtsLanguageCode; // Cached TTS language code to avoid repeated detection
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
      final candidates = _webHighlightCandidates(index);
      if (candidates.isEmpty) return;

      if (mounted) {
        setState(() => _webHighlightText = candidates.first);
      }

      for (final text in candidates) {
        try {
          final success = await _highlightInWebPage(text);
          if (success) break;
        } catch (e) {
          // Silently continue to next candidate
        }
      }
    }
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
          final handled = await s.widgetCompletionHandler!();
          if (handled) {
            return;
          }
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
      _ttsState.sourceTitle = '';
      _ttsState.isTranslatedContent = false;
      _ttsState.readerModeOn = false; // Reset reader mode for new article
      // Clear the notification
      unawaited(_clearReadingNotification());

      // Clear article language cache for new article
      _articlePrimaryLanguage = null;
      _cachedTtsLanguageCode = null;
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
      } else {
        // Open in webview mode - load the full website
        await _loadArticleUrl();
      }

      await _ensureLinesLoaded();

      // Check for cached translation and restore if available
      await _restoreCachedTranslation();

      // Auto-translate if enabled (after lines are loaded, only if not already translated)
      if (!_isTranslatedView) {
        await _autoTranslateIfEnabled();
      }

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
      // But don't restart if TTS is already playing (e.g., when syncing from background)
      if (widget.autoPlay && hasValidLine && !_isPlaying) {
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

      // Get the appropriate speed based on feed and translation state
      final sourceTitle = _ttsState.sourceTitle.isNotEmpty
          ? _ttsState.sourceTitle
          : (widget.sourceTitle ?? _getSourceTitleFromArticles());
      final isTranslated = _ttsState.isTranslatedContent || _isTranslatedView;

      final rate = settings.getSpeedForArticle(sourceTitle, isTranslated);

      debugPrint('🔊 Applying TTS speech rate: $rate '
          '(feed: $sourceTitle, translated: $isTranslated, playing: $_isPlaying)');

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
        m.forEach((key, value) {
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
            _mainFrameLoadAttempts = 0;

            // Automatically remove paywall overlays when page finishes loading
            // This helps user see full content even when not in reader mode
            await Future.delayed(const Duration(milliseconds: 1000));
            if (!mounted || _disposed) return;
            await _removePaywallOverlays();
          },
          onWebResourceError: (error) async {
            if (!mounted || _disposed) return;
            if (error.isForMainFrame != true) return;

            if (_lastRequestedUrl != null && _mainFrameLoadAttempts < 2) {
              _mainFrameLoadAttempts++;
              await Future.delayed(const Duration(milliseconds: 600));
              if (!mounted || _disposed) return;
              try {
                await _controller.loadRequest(Uri.parse(_lastRequestedUrl!));
                return;
              } catch (_) {
                // Fall through to error handling below.
              }
            }

            _handleArticleUnavailable(
              'Unable to load this article. Please try reloading or opening it again.',
            );
          },
        ),
      );
    // Note: Don't load URL here - defer to addPostFrameCallback to avoid race condition
    // with reader mode initialization
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

  Future<bool> _handleWidgetCompletion() async {
    // Widget-specific completion handler (called from global TTS completion handler)
    // This enables highlighting during continuous playback even after navigation
    if (!mounted || _disposed || !_isForeground) return false;

    // Call the instance method which includes highlighting
    await _speakNextLine(auto: true);
    return true;
  }

  Future<void> _loadArticleUrl() async {
    final trimmedUrl = widget.url.trim();
    final uri = trimmedUrl.isEmpty ? null : Uri.tryParse(trimmedUrl);

    if (uri == null) {
      _handleArticleUnavailable(
        'This article is no longer available. It may have been removed from the feed.',
      );
      return;
    }

    _lastRequestedUrl = uri.toString();
    _mainFrameLoadAttempts++;
    if (mounted) {
      setState(() => _isLoading = true);
    }
    await _controller.loadRequest(uri);
  }

  void _handleArticleUnavailable(String message) {
    if (!mounted) return;

    setState(() {
      _articleUnavailable = true;
      _articleUnavailableMessage = message;
      _isLoading = false;
      _readerOn = false;
      _lines.clear();
      _currentLine = 0;
      _paywallLikely = false;
    });

    final articleId = widget.articleId ?? '';
    if (articleId.isNotEmpty) {
      unawaited(stopGlobalTtsForArticle(articleId));
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
      final candidates = _webHighlightCandidates(index);
      if (candidates.isEmpty) return;

      if (mounted) {
        setState(() => _webHighlightText = candidates.first);
      }

      // During active playback, highlight immediately without delay
      if (_isPlaying) {
        for (final text in candidates) {
          try {
            final success = await _highlightInWebPage(text);
            if (success) break;
          } catch (e) {
            // Silently continue - try next candidate
          }
        }
      } else {
        // When not playing, add delay for page load
        await Future.delayed(const Duration(milliseconds: 100));
        // Check if this operation has been superseded
        if (mounted && !_readerOn && _highlightSequence == currentSequence) {
          for (final text in candidates) {
            try {
              final success = await _highlightInWebPage(text);
              if (success) break;
            } catch (e) {
              // Silently continue - try next candidate
            }
          }
        }
      }
    }
  }

  List<String> _webHighlightCandidates(int index) {
    if (index < 0 || index >= _lines.length) return [];
    final primary = _isTranslatedView &&
            _originalLinesCache != null &&
            index < _originalLinesCache!.length
        ? _originalLinesCache![index].trim()
        : _lines[index].trim();
    if (primary.isEmpty) return [];
    final candidates = <String>[primary];
    final translated = _lines[index].trim();
    if (translated.isNotEmpty && translated != primary) {
      candidates.add(translated);
    }
    return candidates;
  }

  Future<bool> _highlightInWebPage(String text) async {
    try {
      final escaped = jsonEncode(text);
      final script = '''
(function(txt){
  if(!txt){return false;}
  const cls='flutter-tts-highlight';
  const styleId = 'flutter-tts-highlight-style';
  if(!document.getElementById(styleId)){
    const style = document.createElement('style');
    style.id = styleId;
    style.textContent = 'mark.'+cls+'{background:rgba(255,235,59,0.75) !important;color:inherit !important;padding:0 0.12em !important;border-radius:0.12em !important;box-decoration-break:clone !important;-webkit-box-decoration-break:clone !important;}';
    document.head.appendChild(style);
  }

  // Remove old highlights - unwrap mark elements back to text nodes
  document.querySelectorAll('mark.'+cls).forEach(m=>{
    const parent=m.parentNode;
    if(!parent){return;}
    while(m.firstChild){
      parent.insertBefore(m.firstChild, m);
    }
    parent.removeChild(m);
    parent.normalize();
  });

  // Normalize search text (remove extra whitespace, normalize unicode)
  const searchText = txt.trim().replace(/\\s+/g, ' ').toLowerCase().normalize('NFC');

  // Find all text-containing elements (comprehensive list including formatted elements)
  const containers = Array.from(document.querySelectorAll('p, div, article, section, main, li, td, th, h1, h2, h3, h4, h5, h6, blockquote, figcaption, caption, pre, code'));

  // Helper to get all text nodes in order with their positions
  function getTextNodesWithPositions(container){
    const result = [];
    const walker = document.createTreeWalker(
      container,
      NodeFilter.SHOW_TEXT,
      null,
      false
    );
    let node;
    let accumulatedText = '';
    while(node = walker.nextNode()){
      const nodeText = node.nodeValue || '';
      if(!nodeText) continue;
      result.push({
        node: node,
        startPos: accumulatedText.length,
        text: nodeText
      });
      accumulatedText += nodeText;
    }
    return { nodes: result, fullText: accumulatedText };
  }

  // Helper to normalize text for matching (preserves position mapping)
  function buildNormalizedMap(text){
    // Maps normalized position -> original position
    const map = [];
    let normalized = '';
    let lastWasSpace = true; // Start true to trim leading
    for(let i = 0; i < text.length; i++){
      const c = text[i];
      if(/\\s/.test(c)){
        if(!lastWasSpace && normalized.length > 0){
          map.push(i);
          normalized += ' ';
          lastWasSpace = true;
        }
      } else {
        map.push(i);
        normalized += c.toLowerCase();
        lastWasSpace = false;
      }
    }
    // Trim trailing space
    if(normalized.endsWith(' ')){
      normalized = normalized.slice(0, -1);
      map.pop();
    }
    return { normalized, map };
  }

  // Highlight text nodes in a range (handles cross-element highlighting)
  function highlightRange(textNodesInfo, startOriginal, endOriginal){
    const nodes = textNodesInfo.nodes;
    let firstMark = null;

    for(const info of nodes){
      const nodeStart = info.startPos;
      const nodeEnd = nodeStart + info.text.length;

      // Check if this node overlaps with highlight range
      if(nodeEnd <= startOriginal || nodeStart >= endOriginal) continue;

      // Calculate overlap within this node
      const highlightStart = Math.max(0, startOriginal - nodeStart);
      const highlightEnd = Math.min(info.text.length, endOriginal - nodeStart);

      if(highlightStart >= highlightEnd) continue;

      try {
        const textNode = info.node;
        const parent = textNode.parentNode;
        if(!parent) continue;

        // Split text node if needed and wrap the highlighted portion
        const beforeText = info.text.substring(0, highlightStart);
        const highlightText = info.text.substring(highlightStart, highlightEnd);
        const afterText = info.text.substring(highlightEnd);

        const mark = document.createElement('mark');
        mark.className = cls;
        mark.style.setProperty('background-color', 'rgba(255,235,59,0.75)', 'important');
        mark.style.setProperty('color', 'inherit', 'important');
        mark.style.setProperty('padding', '0 0.12em', 'important');
        mark.style.setProperty('border-radius', '0.12em', 'important');
        mark.style.setProperty('box-decoration-break', 'clone', 'important');
        mark.style.setProperty('-webkit-box-decoration-break', 'clone', 'important');
        mark.textContent = highlightText;

        // Build replacement nodes
        const frag = document.createDocumentFragment();
        if(beforeText) frag.appendChild(document.createTextNode(beforeText));
        frag.appendChild(mark);
        if(afterText) frag.appendChild(document.createTextNode(afterText));

        parent.replaceChild(frag, textNode);

        if(!firstMark) firstMark = mark;
      } catch(e){
        console.log('Node highlight error:', e);
      }
    }

    if(firstMark){
      firstMark.scrollIntoView({behavior:'smooth', block:'center'});
      return true;
    }
    return false;
  }

  for(const container of containers){
    const textInfo = getTextNodesWithPositions(container);
    if(!textInfo.fullText.trim()) continue;

    const { normalized, map } = buildNormalizedMap(textInfo.fullText);
    const searchIndex = normalized.indexOf(searchText);

    if(searchIndex === -1) continue;

    // Map normalized positions back to original positions
    const originalStart = map[searchIndex] || 0;
    const originalEnd = (map[searchIndex + searchText.length - 1] || originalStart) + 1;

    if(highlightRange(textInfo, originalStart, originalEnd)){
      return true; // Successfully highlighted
    }
  }

  // Fallback: Try matching with more relaxed whitespace
  for(const container of containers){
    const textInfo = getTextNodesWithPositions(container);
    const fullText = textInfo.fullText;
    if(!fullText.trim()) continue;

    // Build a regex pattern that allows flexible whitespace
    const words = searchText.split(/\\s+/).filter(w => w);
    if(words.length === 0) continue;

    const pattern = words.map(w => w.replace(/[.*+?^\${}()|[\\]\\\\]/g, '\\\\\$&')).join('\\\\s+');
    const regex = new RegExp(pattern, 'i');
    const match = fullText.match(regex);

    if(match && match.index !== undefined){
      const originalStart = match.index;
      const originalEnd = match.index + match[0].length;

      if(highlightRange(textInfo, originalStart, originalEnd)){
        return true;
      }
    }
  }
  return false;
})($escaped);
''';
      final result = await _controller.runJavaScriptReturningResult(script);
      return result == true || result.toString() == 'true';
    } catch (_) {
      // ignore failures silently
      return false;
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
    if (articleId == null || articleId.isEmpty) {
      setState(() => _articleLoadFailed = true);
      debugPrint('⚠️ Article ID is null or empty');
      return null;
    }

    try {
      final dao = context.read<ArticleDao>();
      final row = await dao.findById(articleId);

      if (row == null) {
        setState(() => _articleLoadFailed = true);
        debugPrint('⚠️ Article $articleId not found in database (may have been deleted)');
        return null;
      }

      // Check if article is hidden (isRead = 2)
      if (row.isRead == 2) {
        setState(() => _articleLoadFailed = true);
        debugPrint('⚠️ Article $articleId is hidden/archived');
        return null;
      }

      final storedText = row.mainText?.trim() ?? '';
      final storedImage = row.imageUrl?.trim() ?? '';
      if (storedText.isEmpty && storedImage.isEmpty) return null;

      return ArticleReadabilityResult(
        mainText: storedText.isNotEmpty ? storedText : null,
        imageUrl: storedImage.isNotEmpty ? storedImage : null,
        pageTitle: row.title,
      );
    } catch (e) {
      setState(() => _articleLoadFailed = true);
      debugPrint('⚠️ Error loading article ${articleId}: $e');
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
      // Content not extracted yet - silently continue with webview mode
      // The calling code (_loadReaderContent) will handle falling back to website
      setState(() {
        _paywallLikely = false;
        _lines.clear();
        _currentLine = 0;
      });
      return;
    }

    final previewOnly = _isLikelyPreviewText(text, pagePaywalled);
    final rawParagraphs = text.isEmpty
        ? <String>[]
        : text
            .split(RegExp(r'\n+'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

    // 👇 Build final lines list: optional header + article content
    final combined = <String>[];
    final header = ((widget.title ?? '').trim().isNotEmpty
            ? (widget.title ?? '').trim()
            : (result?.pageTitle ?? '').trim())
        .trim();
    if (header.isNotEmpty) {
      combined.add(header);
    }
    combined.addAll(rawParagraphs);

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
      debugPrint('Failed to remove paywall overlays: $e');
    }
  }

  Future<void> _speakCurrentLine({bool auto = false}) async {
    _cancelAutoAdvanceTimer();
    // Only load lines on first play, not during auto-advance (optimization)
    if (!auto) {
      await _ensureLinesLoaded();
    }
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
      // Use cached language code to avoid repeated detection (optimization)
      if (_cachedTtsLanguageCode == null) {
        _cachedTtsLanguageCode = await _detectArticlePrimaryLanguage();
      }
      ttsLanguageCode = _cachedTtsLanguageCode!;
      // Normalize text for the article's language
      text = _normalizeForTts(text, ttsLanguageCode);
    }

    // Set TTS language to match the article's primary language (or translation language)
    // This ensures the SAME voice is used throughout the entire article
    // Only apply locale on first line or when not auto-advancing to avoid delays
    if (!auto || !_isPlaying) {
      await _applyTtsLocale(ttsLanguageCode);
    }

    // Mark article as read when starting to speak (first time)
    if (!_isPlaying && widget.articleId != null) {
      _markArticleAsRead();
    }

    // Highlight current line in reader mode (if setting ON)
    // Always await to ensure highlight completes before speaking
    await _highlightLine(_currentLine);

    // Sync global state with local lines
    _ttsState.lines = _lines;
    _ttsState.articleId = widget.articleId ?? '';
    _ttsState.articleTitle = widget.title ?? '';
    _ttsState.sourceTitle = widget.sourceTitle ?? _getSourceTitleFromArticles();
    _ttsState.isTranslatedContent = _isTranslatedView;
    _ttsState.readerModeOn = _readerOn; // Save reader mode state

    // Sync article list and current index for continuous reading
    _ttsState.allArticles = widget.allArticles;
    if (widget.articleId != null && widget.allArticles.isNotEmpty) {
      final index = widget.allArticles.indexWhere((a) => a.id == widget.articleId);
      if (index >= 0) {
        _ttsState.currentArticleIndex = index;
      }
    }

    // Only stop TTS and apply settings when starting fresh (not auto-advancing)
    // When auto-advancing, TTS has already completed so no need to stop
    if (!auto) {
      await _globalTts.stop();
      await _applySpeechRateFromSettings(restartIfPlaying: false);
    }

    // Only set playing state when starting fresh (not auto-advancing)
    // During auto-advance, these values are already set, so skip rebuild
    if (!auto || !_isPlaying) {
      setState(() {
        _isPlaying = true;
        _webHighlightText = null;
      });
    }

    // Enable WakeLock only when starting fresh (not on every line)
    if (!auto || !_isPlaying) {
      try {
        await WakelockPlus.enable();
        debugPrint('TTS: 🔒 WakeLock enabled - screen will stay on during playback');
      } catch (e) {
        debugPrint('TTS: ⚠️ Failed to enable WakeLock: $e');
      }
    }

    // Start periodic position saving during playback (only on first line)
    if (!auto) {
      _startPeriodicSave();
      _startPeriodicHighlightSync();
    }
    _lastSyncedLine = _currentLine;
    // Update notification without awaiting to avoid delays during auto-advance
    unawaited(_showReadingNotification(text));
    try {
      await _globalTts.speak(text);
    } catch (e) {
      debugPrint('❌ TTS speak failed: $e');
      if (mounted) {
        setState(() => _isPlaying = false);
      }
      try {
        await WakelockPlus.disable();
      } catch (e) {
        debugPrint('TTS: ⚠️ Failed to disable WakeLock after speak error: $e');
      }
      unawaited(_clearReadingNotification());
    }
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
    await _speakCurrentLine(auto: auto);
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

  /// Get the latest article list from provider (excludes hidden articles)
  /// This ensures we have fresh data even if articles were deleted/hidden
  /// Uses visibleItems to respect the user's sort order preference
  List<FeedItem> _getLatestArticleList() {
    final provider = context.read<RssProvider>();
    return provider.visibleItems; // Already sorted and filtered by provider
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

  void _markCurrentArticleRead() {
    if (widget.allArticles.isEmpty || widget.articleId == null) return;

    final currentIndex = widget.allArticles.indexWhere(
      (article) => article.id == widget.articleId,
    );
    if (currentIndex < 0) return;

    final currentArticle = widget.allArticles[currentIndex];
    if (currentArticle.isRead >= 1) return;

    context.read<RssProvider>().markRead(currentArticle, read: 1);
  }

  void _navigateToNextArticle() {
    if (!mounted || _disposed) return;

    _markCurrentArticleRead();

    // Get fresh article list from provider to avoid navigating to deleted articles
    final freshList = _getLatestArticleList();

    // Update global TTS state with fresh list
    _ttsState.allArticles = freshList;

    // Find current article in fresh list
    final currentIndex = freshList.indexWhere((a) => a.id == widget.articleId);

    if (currentIndex < 0) {
      // Current article was deleted/hidden - try to skip to first available article
      debugPrint('⚠️ Current article not found in fresh list, skipping to first available');
      if (freshList.isNotEmpty) {
        final firstArticle = freshList.first;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ArticleWebviewPage(
              articleId: firstArticle.id,
              url: firstArticle.link,
              title: firstArticle.title,
              sourceTitle: firstArticle.sourceTitle,
              initialMainText: firstArticle.mainText,
              initialImageUrl: firstArticle.imageUrl,
              allArticles: freshList,
              autoPlay: true,
            ),
          ),
        );
      } else {
        // No articles left - stop TTS and go back
        debugPrint('⚠️ No articles available, stopping TTS');
        stopGlobalTts();
        Navigator.of(context).pop();
      }
      return;
    }

    // Get next article from fresh list
    if (currentIndex + 1 < freshList.length) {
      final nextArticle = freshList[currentIndex + 1];
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ArticleWebviewPage(
            articleId: nextArticle.id,
            url: nextArticle.link,
            title: nextArticle.title,
            sourceTitle: nextArticle.sourceTitle,
            initialMainText: nextArticle.mainText,
            initialImageUrl: nextArticle.imageUrl,
            allArticles: freshList, // Use fresh list
            autoPlay: true, // Auto-start playing the next article
          ),
        ),
      );
    } else {
      // Reached end of list - stop playback
      debugPrint('✅ Reached end of article list, stopping TTS');
      setState(() => _isPlaying = false);
      WakelockPlus.disable().catchError((e) => debugPrint('TTS: Failed to disable WakeLock: $e'));
    }
  }

  void _goToPreviousArticle() {
    _cancelAutoAdvanceTimer();
    if (!mounted || _disposed) return;

    _markCurrentArticleRead();

    // Get fresh article list from provider
    final freshList = _getLatestArticleList();

    // Update global TTS state with fresh list
    _ttsState.allArticles = freshList;

    // Find current article in fresh list
    final currentIndex = freshList.indexWhere((a) => a.id == widget.articleId);

    if (currentIndex < 0) {
      // Current article was deleted/hidden - go back to news page
      debugPrint('⚠️ Current article not found, going back to news page');
      Navigator.of(context).pop();
      return;
    }

    // Get previous article from fresh list
    if (currentIndex > 0) {
      final previousArticle = freshList[currentIndex - 1];
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ArticleWebviewPage(
            articleId: previousArticle.id,
            url: previousArticle.link,
            title: previousArticle.title,
            sourceTitle: previousArticle.sourceTitle,
            initialMainText: previousArticle.mainText,
            initialImageUrl: previousArticle.imageUrl,
            allArticles: freshList, // Use fresh list
            autoPlay: false, // Don't auto-play when going backwards
          ),
        ),
      );
    } else {
      // At the beginning - go back to news page
      Navigator.of(context).pop();
    }
  }

  void _goToNextArticleNow() {
    _cancelAutoAdvanceTimer();
    if (!mounted || _disposed) return;

    _markCurrentArticleRead();

    // Get fresh article list from provider
    final freshList = _getLatestArticleList();

    // Update global TTS state with fresh list
    _ttsState.allArticles = freshList;

    // Find current article in fresh list
    final currentIndex = freshList.indexWhere((a) => a.id == widget.articleId);

    if (currentIndex < 0) {
      // Current article was deleted/hidden - try to skip to first available article
      debugPrint('⚠️ Current article not found, skipping to first available');
      if (freshList.isNotEmpty) {
        final firstArticle = freshList.first;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ArticleWebviewPage(
              articleId: firstArticle.id,
              url: firstArticle.link,
              title: firstArticle.title,
              sourceTitle: firstArticle.sourceTitle,
              initialMainText: firstArticle.mainText,
              initialImageUrl: firstArticle.imageUrl,
              allArticles: freshList,
              autoPlay: true,
            ),
          ),
        );
      } else {
        // No articles left - stop TTS and go back
        debugPrint('⚠️ No articles available, stopping TTS');
        stopGlobalTts();
        Navigator.of(context).pop();
      }
      return;
    }

    // Get next article from fresh list
    if (currentIndex + 1 < freshList.length) {
      final nextArticle = freshList[currentIndex + 1];
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ArticleWebviewPage(
            articleId: nextArticle.id,
            url: nextArticle.link,
            title: nextArticle.title,
            sourceTitle: nextArticle.sourceTitle,
            initialMainText: nextArticle.mainText,
            initialImageUrl: nextArticle.imageUrl,
            allArticles: freshList, // Use fresh list
            autoPlay: true, // Auto-play when manually skipping to next article
          ),
        ),
      );
    } else {
      // At the end - stay on current article and show message
      debugPrint('✅ Already at last article');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Already at the last article'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
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
        _isForeground = false;
        unawaited(_saveReadingPosition());
        break;
      case AppLifecycleState.resumed:
        // App coming back to foreground
        _isForeground = true;

        // Check if TTS moved to a different article while in background
        final globalArticleId = _ttsState.articleId;
        final currentWidgetArticleId = widget.articleId ?? '';

        if (globalArticleId.isNotEmpty &&
            currentWidgetArticleId.isNotEmpty &&
            globalArticleId != currentWidgetArticleId &&
            _ttsState.isPlaying) {
          // TTS has moved to a different article during background playback
          // Navigate to the current article being read
          _navigateToGlobalArticle();
          return;
        }

        // Sync local state with global state if same article
        if (globalArticleId == currentWidgetArticleId && _ttsState.lines.isNotEmpty) {
          // Update local state to match global state
          if (_ttsState.currentLine != _currentLine) {
            setState(() {
              _currentLine = _ttsState.currentLine;
              _isPlaying = _ttsState.isPlaying;
            });
          }
        }

        // Refresh notification and highlight
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
        _isForeground = false;
        break;
    }
  }

  /// Navigate to the article currently being read by global TTS
  void _navigateToGlobalArticle() {
    if (!mounted || _disposed) return;

    final globalArticleId = _ttsState.articleId;
    if (globalArticleId.isEmpty) return;

    // Find the article in the list
    final articleIndex = widget.allArticles.indexWhere((a) => a.id == globalArticleId);
    if (articleIndex < 0) return;

    final article = widget.allArticles[articleIndex];

    // Mark current article as read before navigating
    _markCurrentArticleRead();

    // Navigate to the article being read
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ArticleWebviewPage(
          articleId: article.id,
          url: article.link,
          title: article.title,
          initialMainText: article.mainText,
          initialImageUrl: article.imageUrl,
          allArticles: widget.allArticles,
          autoPlay: true, // Continue playing
        ),
      ),
    );
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

    // Show error UI if article failed to load (deleted/hidden)
    if (_articleLoadFailed) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Article Not Available'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              // Stop TTS if playing
              if (_isPlaying) {
                await stopGlobalTts();
              }
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.article_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'Article no longer available',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'This article may have been deleted or hidden',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () async {
                    // Stop TTS if playing
                    if (_isPlaying) {
                      await stopGlobalTts();
                    }
                    if (mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _saveReadingPosition();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const SizedBox.shrink(),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
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
            if (!_articleUnavailable) WebViewWidget(controller: _controller),
            if (_articleUnavailable)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.article_outlined, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _articleUnavailableMessage,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text('Go back'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_isLoading && !_articleUnavailable)
              const LinearProgressIndicator(
                minHeight: 2,
              ),
            if (_paywallLikely && !_articleUnavailable)
              Positioned(
                top: 16,
                left: 12,
                right: 12,
                child: SafeArea(
                  child: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.orange.shade50.withValues(alpha: 0.95),
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
