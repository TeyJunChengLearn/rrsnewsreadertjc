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

import '../providers/settings_provider.dart';
import '../services/readability_service.dart';

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
  switch (code) {
    case 'en':
      return 'en-US';
    case 'ms':
      return 'ms-MY';
    case 'zh-CN':
      return 'zh-CN';
    case 'zh-TW':
      return 'zh-TW';
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

  const ArticleWebviewPage({
    super.key,
    required this.url,
    this.title,
  });

  @override
  State<ArticleWebviewPage> createState() => _ArticleWebviewPageState();
}

class _ArticleWebviewPageState extends State<ArticleWebviewPage> {
  late final WebViewController _controller;
  final FlutterTts _tts = FlutterTts();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isLoading = true;
  bool _readerOn = false;
  bool _paywallLikely = false;
  // Reader content (one line per highlightable/speakable chunk)
  final List<String> _lines = [];
  List<String>? _originalLinesCache; // for reverse after translation
  int _currentLine = 0;
  bool _triedDomExtraction = false;
  // Hero image from Readability result (used in reader HTML)
  String? _heroImageUrl;

  // TTS state
  bool _isPlaying = false;

  // Translation state
  bool _isTranslating = false;
  bool _isTranslatedView = false;
  TranslateLanguage? _srcLangDetected;
  bool _hasInternalPageInHistory = false;
  SettingsProvider? _settings;
  VoidCallback? _settingsListener;
  static const int _readingNotificationId = 22;
  String? _webHighlightText;

  Future<bool> _handleBackNavigation() async {
    await _stopSpeaking();

    if (!mounted) return true;

    if (_readerOn) {
      setState(() {
        _readerOn = false;
        _hasInternalPageInHistory = true;
      });

      await _controller.loadRequest(Uri.parse(widget.url));
      return false;
    }
    if (_hasInternalPageInHistory) {
      return true;
    }
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
    }

    return true;
  }

  @override
  void initState() {
    super.initState();
    _initWebView();

    _tts.setSharedInstance(true);
    _tts.setSpeechRate(0.5);
    _tts.setPitch(1.0);

    _tts.setCompletionHandler(() async {
      if (!_isPlaying) return;
      await _speakNextLine(auto: true);
    });
    _tts.setCancelHandler(() {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    });
     _attachSettingsListener();
    unawaited(_initNotifications());
    // Preload Readability text in background so TTS/translate work in both modes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureLinesLoaded();
    });
  }
 void _attachSettingsListener() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _settings = context.read<SettingsProvider>();
      _settingsListener = () {
        _applySpeechRateFromSettings();
      };
      _applySpeechRateFromSettings();
      _settings?.addListener(_settingsListener!);
    });
  }

  void _applySpeechRateFromSettings() {
    final settings = _settings ?? context.read<SettingsProvider>();
    _settings ??= settings;
    final rate = settings.ttsSpeechRate;
    _tts.setSpeechRate(rate);
  }
  /// Choose a concrete voice for the BCP language code (e.g., 'zh-CN')
  /// Choose a concrete voice for the BCP language code (e.g., 'zh-CN')
  Future<void> _applyTtsLocale(String bcpCode) async {
    await _tts.setLanguage(_ttsLocaleForCode(bcpCode));
    try {
      final List<dynamic>? voices = await _tts.getVoices;
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

      await _tts.setVoice({
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
            setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            setState(() => _isLoading = false);
          },
        ),
      );

    // Default: show full website
    _controller.loadRequest(Uri.parse(widget.url));
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _notifications.initialize(settings);
  }

  Future<void> _loadReaderContent() async {
    setState(() {
      _isLoading = true;
    });

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

    if (mounted) {
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

    if (_readerOn) {
      // Clear any lingering overlay highlight when we switch to reader mode
      if (_webHighlightText != null) {
        setState(() => _webHighlightText = null);
      }

      try {
        await _controller.runJavaScript(
          'window.flutterHighlightLine && window.flutterHighlightLine($index);',
        );
      } catch (_) {
        // ignore JS errors
      }
    } else {
      if (index < 0 || index >= _lines.length) return;
      final text = _lines[index].trim();
      if (text.isEmpty) return;
      setState(() => _webHighlightText = text);
      await _highlightInWebPage(text);
    }
  }

  Future<void> _highlightInWebPage(String text) async {
    try {
      final escaped = jsonEncode(text);
      final script = '''
(function(txt){
  if(!txt){return;}
  const cls='flutter-tts-highlight';
  document.querySelectorAll('mark.'+cls).forEach(m=>{
    const parent=m.parentNode;
    if(!parent){return;}
    parent.replaceChild(document.createTextNode(m.textContent||''), m);
    parent.normalize();
  });
  const regexText = txt.replace(/[.*+?^\${}()|[\\]\\\\]/g,"\\\\\$&");
  const regex = new RegExp(regexText,'i');
  function walk(node){
    if(!node){return false;}
    if(node.nodeType===3){
      const match = regex.exec(node.data);
      if(match){
        const range=document.createRange();
        range.setStart(node, match.index);
        range.setEnd(node, match.index + match[0].length);
        const mark=document.createElement('mark');
        mark.className=cls;
        mark.style.backgroundColor='rgba(255,235,59,0.4)';
        range.surroundContents(mark);
        mark.scrollIntoView({behavior:'smooth', block:'center'});
        return true;
      }
    }
    const children = Array.from(node.childNodes||[]);
    for(let i=0;i<children.length;i++){
      if(walk(children[i])) return true;
    }
    return false;
  }
  walk(document.body);
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
    _hasInternalPageInHistory = true;

    await _controller.loadRequest(
      Uri.dataFromString(html, mimeType: 'text/html', encoding: utf8),
    );

    if (showLoading && mounted) {
      setState(() => _isLoading = false);
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
        'var paras=document.querySelectorAll("p[data-idx]");'
        'for(var i=0;i<paras.length;i++){'
        'var el=paras[i];'
        'var idx=parseInt(el.getAttribute("data-idx")||"-1");'
        'if(idx===index){'
        'el.classList.add("hl");'
        'el.scrollIntoView({behavior:"smooth",block:"center"});'
        '}else{'
        'el.classList.remove("hl");'
        '}'
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

    final hasMarkers = previewMarkers.any(lower.contains);
    final trailingEllipsis = RegExp(r'(\.\.\.|…)$').hasMatch(trimmed);

    if (hasMarkers || trailingEllipsis) return true;

    if (pagePaywalled && wordCount < 180) return true;

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
        setState(() {
          _lines
            ..clear()
            ..addAll(_originalLinesCache!);
          _isTranslatedView = false;
          _currentLine = 0;
          _webHighlightText = null;
        });
        await _reloadReaderHtml(showLoading: true);
        await _applyTtsLocale('en');
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

    setState(() {
      _lines
        ..clear()
        ..addAll(translated);
      _isTranslatedView = true;
      _isTranslating = false;
      _currentLine = 0;
      _webHighlightText = null;
    });
    await _reloadReaderHtml(showLoading: true);
    await _applyTtsLocale(code);
  }

  // --------------- TTS playback ---------------

  /// Ensure we have extracted article text (Readability) for TTS/translate,
  /// no matter which mode (reader vs full web) we are in.
  Future<void> _ensureLinesLoaded() async {
    if (_lines.isNotEmpty) return;

    final readability = context.read<Readability4JExtended>();
    ArticleReadabilityResult? result;
    try {
      result = await readability.extractMainContent(widget.url);
    } catch (_) {
      result = null;
    }
    final rssOnly = (result?.source ?? '').toUpperCase() == 'RSS';

    if ((result == null || _looksLikePreview(result) || rssOnly) &&
        !_triedDomExtraction) {
      _triedDomExtraction = true;
      final domResult = await _extractFromWebViewDom();
      if (domResult != null && (domResult.mainText?.trim().isNotEmpty ?? false)) {
        result = domResult;
      }
    }
    if (!mounted) return;

    final hasNoText = result == null || (result.mainText?.trim().isEmpty ?? true);
    final pagePaywalled = result?.isPaywalled ?? false;
    _paywallLikely = pagePaywalled && hasNoText;

    if (hasNoText) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _paywallLikely
                ? 'This article looks paywalled. Sign in on the site (via Add feed → "Requires login") then reload.'
                : 'Unable to extract article text for reading.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      setState(() {});
      return;
    }

    final text = (result.mainText ?? '').trim();
    final previewOnly = _isLikelyPreviewText(text, pagePaywalled);
    final rawLines = text.isEmpty
        ? <String>[]
        : text
            .split('\n\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

    // 👇 Build final lines list: optional header + article content
    final combined = <String>[];
    final header = ((widget.title ?? '').trim().isNotEmpty
            ? (widget.title ?? '').trim()
            : (result.pageTitle ?? '').trim())
        .trim();
    if (header.isNotEmpty) {
      combined.add(header);
    }
    combined.addAll(rawLines);

    _heroImageUrl ??= result.imageUrl;

     // Treat the page as paywalled only when the extracted text still looks
    // like a short preview. Some sites keep paywall markers in the DOM even
    // after login, so don't block full-text articles just because markers
    // exist.
    final looksPaywalled = previewOnly || (pagePaywalled && rawLines.length <= 3);
    setState(() {
      _paywallLikely = looksPaywalled;
      _lines
        ..clear()
        ..addAll(combined);
      _currentLine = 0;
    });
  }
  bool _looksLikePreview(ArticleReadabilityResult result) {
    final text = (result.mainText ?? '').trim();
    if (text.isEmpty) return true;
    return _isLikelyPreviewText(text, result.isPaywalled ?? false);
  }

  Future<ArticleReadabilityResult?> _extractFromWebViewDom() async {
    try {
      await _waitForPageToSettle();
      final raw = await _controller.runJavaScriptReturningResult(
        '(() => document.documentElement.outerHTML)();',
      );

      if (!mounted) return null;

      final html = _normalizeJsString(raw);
      if (html == null || html.isEmpty) return null;

      final readability = context.read<Readability4JExtended>();
      return await readability.extractFromHtml(
        widget.url,
        html,
        strategyName: 'WebView DOM',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _waitForPageToSettle() async {
    // Wait briefly for the current page load + JS-rendered content to settle.
    for (var i = 0; i < 5; i++) {
      if (!_isLoading) break;
      await Future.delayed(const Duration(milliseconds: 200));
    }

    await Future.delayed(const Duration(milliseconds: 200));
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

    if (targetCode != 'off') {
      text = _normalizeForTts(text, targetCode);
    }

    // Highlight current line in reader mode (if setting ON)
    await _highlightLine(_currentLine);

    setState(() {
      _isPlaying = true;
      _webHighlightText = null;
    });
    await _showReadingNotification(text);
    _applySpeechRateFromSettings();
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _speakNextLine({bool auto = false}) async {
    await _ensureLinesLoaded();
    if (_lines.isEmpty) {
      setState(() => _isPlaying = false);
      await _clearReadingNotification();
      return;
    }

    int i = _currentLine + 1;

    if (i >= _lines.length) {
      setState(() => _isPlaying = false);
      await _clearReadingNotification();
      return;
    }

    setState(() => _currentLine = i);
    await _speakCurrentLine();
  }

  Future<void> _speakPrevLine() async {
    await _ensureLinesLoaded();
    if (_lines.isEmpty) return;

    int i = _currentLine - 1;
    if (i < 0) return;

    setState(() => _currentLine = i);
    await _speakCurrentLine();
  }

  Future<void> _stopSpeaking() async {
    await _tts.stop();
    if (mounted) {
      setState(() => _isPlaying = false);
      await _clearReadingNotification();
    }
  }

  Future<void> _goToFirst() async {
    await _ensureLinesLoaded();
    if (_lines.isEmpty) return;

    setState(() => _currentLine = 0);
    await _speakCurrentLine();
  }

  Future<void> _goToLast() async {
    await _ensureLinesLoaded();
    if (_lines.isEmpty) return;

    final i = _lines.length - 1;
    setState(() => _currentLine = i);
    await _speakCurrentLine();
  }

  Future<void> _showReadingNotification(String lineText) async {
    final title =
        (widget.title?.isNotEmpty ?? false) ? widget.title! : 'Reading article';
    final position = '${_currentLine + 1}/${_lines.length}';
    final android = AndroidNotificationDetails(
      'reading_channel',
      'Reading',
      channelDescription: 'Shows the sentence currently being read aloud.',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      onlyAlertOnce: true,
      styleInformation: BigTextStyleInformation('$lineText'),
    );
    const ios = DarwinNotificationDetails(
      presentAlert: false,
      presentSound: false,
      presentBadge: false,
    );

    await _notifications.show(
      _readingNotificationId,
      '$title  ($position)',
      lineText,
      NotificationDetails(android: android, iOS: ios),
    );
  }

  Future<void> _clearReadingNotification() async {
    await _notifications.cancel(_readingNotificationId);
  }
  // --------------- UI ---------------

  Future<void> _toggleReader() async {
    setState(() {
      _readerOn = !_readerOn;
      if (_readerOn) {
        _hasInternalPageInHistory = true;
      }
    });

    if (_readerOn) {
      await _loadReaderContent();
    } else {
      await _stopSpeaking();
      // Go back to full website, but KEEP _lines so TTS still works
      await _controller.loadRequest(Uri.parse(widget.url));
    }
  }

  @override
  void dispose() {
    if (_settingsListener != null && _settings != null) {
      _settings!.removeListener(_settingsListener!);
    }
    _tts.stop();
    unawaited(_clearReadingNotification());
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
                    onPressed: _goToFirst),
                IconButton(
                    icon: const Icon(Icons.fast_rewind),
                    onPressed: _speakPrevLine),
                IconButton(
                  icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                  onPressed: _isPlaying ? _stopSpeaking : _speakCurrentLine,
                  iconSize: 32,
                ),
                IconButton(
                    icon: const Icon(Icons.fast_forward),
                    onPressed: _speakNextLine),
                IconButton(
                    icon: const Icon(Icons.skip_next), onPressed: _goToLast),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
