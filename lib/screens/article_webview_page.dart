// lib/screens/article_webview_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';

import '../providers/settings_provider.dart';

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
      return 'en';
  }
}

/// TTS locale preference list for a language code saved in settings
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

// ====== added: proper Chinese number converter ======
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
        res = digits[v] + smallUnits[unitPos] + res;
        zero = false;
      }
      unitPos++;
      sec ~/= 10;
    }
    return res;
  }

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
// ====== end added ======

class ArticleWebviewPage extends StatefulWidget {
  final String url; // only URL, no title in ctor
  const ArticleWebviewPage({super.key, required this.url});

  @override
  State<ArticleWebviewPage> createState() => _ArticleWebviewPageState();
}

class _ArticleWebviewPageState extends State<ArticleWebviewPage> {
  late final WebViewController _controller;
  final FlutterTts _tts = FlutterTts();

  bool _isLoading = true;
  bool _readerOn = true;

  // Reader content (one line per highlightable/speakable chunk)
  List<String> _lines = [];
  List<String>? _originalLinesCache; // for reverse after translation
  int _currentLine = 0;

  // TTS state
  bool _isPlaying = false;

  // Translation state
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

  /// Choose a concrete voice for the BCP language code (e.g., 'zh-CN')
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
          (v) => (v['locale'] ?? '').toString().toLowerCase().startsWith(base),
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

  /// Normalize digits/symbols so TTS doesn’t switch to English mid-sentence
  String _normalizeForTts(String s, String langCode) {
    if (langCode.startsWith('zh')) {
      // dates 2025-10-30 -> 2025年10月30日  (each part converted)
      s = s.replaceAllMapped(
        RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'),
        (m) =>
            '${_toChineseNumber(m[1]!)}年${_toChineseNumber(m[2]!)}月${_toChineseNumber(m[3]!)}日',
      );
      // time 14:05 -> 14点05分
      s = s.replaceAllMapped(
        RegExp(r'(\d{1,2}):(\d{2})'),
        (m) => '${_toChineseNumber(m[1]!)}点${_toChineseNumber(m[2]!)}分',
      );
      // percent 12% -> 百分之十二
      s = s.replaceAllMapped(
        RegExp(r'(\d+)%'),
        (m) => '百分之${_toChineseNumber(m[1]!)}',
      );
      // units & currency
      s = s.replaceAll('km/h', '公里每小时').replaceAll(RegExp(r'\bkm\b'), '公里');
      s = s.replaceAll('USD', '美元').replaceAll(RegExp(r'\$'), '美元');
      // >>> main change: whole numbers -> Chinese
      s = s.replaceAllMapped(
        RegExp(r'\d+'),
        (m) => _toChineseNumber(m[0]!),
      );
    } else if (langCode == 'ja') {
      s = s.replaceAllMapped(RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'),
          (m) => '${m[1]}年${m[2]}月${m[3]}日');
      s = s.replaceAllMapped(
          RegExp(r'(\d{1,2}):(\d{2})'), (m) => '${m[1]}時${m[2]}分');
      s = s.replaceAll('km/h', 'キロ毎時').replaceAll(RegExp(r'\bkm\b'), 'キロ');
      s = s.replaceAll('USD', '米ドル').replaceAll(RegExp(r'\$'), 'ドル');
    } else if (langCode == 'ko') {
      s = s.replaceAllMapped(
          RegExp(r'(\d{1,2}):(\d{2})'), (m) => '${m[1]}시 ${m[2]}분');
      s = s.replaceAll('km/h', '시속 킬로미터').replaceAll(RegExp(r'\bkm\b'), '킬로미터');
      s = s.replaceAll('USD', '미 달러').replaceAll(RegExp(r'\$'), '달러');
    }
    return s;
  }

  // ---------------- WebView + Reader ----------------

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('flutterArticle', onMessageReceived: (msg) {
        final parts = msg.message
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (!mounted) return;
        setState(() {
          _lines = parts;
          _originalLinesCache ??= List<String>.from(parts);
          _currentLine = 0;
        });
      })
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) async {
            setState(() => _isLoading = false);
            if (_readerOn) await _injectReader();
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _injectReader() async {
    const js = r"""
      (function() {
        function txt(el){return el?el.textContent.trim():'';}
        function isJunk(s){
          if (!s) return false;
          s = s.toLowerCase();
          return s.includes('advert')||s.includes('promo')||s.includes('social')||
                s.includes('share')||s.includes('bookmark');
        }
        function esc(t){ return t.replace(/</g,'&lt;').replace(/>/g,'&gt;'); }

        var titleEl = document.querySelector('h1,[data-component="headline"],.story-body__h1');
        var title = txt(titleEl) || document.title || '';

        var articleEl = document.querySelector('article') ||
                        document.querySelector('main article') ||
                        document.querySelector('main') ||
                        document.querySelector('.story-body') ||
                        document.querySelector('.gs-c-article-body') ||
                        document.querySelector('.article-body') ||
                        document.querySelector('.content');

        // --- hero image: only from article or its direct parent ---
        var imgSrc = '';
        if (articleEl) {
          var hero = articleEl.querySelector('figure img, img');
          if (!hero && articleEl.parentElement) {
            // fall back to a figure/img near the article, but not whole document
            hero = articleEl.parentElement.querySelector('figure img, img');
          }
          if (hero) {
            imgSrc = hero.getAttribute('src') || hero.getAttribute('data-src') || '';
          }
        }
        // if articleEl is null, we leave imgSrc='' (no hero, to avoid logos)

        var timeEl = document.querySelector('time,[data-testid="timestamp"]');
        var timeTxt = txt(timeEl);

        var idx = 0;
        var htmlLines = [];
        var plainLines = [];
        var seenImg = {};

        function pushLine(t, tag, cls){
          if(!t) return;
          var c='flutter-line'+(cls?(' '+cls):'');
          htmlLines.push('<'+tag+' class="'+c+'" id="flutter-line-'+idx+'">'+esc(t)+'</'+tag+'>');
          plainLines.push(t);
          idx++;
        }

        // inline images only from article content (skip hero + duplicates)
        function pushImg(src){
          if(!src) return;

          if (src === imgSrc) return;      // don't duplicate hero
          if (seenImg[src]) return;
          seenImg[src] = true;

          htmlLines.push(
            '<div class="flutter-line is-image" data-type="image" id="flutter-line-'+idx+'">' +
              '<img src="'+src+'" class="inline-image" />' +
            '</div>'
          );
          plainLines.push('__IMG__|' + src);
          idx++;
        }

        pushLine(title,'h1','is-title');
        if (timeTxt) pushLine(timeTxt,'div','is-time');

        function collectFrom(root){
          var nodes = root.querySelectorAll('p,h2,h3,ul,ol,figure,img');
          nodes.forEach(function(n){
            var tag = n.tagName;

            if (tag === 'IMG' || tag === 'FIGURE') {
              var im = n.querySelector('img') || n;
              if (im) {
                var src = im.getAttribute('src') || im.getAttribute('data-src') || '';
                if (src) pushImg(src);
              }
              return;
            }

            var c = (n.className||'').toString();
            if (isJunk(c)) return;
            if (n.querySelector && n.querySelector('button,svg,path')) return;

            var t = txt(n); if(!t) return;
            var low = t.toLowerCase();
            if (low === 'share' || low === 'save') return;

            if (tag==='P') pushLine(t,'p','');
            else if (tag==='H2') pushLine(t,'h2','is-subhead');
            else if (tag==='H3') pushLine(t,'h3','is-subhead');
            else if (tag==='UL' || tag==='OL') pushLine(t,'p','');
          });
        }

        if (articleEl) {
          collectFrom(articleEl);
        } else {
          // fallback: only text paragraphs, no images (to avoid picking wrong ones)
          document.querySelectorAll('p').forEach(function(n){
            var t = txt(n); if(t) pushLine(t,'p','');
          });
        }

        // expose to Flutter
        window.flutterSetLine = function(i, t){
          var el = document.getElementById('flutter-line-'+i); if(el) el.textContent = t;
        };
        window.flutterHighlightLine = function(i){
          document.querySelectorAll('.flutter-line').forEach(function(e){e.classList.remove('highlight');});
          var tgt = document.getElementById('flutter-line-'+i);
          if (tgt){ tgt.classList.add('highlight'); tgt.scrollIntoView({behavior:'smooth', block:'center'}); }
        };

        if (window.flutterArticle && window.flutterArticle.postMessage) {
          window.flutterArticle.postMessage(plainLines.join('\n'));
        }

        var html = `
          <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
              body{margin:0;background:#fff;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Oxygen,Ubuntu,Cantarell,"Open Sans","Helvetica Neue",sans-serif;}
              .wrap{max-width:760px;margin:0 auto;padding:16px;}
              img.hero{width:100%;height:auto;border-radius:8px;margin-bottom:16px;object-fit:cover;}
              img.inline-image{max-width:100%;height:auto;border-radius:6px;margin:10px 0;}
              h1.flutter-line{font-size:1.7rem;line-height:1.2;margin:0 0 .5rem 0;}
              .is-time.flutter-line{color:#666;font-size:.85rem;margin:0 0 1.2rem 0;}
              p.flutter-line{font-size:1.02rem;line-height:1.7;margin:0 0 1rem 0;}
              h2.flutter-line,h3.flutter-line{margin:1.5rem 0 .6rem 0;}
              .flutter-line{border-left:4px solid transparent;padding-left:8px;transition:background .25s,border-left .25s;}
              .flutter-line.highlight{background:#fff3cd;border-left-color:#f1b500;}
            </style>
          </head>
          <body>
            <div class="wrap">
              ${imgSrc ? `<img src="${imgSrc}" class="hero" />` : ``}
              ${htmlLines.join('')}
            </div>
          </body>
          </html>`;
        document.open(); document.write(html); document.close();
      })();
    """;

    await _controller.runJavaScript(js);
    await _highlightLine(0);
  }

  Future<void> _highlightLine(int index) async {
    await _controller.runJavaScript(
      "if(window.flutterHighlightLine) window.flutterHighlightLine($index);",
    );
  }

  Future<void> _setWebLine(int index, String text) async {
    final safe = text
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', ' ');
    await _controller.runJavaScript(
      "if(window.flutterSetLine) window.flutterSetLine($index,'$safe');",
    );
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
      final code =
          await id.identifyLanguage(sample.isNotEmpty ? sample : 'Hello');
      TranslateLanguage lang = TranslateLanguage.english;
      if (code.startsWith('ms'))
        lang = TranslateLanguage.malay;
      else if (code.startsWith('zh'))
        lang = TranslateLanguage.chinese;
      else if (code.startsWith('ja'))
        lang = TranslateLanguage.japanese;
      else if (code.startsWith('ko'))
        lang = TranslateLanguage.korean;
      else if (code.startsWith('id'))
        lang = TranslateLanguage.indonesian;
      else if (code.startsWith('th'))
        lang = TranslateLanguage.thai;
      else if (code.startsWith('vi'))
        lang = TranslateLanguage.vietnamese;
      else if (code.startsWith('ar'))
        lang = TranslateLanguage.arabic;
      else if (code.startsWith('fr'))
        lang = TranslateLanguage.french;
      else if (code.startsWith('es'))
        lang = TranslateLanguage.spanish;
      else if (code.startsWith('de'))
        lang = TranslateLanguage.german;
      else if (code.startsWith('pt'))
        lang = TranslateLanguage.portuguese;
      else if (code.startsWith('it'))
        lang = TranslateLanguage.italian;
      else if (code.startsWith('ru'))
        lang = TranslateLanguage.russian;
      else if (code.startsWith('hi')) lang = TranslateLanguage.hindi;

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

        // restore DOM but DON'T touch image lines
        for (int i = 0; i < _lines.length; i++) {
          final line = _lines[i];
          if (line.startsWith('__IMG__|')) {
            // leave HTML <img> as is
            continue;
          }
          unawaited(_setWebLine(i, line));
        }

        await _applyTtsLocale('en');
        await _highlightLine(0);
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

    final translator =
        OnDeviceTranslator(sourceLanguage: src, targetLanguage: target);

    _originalLinesCache ??= List<String>.from(_lines);
    final translated = <String>[];

    for (int i = 0; i < _lines.length; i++) {
      final line = _lines[i];

      // image line → keep it, don’t translate, don’t overwrite DOM
      if (line.startsWith('__IMG__|')) {
        translated.add(line);
        continue;
      }

      final t = await translator.translateText(line);
      translated.add(t);
      await _setWebLine(i, t);
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
    await _highlightLine(0);
  }

  // --------------- TTS playback ---------------

  Future<void> _speakCurrentLine() async {
    if (_lines.isEmpty) return;
    if (_currentLine < 0 || _currentLine >= _lines.length) return;

    final settings = context.read<SettingsProvider>();
    final targetCode = _isTranslatedView ? settings.translateLangCode : 'off';

    String text = _lines[_currentLine].trim();

    // image line → skip
    if (text.startsWith('__IMG__|')) {
      await _speakNextLine(auto: true);
      return;
    }

    if (text.isEmpty) {
      await _speakNextLine(auto: true);
      return;
    }

    if (targetCode != 'off') {
      text = _normalizeForTts(text, targetCode);
    }

    setState(() => _isPlaying = true);
    await _highlightLine(_currentLine);
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _speakNextLine({bool auto = false}) async {
    if (_lines.isEmpty) return;

    int i = _currentLine + 1;
    while (i < _lines.length && _lines[i].trim().startsWith('__IMG__|')) {
      i++;
    }

    if (i >= _lines.length) {
      setState(() => _isPlaying = false);
      return;
    }

    setState(() => _currentLine = i);
    await _speakCurrentLine();
  }

  Future<void> _speakPrevLine() async {
    if (_lines.isEmpty) return;

    int i = _currentLine - 1;
    while (i >= 0 && _lines[i].trim().startsWith('__IMG__|')) {
      i--;
    }

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

    int i = _lines.length - 1;
    while (i >= 0 && _lines[i].trim().startsWith('__IMG__|')) {
      i--;
    }
    if (i < 0) return;

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
      await _injectReader();
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
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await _stopSpeaking();
            if (mounted) Navigator.of(context).maybePop();
          },
        ),
        actions: [
          if (_readerOn)
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
              // disable while page is loading OR translating
              onPressed: (_isLoading || _isTranslating)
                  ? null
                  : _toggleTranslateToSetting,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
