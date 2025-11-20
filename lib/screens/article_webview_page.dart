import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';

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
      return 'zh';
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
@@ -69,51 +70,50 @@ String _ttsLocaleForCode(String code) {
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
      return 'pt-BR';
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

String _toChineseNumber(String numStr) {
  final n = int.tryParse(numStr);
  if (n == null) return numStr;
  return _intToChinese(n);
}

String _intToChinese(int n) {
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
@@ -128,665 +128,521 @@ String _intToChinese(int n) {

  String out = '';
  int bigPos = 0;
  while (n > 0) {
    final sec = n % 10000;
    if (sec != 0) {
      String part = sectionToCn(sec);
      if (bigPos > 0) {
        part += bigUnits[bigPos];
      }
      out = part + out;
    } else {
      if (!out.startsWith('零') && out.isNotEmpty) {
        out = '零$out';
      }
    }
    bigPos++;
    n ~/= 10000;
  }

  if (out.startsWith('一十')) {
    out = out.substring(1);
  }
  return out;
}

class ArticleWebviewPage extends StatefulWidget {
  final String url;
  const ArticleWebviewPage({super.key, required this.url});

  @override
  State<ArticleWebviewPage> createState() => _ArticleWebviewPageState();
}

class _ArticleWebviewPageState extends State<ArticleWebviewPage> {
  late final WebViewController _controller;
  final FlutterTts _tts = FlutterTts();

  bool _isLoading = true;
  bool _readerOn = true;

  List<String> _lines = [];
  List<String>? _originalLinesCache;
  int _currentLine = 0;

  bool _isPlaying = false;

  bool _isTranslating = false;
  bool _isTranslatedView = false;
  TranslateLanguage? _srcLangDetected;

  @override
  void initState() {
    super.initState();
    _initTts();
    _initWebView();
  }

  // ---------------- TTS setup + helpers ----------------

  Future<void> _initTts() async {
    await _tts.setVolume(1.0);
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
    try {
      await _tts.setEngine('com.google.android.tts');
    } catch (_) {}

    _tts.setCompletionHandler(() async {
      if (!_isPlaying) return;
      await _speakNextLine(auto: true);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  Future<void> _applyTtsLocale(String bcpCode) async {
    await _tts.setLanguage(_ttsLocaleForCode(bcpCode));
    try {
      final List<dynamic>? voices = await _tts.getVoices;
      if (voices == null) return;

      Map<String, dynamic>? chosen;
      final lc = bcpCode.toLowerCase();
      final base = lc.split('-').first;

      final parsed = voices
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
          .toList();

      chosen = parsed.firstWhere(
        (v) => (v['locale'] ?? '').toString().toLowerCase() == lc,
        orElse: () => parsed.firstWhere(
          (v) =>
              (v['locale'] ?? '').toString().toLowerCase().startsWith(base),
          orElse: () => <String, dynamic>{},
        ),
      );

      if (chosen != null && chosen.isNotEmpty) {
        await _tts.setVoice({
          'name': chosen['name'],
          'locale': chosen['locale'],
        });
      }
    } catch (_) {/* ignore */}
  }

  String _normalizeForTts(String s, String langCode) {
    if (langCode.startsWith('zh')) {
      s = s.replaceAllMapped(
        RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'),
        (m) =>
            '${_toChineseNumber(m[1]!)}年${_toChineseNumber(m[2]!)}月${_toChineseNumber(m[3]!)}日',
      );
      s = s.replaceAllMapped(
        RegExp(r'(\d{1,2}):(\d{2})'),
        (m) => '${_toChineseNumber(m[1]!)}点${_toChineseNumber(m[2]!)}分',
      );
      s = s.replaceAllMapped(
        RegExp(r'(\d+)%'),
        (m) => '百分之${_toChineseNumber(m[1]!)}',
      );
      s = s
          .replaceAll('km/h', '公里每小时')
          .replaceAll(RegExp(r'\bkm\b'), '公里');
      s = s.replaceAll('USD', '美元').replaceAll(RegExp(r'\$'), '美元');
      s = s.replaceAllMapped(
        RegExp(r'\d+'),
        (m) => _toChineseNumber(m[0]!),
      );
    } else if (langCode == 'ja') {
      s = s.replaceAllMapped(RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'),
          (m) => '${m[1]}年${m[2]}月${m[3]}日');
      s = s.replaceAllMapped(
          RegExp(r'(\d{1,2}):(\d{2})'), (m) => '${m[1]}時${m[2]}分');
      s = s
          .replaceAll('km/h', 'キロ毎時')
          .replaceAll(RegExp(r'\bkm\b'), 'キロ');
      s = s.replaceAll('USD', '米ドル').replaceAll(RegExp(r'\$'), 'ドル');
    } else if (langCode == 'ko') {
      s = s.replaceAllMapped(
          RegExp(r'(\d{1,2}):(\d{2})'), (m) => '${m[1]}시 ${m[2]}분');
      s = s
          .replaceAll('km/h', '시속 킬로미터')
          .replaceAll(RegExp(r'\bkm\b'), '킬로미터');
      s = s.replaceAll('USD', '미 달러').replaceAll(RegExp(r'\$'), '달러');
    }
    return s;
  }

  // ---------------- WebView + Reader ----------------

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
        ),
      );

    if (_readerOn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadReaderContent();
      });
    } else {
      _controller.loadRequest(Uri.parse(widget.url));
    }
  }

  Future<void> _loadReaderContent() async {
    setState(() {
      _isLoading = true;
      _isTranslatedView = false;
      _originalLinesCache = null;
    });

    final readability = context.read<Readability4JExtended>();
    ArticleReadabilityResult? result;
    try {
      result = await readability.extractMainContent(widget.url);
    } catch (_) {
      result = null;
    }

    if (!mounted) return;

    if (result == null || (result.mainText?.trim().isEmpty ?? true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load reader view, showing website.')),
      );
      setState(() {
        _readerOn = false;
        _lines = [];
        _currentLine = 0;
        _isLoading = false;
      });
      await _controller.loadRequest(Uri.parse(widget.url));
      return;
    }

    final text = (result.mainText ?? '').trim();
    final lines = text.isEmpty
        ? <String>[]
        : text
            .split('\n\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
    final html = _buildReaderHtml(lines, result.imageUrl);

    await _controller.loadRequest(
      Uri.dataFromString(
        html,
        mimeType: 'text/html',
        encoding: utf8,
      ),
    );

    setState(() {
      _lines = lines;
      _currentLine = 0;
      _isLoading = false;
    });
  }

  String _buildReaderHtml(List<String> lines, String? heroUrl) {
    final buffer = StringBuffer();
    buffer.writeln(
        '<html><head><meta name="viewport" content="width=device-width, initial-scale=1.0">');
    buffer.writeln(
        '<style>body{margin:0;background:#fff;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Oxygen,Ubuntu,Cantarell,"Open Sans","Helvetica Neue",sans-serif;}');
    buffer.writeln('.wrap{max-width:760px;margin:0 auto;padding:16px;}');
    buffer.writeln(
        'img.hero{width:100%;height:auto;border-radius:8px;margin-bottom:16px;object-fit:cover;}');
    buffer.writeln('p{font-size:1.02rem;line-height:1.7;margin:0 0 1rem 0;}');
    buffer.writeln('</style></head><body><div class="wrap">');
    if (heroUrl != null && heroUrl.isNotEmpty) {
      buffer.writeln('<img src="' + heroUrl + '" class="hero" />');
    }
    for (final p in lines) {
      final escaped = p
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;');
      buffer.writeln('<p>' + escaped + '</p>');
    }
    buffer.writeln('</div></body></html>');
    return buffer.toString();
  }

  // --------------- Translation ---------------

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
      final code = await id.identifyLanguage(sample.isNotEmpty ? sample : 'Hello');
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
    if (!_readerOn || _lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open Reader mode first.')),
      );
      return;
    }

    if (_isTranslatedView) {
      if (_originalLinesCache != null) {
        setState(() {
          _lines = List<String>.from(_originalLinesCache!);
          _isTranslatedView = false;
          _currentLine = 0;
        });

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

    final src = await _detectSourceLang();
    final manager = OnDeviceTranslatorModelManager();
    await manager.downloadModel(bcpFromTranslateLanguage(src));
    await manager.downloadModel(bcpFromTranslateLanguage(target));

    final translator = OnDeviceTranslator(sourceLanguage: src, targetLanguage: target);

    _originalLinesCache ??= List<String>.from(_lines);
    final translated = <String>[];

    for (final line in _lines) {
      final t = await translator.translateText(line);
      translated.add(t);
    }

    await translator.close();

    if (!mounted) return;

    setState(() {
      _lines = translated;
      _isTranslatedView = true;
      _isTranslating = false;
      _currentLine = 0;
    });

    await _applyTtsLocale(code);
  }

  // --------------- TTS playback ---------------

  Future<void> _speakCurrentLine() async {
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

    setState(() => _isPlaying = true);
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _speakNextLine({bool auto = false}) async {
    if (_lines.isEmpty) return;

    int i = _currentLine + 1;

    if (i >= _lines.length) {
      setState(() => _isPlaying = false);
      return;
    }

    setState(() => _currentLine = i);
    await _speakCurrentLine();
  }

  Future<void> _speakPrevLine() async {
    if (_lines.isEmpty) return;

    final i = _currentLine - 1;
    if (i < 0) return;

    setState(() => _currentLine = i);
    await _speakCurrentLine();
  }

  Future<void> _stopSpeaking() async {
    await _tts.stop();
    if (mounted) setState(() => _isPlaying = false);
  }

  Future<void> _goToFirst() async {
    if (_lines.isEmpty) return;
    setState(() => _currentLine = 0);
    await _speakCurrentLine();
  }

  Future<void> _goToLast() async {
    if (_lines.isEmpty) return;

    final i = _lines.length - 1;
    setState(() => _currentLine = i);
    await _speakCurrentLine();
  }

  Future<void> _openWebsiteView() async {
    if (!_readerOn) return;
    await _toggleReader();
  }

  // --------------- UI ---------------

  Future<void> _toggleReader() async {
    setState(() {
      _readerOn = !_readerOn;
      _isTranslatedView = false;
      _originalLinesCache = null;
    });
    if (_readerOn) {
      await _loadReaderContent();
    } else {
      await _stopSpeaking();
      await _controller.loadRequest(Uri.parse(widget.url));
      setState(() {
        _lines = [];
        _currentLine = 0;
      });
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final canTranslate = settings.translateLangCode != 'off';

    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
        leading: IconButton(
@@ -801,74 +657,71 @@ class _ArticleWebviewPageState extends State<ArticleWebviewPage> {
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextButton.icon(
                onPressed: _openWebsiteView,
                icon: const Icon(Icons.public),
                label: const Text('Website'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          IconButton(
            icon: Icon(_readerOn ? Icons.web : Icons.chrome_reader_mode),
            onPressed: _toggleReader,
            tooltip: _readerOn ? 'Show original page' : 'Reader mode',
          ),
          if (_readerOn && canTranslate)
            IconButton(
              icon: (_isLoading || _isTranslating)
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_isTranslatedView ? Icons.undo : Icons.g_translate),
              onPressed:
                  (_isLoading || _isTranslating) ? null : _toggleTranslateToSetting,
              tooltip: _isTranslatedView ? 'Show original' : 'Translate',
            ),
          if (!_readerOn)
            IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => _controller.reload()),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
      bottomNavigationBar: _readerOn
          ? SafeArea(
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
                        icon: const Icon(Icons.skip_next),
                        onPressed: _goToLast),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
