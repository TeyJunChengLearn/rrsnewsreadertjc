import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

/// Result of readability extraction: main article text + optional hero image.
class ArticleReadabilityResult {
  final String? mainText;
  final String? imageUrl;
  final String? pageTitle;
  const ArticleReadabilityResult(
      {this.mainText, this.imageUrl, this.pageTitle});

  bool get hasContent =>
      (mainText != null && mainText!.isNotEmpty) ||
      (imageUrl != null && imageUrl!.isNotEmpty);
}

/// "Readability4JExtended-style" extractor.
///
/// - Fetches HTML for a URL
/// - Strips obvious noise (header, footer, nav, etc.)
/// - Finds a likely article container:
///     1. semantic tags (article/main/role=main/etc.)
///     2. best-scoring <div>/<section> by text length
/// - Extracts text from <p> and <li>
/// - Picks a reasonable hero image
///
/// IMPORTANT:
/// If no container has enough real article text, this returns `null`
/// instead of falling back to the entire <body>. That way TTS will only
/// read "article-like" content, never the whole noisy page.
class Readability4JExtended {
  final http.Client _client;
  final Future<String?> Function(Uri url)? cookieHeaderBuilder;
  Readability4JExtended({http.Client? client, this.cookieHeaderBuilder})
      : _client = client ?? http.Client();

  Future<ArticleReadabilityResult?> extractMainContent(String url) async {
    try {
       final headers = await _buildRequestHeaders(url);
      final resp = await _client.get(Uri.parse(url), headers: headers);

      if (resp.statusCode != 200) return null;

      final doc = html_parser.parse(resp.body);

      _stripNoise(doc);

      final title = _extractPageTitle(doc);
      final articleRoot = _findArticleRoot(doc);

      String? normalized;
      if (articleRoot != null) {
        final text = _extractMainText(articleRoot);
        normalized = _normalizeWhitespace(text);
      }

      normalized ??= _fallbackBodyText(doc);

      if (normalized == null || normalized.isEmpty) {
        return null;
      }

      final heroImage = _extractLeadImage(doc, articleRoot, url);


      final result = ArticleReadabilityResult(
        mainText: normalized,
        imageUrl: heroImage,
        pageTitle: title,
      );

      return result.hasContent ? result : null;
    } catch (_) {
      return null;
    }
  }
  Future<Map<String, String>> _buildRequestHeaders(String url) async {
    final headers = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml',
    };

    if (cookieHeaderBuilder != null) {
      final cookie = await cookieHeaderBuilder!(Uri.parse(url));
      if (cookie != null && cookie.trim().isNotEmpty) {
        headers['Cookie'] = cookie.trim();
      }
    }

    return headers;
  }
  // ---------------------------------------------------------------------------
  // DOM cleaning
  // ---------------------------------------------------------------------------

  void _stripNoise(dom.Document doc) {
    // Remove hard-noise tags.
    final garbage = doc.querySelectorAll(
      'script,style,noscript,form,iframe',
    );
    for (final node in garbage) {
      node.remove();
    }

    // Remove elements that are very likely to be navigation/ads/etc.
    final candidates = doc.querySelectorAll('*').toList();
    for (final el in candidates) {
      final tag = el.localName ?? '';
      if (tag == 'header' ||
          tag == 'footer' ||
          tag == 'nav' ||
          tag == 'aside') {
        el.remove();
        continue;
      }

      final id = (el.id ?? '').toLowerCase();
      final classAttr = (el.className ?? '').toLowerCase();
      final marker = '$id $classAttr';

      const badHints = <String>[
        'nav',
        'menu',
        'footer',
        'header',
        'sidebar',
        'subscribe',
        'signup',
        'comment',
        'comments',
        'share',
        'sharing',
        'related',
        'recommend',
        'promo',
        'advert',
        'ad-',
        'banner',
        'cookie',
        'consent',
        'modal',
        'popup',
      ];

      if (badHints.any((h) => marker.contains(h))) {
        el.remove();
      }
    }
  }

  String? _extractPageTitle(dom.Document doc) {
    // Prefer Open Graph/Twitter title if available
    final og =
        doc.querySelector('meta[property="og:title"]')?.attributes['content'];
    if (og != null && og.trim().isNotEmpty) return og.trim();

    final twitter =
        doc.querySelector('meta[name="twitter:title"]')?.attributes['content'];
    if (twitter != null && twitter.trim().isNotEmpty) return twitter.trim();

    final plainTitle = doc.querySelector('title')?.text;
    if (plainTitle != null && plainTitle.trim().isNotEmpty)
      return plainTitle.trim();

    return null;
  }
  // ---------------------------------------------------------------------------
  // Article container selection
  // ---------------------------------------------------------------------------

  static const int _minArticleScore = 400;

  dom.Element? _findArticleRoot(dom.Document doc) {
    // 1) Try semantic / common content wrappers with scoring
    final prioritySelectors = <String>[
      'article',
      'main',
      '[role="main"]',
      '#content',
      '.content',
      '.post',
      '.article-body',
      '.story-body',
      '.entry-content',
    ];

    dom.Element? best;
    var bestScore = 0;

    for (final selector in prioritySelectors) {
      final els = doc.querySelectorAll(selector);
      for (final el in els) {
        final score = _textScore(el);
        if (score > bestScore) {
          bestScore = score;
          best = el;
        }
      }
    }

    if (best != null && bestScore >= _minArticleScore) {
      return best;
    }

    // 2) Fallback: search all div/section for the "text richest" one.
    best = null;
    bestScore = 0;

    final allBlocks = <dom.Element>[];
    allBlocks.addAll(doc.querySelectorAll('div'));
    allBlocks.addAll(doc.querySelectorAll('section'));

    for (final el in allBlocks) {
      final score = _textScore(el);
      if (score > bestScore) {
        bestScore = score;
        best = el;
      }
    }

    if (best != null && bestScore >= _minArticleScore) {
      return best;
    }

    // Nothing reaches our minimum article score.
    return null;
  }

  int _textScore(dom.Element el) {
    // Score is total length of all <p> and <li> text under this element.
    final blocks = el.querySelectorAll('p, li');
    var total = 0;
    for (final b in blocks) {
      final t = b.text.trim();
      if (t.isEmpty) continue;
      total += t.length;
    }
    return total;
  }

  // ---------------------------------------------------------------------------
  // Text extraction
  // ---------------------------------------------------------------------------

  String _extractMainText(dom.Element root) {
    final buffer = StringBuffer();

    final blocks = root.querySelectorAll('p, li');
    for (final block in blocks) {
      final text = block.text.trim();
      if (text.isEmpty) continue;
      buffer.writeln(text);
      buffer.writeln();
    }

    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Lead image selection
  // ---------------------------------------------------------------------------

  String? _extractLeadImage(
    dom.Document doc,
    dom.Element? articleRoot,
    String baseUrl,
  ) {
    String? resolve(String? src) {
      if (src == null || src.trim().isEmpty) return null;
      final srcUri = Uri.tryParse(src.trim());
      if (srcUri == null) return null;
      if (srcUri.hasScheme) return srcUri.toString();

      final base = Uri.tryParse(baseUrl);
      if (base == null) return null;
      return base.resolveUri(srcUri).toString();
    }

    bool looksLikeJunk(String url) {
      final lower = url.toLowerCase();
      if (lower.startsWith('data:')) return true;
      if (lower.endsWith('.svg') || lower.endsWith('.gif')) return true;
      const junkHints = <String>[
        'logo',
        'icon',
        'avatar',
        'sprite',
        'pixel',
        'spacer',
        'placeholder',
        'badge',
        'ads',
        'ad-',
        'banner',
        'tracking',
      ];
      return junkHints.any((h) => lower.contains(h));
    }

    bool hasAcceptableSize(dom.Element img) {
      int? parseDim(String? raw) => int.tryParse(raw ?? '');
      final w = parseDim(img.attributes['width']);
      final h = parseDim(img.attributes['height']);

      const minSize = 200;
      if (w == null && h == null) return true;
      if (w != null && w < minSize) return false;
      if (h != null && h < minSize) return false;
      return true;
    }

    String? pickCandidate(Iterable<dom.Element> candidates) {
      for (final el in candidates) {
        final resolved = resolve(el.attributes['src']);
        if (resolved == null) continue;
        if (looksLikeJunk(resolved)) continue;
        if (!hasAcceptableSize(el)) continue;
        return resolved;
      }
      return null;
    }

// 1) <figure> images inside the article
    // These are the most likely to be the main content images.
     if (articleRoot != null) {
      final figureImgs = articleRoot.querySelectorAll('figure img');
      final resolvedFigure = pickCandidate(figureImgs);
      if (resolvedFigure != null) return resolvedFigure;

      // 2) Any inline image inside the article
      final inlineImgs = articleRoot.querySelectorAll('img');
      final resolvedInline = pickCandidate(inlineImgs);
      if (resolvedInline != null) return resolvedInline;
    }

    // 3) Metadata-defined hero (Open Graph / Twitter)
    final ogImage =
        doc.querySelector('meta[property="og:image"]')?.attributes['content'];
    final resolvedOg = resolve(ogImage);
    if (resolvedOg != null && !looksLikeJunk(resolvedOg)) {
      return resolvedOg;
    }
    final twitterImage =
        doc.querySelector('meta[name="twitter:image"]')?.attributes['content'];
    final resolvedTwitter = resolve(twitterImage);
    if (resolvedTwitter != null && !looksLikeJunk(resolvedTwitter)) {
      return resolvedTwitter;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Whitespace normalization
  // ---------------------------------------------------------------------------

  String _normalizeWhitespace(String raw) {
    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.join('\n\n');
  }

  String? _fallbackBodyText(dom.Document doc) {
    final bodyText = doc.body?.text ?? '';
    final normalized = _normalizeWhitespace(bodyText);
    // Avoid returning extremely short or obviously empty content.
    return normalized.length < 120 ? null : normalized;
  }
}
