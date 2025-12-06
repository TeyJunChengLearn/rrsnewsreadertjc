import 'dart:convert';
import 'dart:io';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'android_webview_extractor.dart';

/// Result of article extraction
class ArticleReadabilityResult {
  final String? mainText;
  final String? imageUrl;
  final String? pageTitle;
  final bool? isPaywalled;
  final String? source;
  final String? author;
  final DateTime? publishedDate;

  const ArticleReadabilityResult({
    this.mainText,
    this.imageUrl,
    this.pageTitle,
    this.isPaywalled,
    this.source,
    this.author,
    this.publishedDate,
  });

  bool get hasContent =>
      (mainText != null && mainText!.isNotEmpty) ||
      (imageUrl != null && imageUrl!.isNotEmpty);

  bool get hasFullContent {
    if (!hasContent) return false;
    final text = mainText?.trim() ?? '';
    return text.length >= 150;
  }

  @override
  String toString() {
    return 'ArticleReadabilityResult{'
        'title: $pageTitle, '
        'textLength: ${mainText?.length ?? 0}, '
        'source: $source}';
  }
}

/// Configuration for readability service
class ReadabilityConfig {
  final Duration requestDelay;
  final String userAgent;
  final bool attemptRssFallback;

  ReadabilityConfig({
    Duration? requestDelay,
    String? userAgent,
    bool? attemptRssFallback,
  })  : requestDelay = requestDelay ?? const Duration(milliseconds: 500),
        userAgent = userAgent ??
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        attemptRssFallback = attemptRssFallback ?? true;
}

/// RSS content extraction
class _RssItemContent {
  final String text;
  final String? imageUrl;
  final String? title;
  final String? author;
  final DateTime? publishedDate;

  const _RssItemContent({
    required this.text,
    this.imageUrl,
    this.title,
    this.author,
    this.publishedDate,
  });

  bool get hasContent => text.trim().isNotEmpty;
}

/// RSS feed parser
class RssFeedParser {
  final http.Client _client;

  RssFeedParser({http.Client? client}) : _client = client ?? http.Client();

  Future<_RssItemContent?> extractFromRss(
    String rssUrl,
    String targetUrl, {
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _client.get(
        Uri.parse(rssUrl),
        headers: headers ?? {},
      );

      if (response.statusCode != 200) return null;

      final xmlDoc = XmlDocument.parse(response.body);
      final normalizedTarget = _normalizeUrl(targetUrl);

      for (final item in xmlDoc.findAllElements('item')) {
        final link = _readText(item, 'link');
        final guid = _readText(item, 'guid');

        if (!_matchesTarget(link, normalizedTarget) &&
            !_matchesTarget(guid, normalizedTarget)) {
          continue;
        }

        final content = _readText(item, 'encoded', namespace: 'content') ??
            _readText(item, 'content') ??
            _readText(item, 'description');

        final cleanedText = _cleanRssContent(content);
        if (cleanedText == null || cleanedText.trim().isEmpty) continue;

        final imageUrl = _extractImageUrl(item) ??
            _extractImageFromHtml(content);

        final author = _readText(item, 'creator', namespace: 'dc') ??
            _readText(item, 'author');

        final pubDate = _parseDate(_readText(item, 'pubDate')) ??
            _parseDate(_readText(item, 'published'));

        final title = _readText(item, 'title');

        return _RssItemContent(
          text: cleanedText,
          imageUrl: imageUrl,
          title: title,
          author: author,
          publishedDate: pubDate,
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String? _readText(XmlElement element, String localName, {String? namespace}) {
    final matches = element.findElements(localName, namespace: namespace);
    if (matches.isEmpty) return null;
    return matches.first.text.trim();
  }

  bool _matchesTarget(String? candidate, String normalizedTarget) {
    if (candidate == null || candidate.isEmpty) return false;
    final normalized = _normalizeUrl(candidate);
    return normalized == normalizedTarget ||
        normalized.contains(normalizedTarget) ||
        normalizedTarget.contains(normalized);
  }

  String _normalizeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final filteredParams = Map<String, String>.fromEntries(
        uri.queryParameters.entries.where(
          (entry) =>
              !entry.key.toLowerCase().startsWith('utm_') &&
              !entry.key.toLowerCase().startsWith('fbclid') &&
              entry.key.toLowerCase() != 'ref',
        ),
      );

      final cleanedUri = uri.replace(
        queryParameters: filteredParams.isEmpty ? null : filteredParams,
        path: uri.path.endsWith('/') && uri.path.length > 1
            ? uri.path.substring(0, uri.path.length - 1)
            : uri.path,
      );

      return cleanedUri.toString().toLowerCase();
    } catch (_) {
      return url.toLowerCase();
    }
  }

  String? _cleanRssContent(String? content) {
    if (content == null) return null;

    final stripped = content.replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '');
    final fragment = html_parser.parseFragment(stripped);

    final paragraphs = fragment.querySelectorAll('p, li, blockquote');
    if (paragraphs.isEmpty) {
      return _normalizeWhitespace(fragment.text ?? '');
    }

    final buffer = StringBuffer();
    for (final element in paragraphs) {
      final text = element.text.trim();
      if (text.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.write('\n\n');
        buffer.write(text);
      }
    }

    return _normalizeWhitespace(buffer.toString());
  }

  String? _extractImageUrl(XmlElement item) {
    final mediaContent = item.findElements('content', namespace: 'media');
    for (final content in mediaContent) {
      final url = content.getAttribute('url');
      if (url != null && url.isNotEmpty) return url;
    }

    final mediaThumbnail = item.findElements('thumbnail', namespace: 'media');
    for (final thumbnail in mediaThumbnail) {
      final url = thumbnail.getAttribute('url');
      if (url != null && url.isNotEmpty) return url;
    }

    final enclosures = item.findElements('enclosure');
    for (final enclosure in enclosures) {
      final type = enclosure.getAttribute('type')?.toLowerCase() ?? '';
      final url = enclosure.getAttribute('url');
      if (url != null && type.startsWith('image/')) {
        return url;
      }
    }

    return null;
  }

  String? _extractImageFromHtml(String? html) {
    if (html == null || html.isEmpty) return null;
    final fragment = html_parser.parseFragment(html);

    final img = fragment.querySelector('img[src]');
    if (img != null) {
      return img.attributes['src'];
    }

    return null;
  }

  DateTime? _parseDate(String? date) {
    if (date == null) return null;
    try {
      return DateTime.parse(date);
    } catch (_) {
      try {
        return HttpDate.parse(date);
      } catch (_) {
        return null;
      }
    }
  }

  String _normalizeWhitespace(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

/// Main readability service
class Readability4JExtended {
  final http.Client _client;
  final ReadabilityConfig _config;
  final RssFeedParser _rssParser;
  final Map<String, DateTime> _lastRequestTime = {};

  Readability4JExtended({
    http.Client? client,
    ReadabilityConfig? config,
    AndroidWebViewExtractor? webViewExtractor,
    Future<String?> Function(String url)? cookieHeaderBuilder,
  })  : _client = client ?? http.Client(),
        _config = config ?? ReadabilityConfig(),
        _rssParser = RssFeedParser(client: client);

  /// Main extraction method
  Future<ArticleReadabilityResult?> extractMainContent(String url) async {
    try {
      await _respectRateLimit(url);

      // Try HTML extraction first
      final htmlResult = await _extractFromHtml(url);
      if (htmlResult != null && htmlResult.hasFullContent) {
        return htmlResult;
      }

      // Fallback to RSS if configured
      if (_config.attemptRssFallback) {
        final rssResult = await _extractFromRss(url);
        if (rssResult != null && rssResult.hasContent) {
          // Return RSS if better than HTML
          if (htmlResult == null ||
              (rssResult.mainText?.length ?? 0) >
                  (htmlResult.mainText?.length ?? 0)) {
            return rssResult;
          }
        }
      }

      return htmlResult;
    } catch (e) {
      print('Error extracting content from $url: $e');
      return null;
    }
  }

  /// Extract from HTML
  Future<ArticleReadabilityResult?> _extractFromHtml(String url) async {
    try {
      final headers = _buildRequestHeaders(url);
      final response = await _client.get(Uri.parse(url), headers: headers);

      if (response.statusCode != 200) return null;

      final doc = html_parser.parse(response.body);
      final pageUri = Uri.parse(url);

      // Extract metadata
      final title = _extractTitle(doc);
      final author = _extractAuthor(doc);
      final publishedDate = _extractPublishedDate(doc);
      final heroImage = _extractHeroImage(doc, pageUri);

      // Clean document
      _cleanDocument(doc);

      // Try JSON-LD first
      final jsonLdContent = _extractJsonLdContent(doc);
      if (jsonLdContent != null && jsonLdContent.length > 200) {
        return ArticleReadabilityResult(
          mainText: jsonLdContent,
          imageUrl: heroImage,
          pageTitle: title,
          source: 'JSON-LD',
          author: author,
          publishedDate: publishedDate,
        );
      }

      // Find article root and extract content
      final articleRoot = _findArticleRoot(doc);
      if (articleRoot == null) return null;

      final content = _extractMainText(articleRoot);
      final normalizedContent = _normalizeWhitespace(content);

      if (normalizedContent.isEmpty) return null;

      return ArticleReadabilityResult(
        mainText: normalizedContent,
        imageUrl: heroImage,
        pageTitle: title,
        source: 'HTML',
        author: author,
        publishedDate: publishedDate,
      );
    } catch (_) {
      return null;
    }
  }

  /// Extract from RSS feed
  Future<ArticleReadabilityResult?> _extractFromRss(String url) async {
    final rssUrls = _generateRssUrls(url);

    for (final rssUrl in rssUrls) {
      try {
        final headers = _buildRequestHeaders(rssUrl);
        final rssContent = await _rssParser.extractFromRss(
          rssUrl,
          url,
          headers: headers,
        );

        if (rssContent != null && rssContent.hasContent) {
          return ArticleReadabilityResult(
            mainText: rssContent.text,
            imageUrl: rssContent.imageUrl,
            pageTitle: rssContent.title,
            source: 'RSS',
            author: rssContent.author,
            publishedDate: rssContent.publishedDate,
          );
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  /// Generate RSS URLs to try
  List<String> _generateRssUrls(String url) {
    final uri = Uri.parse(url);
    final baseUrl = '${uri.scheme}://${uri.host}';
    final path = uri.path;

    final rssUrls = <String>[
      '$baseUrl/feed',
      '$baseUrl/rss',
      '$baseUrl/feed.xml',
      '$baseUrl/rss.xml',
      '$baseUrl/atom.xml',
      '$baseUrl/?feed=rss',
      '$baseUrl/index.xml',
    ];

    // Add section-based feeds
    if (path.contains('/')) {
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        final section = segments.first;
        rssUrls.addAll([
          '$baseUrl/$section/feed',
          '$baseUrl/$section/rss',
        ]);
      }
    }

    return rssUrls;
  }

  /// Build request headers
  Map<String, String> _buildRequestHeaders(String url) {
    return {
      'User-Agent': _config.userAgent,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Accept-Encoding': 'gzip, deflate',
      'Connection': 'keep-alive',
    };
  }

  /// Respect rate limiting
  Future<void> _respectRateLimit(String url) async {
    final domain = Uri.parse(url).host;
    final lastRequest = _lastRequestTime[domain];

    if (lastRequest != null) {
      final elapsed = DateTime.now().difference(lastRequest);
      if (elapsed < _config.requestDelay) {
        await Future.delayed(_config.requestDelay - elapsed);
      }
    }

    _lastRequestTime[domain] = DateTime.now();
  }

  /// Extract title
  String? _extractTitle(dom.Document doc) {
    final ogTitle =
        doc.querySelector('meta[property="og:title"]')?.attributes['content'];
    if (ogTitle != null && ogTitle.isNotEmpty) return ogTitle;

    final twitterTitle =
        doc.querySelector('meta[name="twitter:title"]')?.attributes['content'];
    if (twitterTitle != null && twitterTitle.isNotEmpty) return twitterTitle;

    final plainTitle = doc.querySelector('title')?.text?.trim();
    if (plainTitle != null && plainTitle.isNotEmpty) return plainTitle;

    final h1 = doc.querySelector('h1')?.text?.trim();
    if (h1 != null && h1.isNotEmpty) return h1;

    return null;
  }

  /// Extract author
  String? _extractAuthor(dom.Document doc) {
    final ogAuthor = doc
            .querySelector('meta[property="article:author"]')
            ?.attributes['content'] ??
        doc.querySelector('meta[name="author"]')?.attributes['content'];
    if (ogAuthor != null && ogAuthor.isNotEmpty) return ogAuthor;

    final selectors = [
      '.author',
      '.byline',
      '[rel="author"]',
      '.article-author',
    ];

    for (final selector in selectors) {
      final authorText = doc.querySelector(selector)?.text?.trim();
      if (authorText != null && authorText.isNotEmpty) return authorText;
    }

    return null;
  }

  /// Extract published date
  DateTime? _extractPublishedDate(dom.Document doc) {
    try {
      final ogDate = doc
          .querySelector('meta[property="article:published_time"]')
          ?.attributes['content'];
      if (ogDate != null && ogDate.isNotEmpty) {
        return DateTime.tryParse(ogDate);
      }

      final dateSelectors = ['time[datetime]', '.date', '.published'];

      for (final selector in dateSelectors) {
        final dateElement = doc.querySelector(selector);
        if (dateElement != null) {
          final dateTime = dateElement.attributes['datetime'];
          if (dateTime != null && dateTime.isNotEmpty) {
            return DateTime.tryParse(dateTime);
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// Clean document
  void _cleanDocument(dom.Document doc) {
    // Remove noise elements
    final garbage = doc.querySelectorAll(
      'style,script,noscript,form,iframe,video,audio,svg,canvas,'
      'header,footer,nav,aside,.sidebar,.advertisement,.ad,'
      '.comments,.social-share,.related-posts',
    );
    for (final node in garbage) {
      node.remove();
    }
  }

  /// Extract JSON-LD content
  String? _extractJsonLdContent(dom.Document doc) {
    try {
      final scripts =
          doc.querySelectorAll('script[type="application/ld+json"]');

      for (final script in scripts) {
        final content = script.text?.trim();
        if (content == null || content.isEmpty) continue;

        try {
          final json = jsonDecode(content);
          final body = _extractArticleBody(json);
          if (body != null && body.trim().isNotEmpty) {
            return body.trim();
          }
        } catch (_) {
          continue;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Extract article body from JSON-LD
  String? _extractArticleBody(dynamic json) {
    if (json is Map<String, dynamic>) {
      // Direct articleBody
      if (json['articleBody'] != null) {
        return json['articleBody'].toString();
      }

      // Check @graph
      if (json['@graph'] is List) {
        for (final item in json['@graph']) {
          if (item is Map<String, dynamic>) {
            final type = item['@type'];
            if (type != null &&
                (type.toString().toLowerCase().contains('article') ||
                    type.toString().toLowerCase().contains('newsarticle'))) {
              if (item['articleBody'] != null) {
                return item['articleBody'].toString();
              }
            }
          }
        }
      }

      // Check mainEntity
      if (json['mainEntity'] is Map<String, dynamic>) {
        return _extractArticleBody(json['mainEntity']);
      }
    } else if (json is List) {
      for (final item in json) {
        final body = _extractArticleBody(item);
        if (body != null) return body;
      }
    }

    return null;
  }

  /// Find article root element
  dom.Element? _findArticleRoot(dom.Document doc) {
    // Priority selectors for common article containers
    final selectors = [
      'article',
      '[role="main"]',
      'main',
      '.article-body',
      '.story-body',
      '.post-content',
      '.entry-content',
      '.article-content',
      '#content',
      '.content',
    ];

    dom.Element? best;
    var bestScore = 0;

    for (final selector in selectors) {
      final elements = doc.querySelectorAll(selector);
      for (final el in elements) {
        final score = _calculateElementScore(el);
        if (score > bestScore) {
          bestScore = score;
          best = el;
        }
      }
    }

    if (best != null && bestScore >= 50) {
      return best;
    }

    // Fallback: find highest scoring div or section
    final blocks = doc.querySelectorAll('div, section, article');
    for (final el in blocks) {
      final score = _calculateElementScore(el);
      if (score > bestScore) {
        bestScore = score;
        best = el;
      }
    }

    return best;
  }

  /// Calculate element score
  int _calculateElementScore(dom.Element el) {
    final paragraphs = el.querySelectorAll('p');
    var score = 0.0;

    for (final p in paragraphs) {
      final text = p.text?.trim() ?? '';
      if (text.length > 50) {
        score += text.length * 1.5;
      }
    }

    // Penalize high link density
    final linkCount = el.querySelectorAll('a').length;
    final textLength = el.text?.length ?? 1;
    final linkDensity = linkCount / (textLength / 100);
    if (linkDensity > 2.0) {
      score *= 0.5;
    }

    return score.toInt();
  }

  /// Extract main text
  String _extractMainText(dom.Element root) {
    final buffer = StringBuffer();
    final seenTexts = <String>{};

    final blocks = root.querySelectorAll('p, h1, h2, h3, h4, h5, h6, li');

    for (final block in blocks) {
      final text = block.text?.trim() ?? '';
      if (text.isEmpty || text.length < 20) continue;
      if (seenTexts.contains(text)) continue;

      seenTexts.add(text);

      if (block.localName?.startsWith('h') ?? false) {
        buffer.writeln('\n$text\n');
      } else {
        buffer.writeln(text);
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// Extract hero image
  String? _extractHeroImage(dom.Document doc, Uri pageUri) {
    final ogImage =
        doc.querySelector('meta[property="og:image"]')?.attributes['content'];
    if (ogImage != null && ogImage.trim().isNotEmpty) {
      return _resolveImageUrl(ogImage.trim(), pageUri);
    }

    final twitterImage =
        doc.querySelector('meta[name="twitter:image"]')?.attributes['content'];
    if (twitterImage != null && twitterImage.trim().isNotEmpty) {
      return _resolveImageUrl(twitterImage.trim(), pageUri);
    }

    // Find largest image
    final images = doc.querySelectorAll('img[src]');
    String? bestImage;
    var bestSize = 0;

    for (final img in images) {
      final src = img.attributes['src'];
      if (src == null || src.contains('logo') || src.contains('icon')) {
        continue;
      }

      final width = int.tryParse(img.attributes['width'] ?? '') ?? 0;
      final height = int.tryParse(img.attributes['height'] ?? '') ?? 0;
      final size = width * height;

      if (size > bestSize) {
        bestSize = size;
        bestImage = src;
      }
    }

    return bestImage != null ? _resolveImageUrl(bestImage, pageUri) : null;
  }

  /// Resolve image URL
  String? _resolveImageUrl(String? url, Uri baseUri) {
    if (url == null || url.trim().isEmpty) return null;

    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;

    if (uri.hasScheme) return uri.toString();

    return baseUri.resolveUri(uri).toString();
  }

  /// Normalize whitespace
  String _normalizeWhitespace(String raw) {
    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.join('\n\n');
  }

  /// Batch extract multiple articles
  Future<List<ArticleReadabilityResult?>> extractArticles(
    List<String> urls,
  ) async {
    final results = <ArticleReadabilityResult?>[];

    for (final url in urls) {
      try {
        final result = await extractMainContent(url);
        results.add(result);
      } catch (_) {
        results.add(null);
      }

      if (url != urls.last) {
        await Future.delayed(_config.requestDelay);
      }
    }

    return results;
  }

  /// Extract from existing HTML
  Future<ArticleReadabilityResult?> extractFromHtml(
    String url,
    String html, {
    String strategyName = 'DOM',
  }) async {
    try {
      final doc = html_parser.parse(html);
      final pageUri = Uri.parse(url);

      final title = _extractTitle(doc);
      final author = _extractAuthor(doc);
      final publishedDate = _extractPublishedDate(doc);
      final heroImage = _extractHeroImage(doc, pageUri);

      _cleanDocument(doc);

      final jsonLdContent = _extractJsonLdContent(doc);
      if (jsonLdContent != null && jsonLdContent.length > 200) {
        return ArticleReadabilityResult(
          mainText: jsonLdContent,
          imageUrl: heroImage,
          pageTitle: title,
          source: 'JSON-LD',
          author: author,
          publishedDate: publishedDate,
        );
      }

      final articleRoot = _findArticleRoot(doc);
      if (articleRoot == null) return null;

      final content = _extractMainText(articleRoot);
      final normalizedContent = _normalizeWhitespace(content);

      if (normalizedContent.isEmpty) return null;

      return ArticleReadabilityResult(
        mainText: normalizedContent,
        imageUrl: heroImage,
        pageTitle: title,
        source: strategyName,
        author: author,
        publishedDate: publishedDate,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Helper function to create readability extractor
Readability4JExtended createReadabilityExtractor({
  http.Client? client,
  Duration requestDelay = const Duration(milliseconds: 500),
  bool attemptRssFallback = true,
  Map<String, String>? cookies,
  Map<String, String>? customHeaders,
  Future<String?> Function(String url)? cookieHeaderBuilder,
  bool useMobileUserAgent = false,
  bool attemptAuthenticatedRss = true,
  Duration pageLoadDelay = const Duration(seconds: 3),
  Duration webViewSnapshotInterval = const Duration(seconds: 2),
  Duration webViewMaxSnapshotDuration = const Duration(seconds: 12),
  Duration webViewRenderTimeoutBuffer = const Duration(seconds: 20),
  int webViewMaxSnapshots = 3,
  double webViewChangeThreshold = 0.02,
  int paginationPageLimit = 3,
  Map<String, String>? siteSpecificAuthHeaders,
  Map<String, String>? knownSubscriberFeeds,
}) {
  final config = ReadabilityConfig(
    requestDelay: requestDelay,
    attemptRssFallback: attemptRssFallback,
  );

  return Readability4JExtended(
    client: client,
    config: config,
  );
}
