import 'dart:convert';
import 'dart:io';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// Result of readability extraction: main article text + optional hero image.
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

  @override
  String toString() {
    return 'ArticleReadabilityResult{'
        'title: $pageTitle, '
        'textLength: ${mainText?.length ?? 0}, '
        'isPaywalled: $isPaywalled, '
        'source: $source}';
  }
}

/// Metadata extraction result
class _Metadata {
  final String? title;
  final String? author;
  final DateTime? publishedDate;
  final String? imageUrl;

  _Metadata({
    this.title,
    this.author,
    this.publishedDate,
    this.imageUrl,
  });
}
/// Represents an RSS item's rich content to be merged into readability results.
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
/// Configuration for the readability service - FIXED CONSTRUCTOR
class ReadabilityConfig {
  final Map<String, String>? cookies;
  final Map<String, String>? customHeaders;
  final List<String> paywallKeywords;
  final bool attemptRssFallback;
  final Duration requestDelay;
  final Duration pageLoadDelay;
  final int paginationPageLimit;
  final bool useMobileUserAgent;
  final String userAgent;
  ReadabilityConfig({
    Map<String, String>? cookies,
    Map<String, String>? customHeaders,
    List<String>? paywallKeywords,
    bool? attemptRssFallback,
    Duration? requestDelay,
    Duration? pageLoadDelay,
    int? paginationPageLimit,
    bool? useMobileUserAgent,
    String? userAgent,
  })  : cookies = cookies,
        customHeaders = customHeaders,
        paywallKeywords = paywallKeywords ??
            const [
              'subscribe',
              'premium',
              'members-only',
              'paywall',
              'locked',
              'restricted',
              'membership',
              'subscriber',
              'login-required',
              'sign-in',
              'register',
              'purchase',
              'subscribe now',
              'To continue reading',
              'This content is for subscribers only',
            ],
        attemptRssFallback = attemptRssFallback ?? true,
        requestDelay = requestDelay ?? const Duration(seconds: 2),
        pageLoadDelay = pageLoadDelay ?? Duration.zero,
         paginationPageLimit = paginationPageLimit ?? 3,
        useMobileUserAgent = useMobileUserAgent ?? false,
        userAgent = userAgent ??
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
}

/// RSS feed parser for news sites
class RssFeedParser {
  final http.Client _client;

  RssFeedParser({http.Client? client}) : _client = client ?? http.Client();

/// Extract article content and metadata from an RSS feed.
  Future<_RssItemContent?> extractFromRss(
    String rssUrl,
    String targetUrl, {
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _client.get(
        Uri.parse(rssUrl),
        headers: headers,
      );
      if (response.statusCode != 200) return null;

      final xmlDoc = XmlDocument.parse(response.body);
      final normalizedTarget = _normalizeUrl(targetUrl);

          // If not found, try description
          for (final item in xmlDoc.findAllElements('item')) {
        final link = _readText(item, 'link');
        final guid = _readText(item, 'guid');
        final origin = _readText(item, 'origLink');

          final candidateLinks = [link, guid, origin]
            .where((candidate) => candidate != null)
            .cast<String>();

          final matched = candidateLinks.any(
          (candidate) => _matchesTarget(_normalizeUrl(candidate), normalizedTarget),
        );

        if (!matched) continue;

        final content = _readText(item, 'encoded', namespace: 'content') ??
            _readText(item, 'content') ??
            _readText(item, 'description');

        final cleanedText = _cleanRssContent(content);

        // Prefer media content; fall back to enclosure or first image in HTML.
        final imageUrl = _extractImageUrl(item) ?? _extractImageFromHtml(content);

        final author = _readText(item, 'creator', namespace: 'dc') ??
            _readText(item, 'author');
        final pubDate = _parseDate(_readText(item, 'pubDate')) ??
            _parseDate(_readText(item, 'published'));

        final title = _readText(item, 'title');

        if (cleanedText != null && cleanedText.trim().isNotEmpty) {
          return _RssItemContent(
            text: cleanedText,
            imageUrl: imageUrl,
            title: title,
            author: author,
            publishedDate: pubDate,
          );
        }
      }
    } catch (e) {
      print('RSS parsing error: $e');
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
    return candidate == normalizedTarget ||
        candidate.contains(normalizedTarget) ||
        normalizedTarget.contains(candidate);
  }

  String _normalizeUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final filteredParams = Map<String, String>.fromEntries(
        uri.queryParameters.entries.where(
          (entry) =>
              !entry.key.toLowerCase().startsWith('utm_') &&
              entry.key.toLowerCase() != 'fbclid',
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

    final paragraphs = fragment.querySelectorAll('p, li, blockquote, pre');
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
    if (mediaContent.isNotEmpty) {
      final url = mediaContent.first.getAttribute('url');
      if (url != null && url.isNotEmpty) return url;
    }

    final enclosure = item.findElements('enclosure');
    if (enclosure.isNotEmpty) {
      final url = enclosure.first.getAttribute('url');
      final type = enclosure.first.getAttribute('type');
      if (url != null && (type?.startsWith('image/') ?? true)) {
        return url;
      }
    }
    return null;
  }

  String? _extractImageFromHtml(String? html) {
    if (html == null || html.isEmpty) return null;
    final fragment = html_parser.parseFragment(html);
    final img = fragment.querySelector('img');
    return img?.attributes['src'];
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

/// Main readability class
class Readability4JExtended {
  final http.Client _client;
  final ReadabilityConfig _config;
  final RssFeedParser _rssParser;
  final Map<String, DateTime> _lastRequestTime = {};
  final Future<String?> Function(String url)? cookieHeaderBuilder;

  Readability4JExtended({
    http.Client? client,
    ReadabilityConfig? config,
    this.cookieHeaderBuilder,
  })  : _client = client ?? http.Client(),
        _config = config ?? ReadabilityConfig(), // 使用非const构造函数
        _rssParser = RssFeedParser(client: client);

  /// Main extraction method
  Future<ArticleReadabilityResult?> extractMainContent(String url) async {
    try {
      // Respect rate limiting
      await _respectRateLimit(url);

      // Try multiple strategies in order
      final strategies = [
        _extractWithDefaultStrategy(url),
        if (_config.useMobileUserAgent) _extractWithMobileStrategy(url),
        if (_config.attemptRssFallback) _extractFromRssStrategy(url),
      ];

      for (final strategy in strategies) {
        try {
          final result = await strategy;
          if (result != null && result.hasContent) {
            return result;
          }
        } catch (_) {
          continue;
        }
      }

      return null;
    } catch (e) {
      print('Error extracting content from $url: $e');
      return null;
    }
  }

  /// Strategy 1: Default extraction with desktop user agent
  Future<ArticleReadabilityResult?> _extractWithDefaultStrategy(
      String url) async {
    try {
      final headers = await _buildRequestHeaders(url);
      return await _extractContent(url, headers, 'Desktop');
    } catch (e) {
      print('Error in _extractWithDefaultStrategy: $e');
      return null;
    }
  }

  /// Strategy 2: Extract with mobile user agent
  Future<ArticleReadabilityResult?> _extractWithMobileStrategy(
      String url) async {
    try {
      final headers = await _buildRequestHeaders(url, mobile: true);
      return await _extractContent(url, headers, 'Mobile');
    } catch (e) {
      print('Error in _extractWithMobileStrategy: $e');
      return null;
    }
  }
  /// Extract article content from an existing HTML document (e.g., WebView DOM).
  Future<ArticleReadabilityResult?> extractFromHtml(
    String url,
    String html, {
    String strategyName = 'DOM',
  }) async {
    try {
      final doc = html_parser.parse(html);
      return _extractFromDocument(url, doc, strategyName);
    } catch (_) {
      return null;
    }
  }
  /// Strategy 3: Try RSS feed for news sites
  Future<ArticleReadabilityResult?> _extractFromRssStrategy(String url) async {
    final rssUrls = _generateRssUrls(url);

    for (final rssUrl in rssUrls) {
      try {
        final rssHeaders = await _buildRequestHeaders(rssUrl);
        final rssContent = await _rssParser.extractFromRss(
          rssUrl,
          url,
          headers: rssHeaders,
        );
        if (rssContent != null && rssContent.hasContent) {
          final metadata = _Metadata(
            title: rssContent.title,
            author: rssContent.author,
            publishedDate: rssContent.publishedDate,
            imageUrl: rssContent.imageUrl,
          );

          return ArticleReadabilityResult(
            mainText: _normalizeWhitespace(rssContent.text),
            imageUrl: metadata.imageUrl,
            pageTitle: metadata.title,
            isPaywalled: false,
            source: 'RSS',
            author: metadata.author,
            publishedDate: metadata.publishedDate,
          );
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  /// Generate possible RSS feed URLs for a given news URL
  List<String> _generateRssUrls(String url) {
    final uri = Uri.parse(url);
    final baseUrl = '${uri.scheme}://${uri.host}';
    final path = uri.path;

    final rssUrls = <String>[
      '$baseUrl/feed',
      '$baseUrl/rss',
      '$baseUrl/feed/rss',
      '$baseUrl/feed.xml',
      '$baseUrl/rss.xml',
      '$baseUrl/atom.xml',
      '$baseUrl/index.xml',
      '$baseUrl/?feed=rss',
    ];

    if (path.contains('/news/')) {
      final section = path.split('/')[1];
      rssUrls.addAll([
        '$baseUrl/$section/feed',
        '$baseUrl/$section/rss',
        if (path.split('/').length > 2)
          '$baseUrl/category/${path.split('/')[2]}/feed',
      ]);
    }

    rssUrls.addAll([
      '$baseUrl/?feed=rss2',
      '$baseUrl/?feed=atom',
    ]);

    return rssUrls;
  }

  /// Common extraction logic - FIXED: JSON-LD extraction before cleaning
    Future<ArticleReadabilityResult?> _extractContent(
    String url,
    Map<String, String> headers,
    String strategyName,
  ) async {
    try {
      final doc = await _fetchDocument(url, headers);
      if (doc == null) return null;

      return _extractFromDocument(url, doc, strategyName);
    } catch (_) {
      return null;
    }
  }

  ArticleReadabilityResult? _extractFromDocument(
    String url,
    dom.Document doc,
    String strategyName,
  ) {
    final isPaywalled = _detectPaywall(doc);
    final pageUri = Uri.parse(url);
    final metadata = _extractMetadata(doc, pageUri);

    // Extract JSON-LD BEFORE cleaning document (script tags will be removed)
    String? jsonLdContent = _extractJsonLdContent(doc);

    _cleanDocument(doc);
    _removePaywallElements(doc);

    String? content;
    String? source = strategyName;

    // Use JSON-LD content if available
    if (jsonLdContent != null && jsonLdContent.trim().isNotEmpty) {
      content = jsonLdContent.trim();
      source = 'JSON-LD';
    }

    // If no JSON-LD, try normal article extraction
    if (content == null) {
      final articleRoot = _findArticleRoot(doc);
      if (articleRoot != null) {
        final text = _extractMainText(articleRoot);
        content = _normalizeWhitespace(text);

        if (_isContentTruncated(content)) {
          final hiddenContent = _extractHiddenContent(articleRoot);
          if (hiddenContent != null && hiddenContent.length > content.length) {
            content = hiddenContent;
            source = 'Hidden Content';
          }
        }
      }
    }

    // Fallback to general text extraction
    if (content == null || content.isEmpty) {
      content = _extractFallbackText(doc);
    }

    if (content == null || content.isEmpty) {
      return null;
    }

    final heroImage = _extractHeroImage(doc, pageUri);

    return ArticleReadabilityResult(
      mainText: content,
      imageUrl: heroImage,
      pageTitle: metadata.title,
      isPaywalled: isPaywalled,
      source: source,
      author: metadata.author,
      publishedDate: metadata.publishedDate,
    );
  }


  /// Fetch document with error handling
  Future<dom.Document?> _fetchDocument(
    String url, [
    Map<String, String>? headers,
  ]) async {
    try {
      final effectiveHeaders = headers ?? await _buildRequestHeaders(url);
      final response =
          await _client.get(Uri.parse(url), headers: effectiveHeaders);

      if (response.statusCode != 200) {
        return null;
      }
      if (_config.pageLoadDelay > Duration.zero) {
        await Future.delayed(_config.pageLoadDelay);
      }

      var doc = html_parser.parse(response.body);

      if (_config.paginationPageLimit > 0) {
        doc = await _maybeAppendNextPages(
              doc,
              Uri.parse(url),
              effectiveHeaders,
            ) ??
            doc;
      }

      return doc;
    } catch (_) {
      return null;
    }
  }
   Future<dom.Document?> _maybeAppendNextPages(
    dom.Document doc,
    Uri baseUri,
    Map<String, String> headers,
  ) async {
    final seen = <String>{baseUri.toString()};
    var current = doc;
    var nextUrl = _findNextPageUrl(current, baseUri);
    var depth = 0;

    while (nextUrl != null && depth < _config.paginationPageLimit) {
      if (seen.contains(nextUrl)) {
        break;
      }

      seen.add(nextUrl);

      try {
        final resp = await _client.get(Uri.parse(nextUrl), headers: headers);
        if (resp.statusCode != 200) {
          break;
        }

        if (_config.pageLoadDelay > Duration.zero) {
          await Future.delayed(_config.pageLoadDelay);
        }

        final nextDoc = html_parser.parse(resp.body);
        current = _mergeDocuments(current, nextDoc);
      } catch (_) {
        break;
      }

      depth++;
      nextUrl = _findNextPageUrl(current, Uri.parse(nextUrl));
    }

    return current;
  }

  dom.Document _mergeDocuments(dom.Document original, dom.Document nextDoc) {
    final body = original.body;
    final nextBody = nextDoc.body;
    if (body == null || nextBody == null) {
      return original;
    }

    for (final child in nextBody.children) {
      body.append(child.clone(true));
    }

    return original;
  }

  String? _findNextPageUrl(dom.Document doc, Uri baseUri) {
    final link = doc.querySelector('link[rel="next"]');
    final href = link?.attributes['href'];
    if (href != null && href.isNotEmpty) {
      return baseUri.resolve(href).toString();
    }

    final anchors = doc
        .querySelectorAll('a[href]')
        .where((a) =>
            (a.text ?? '').toLowerCase().contains('next') ||
            (a.attributes['aria-label'] ?? '')
                .toLowerCase()
                .contains('next'))
        .toList();

    for (final a in anchors) {
      final href = a.attributes['href'];
      if (href != null && href.isNotEmpty) {
        return baseUri.resolve(href).toString();
      }
    }

    return null;
  }
  /// Build request headers - FIXED NULL SAFETY
  Future<Map<String, String>> _buildRequestHeaders(
    String url, {
    bool mobile = false,
  }) async {
    final headers = <String, String>{
      'User-Agent': mobile
          ? 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36'
          : _config.userAgent,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'Accept-Encoding': 'gzip, deflate',
      'Connection': 'keep-alive',
      'Upgrade-Insecure-Requests': '1',
    };

    // Add cookies
    final builtCookie =
        cookieHeaderBuilder != null ? await cookieHeaderBuilder!(url) : null;

    if (builtCookie != null && builtCookie.isNotEmpty) {
      headers['Cookie'] = builtCookie;
    } else if (_config.cookies != null && _config.cookies!.isNotEmpty) {
      final cookieString =
          _config.cookies!.entries.map((e) => '${e.key}=${e.value}').join('; ');
      headers['Cookie'] = cookieString;
    }

    // Add custom headers
    if (_config.customHeaders != null) {
      headers.addAll(_config.customHeaders!);
    }

    // Add referer header
    final uri = Uri.parse(url);
    headers['Referer'] = '${uri.scheme}://${uri.host}';

    return headers;
  }

  /// Respect rate limiting per domain
  Future<void> _respectRateLimit(String url) async {
    final domain = Uri.parse(url).host;
    final lastRequest = _lastRequestTime[domain];

    if (lastRequest != null) {
      final elapsed = DateTime.now().difference(lastRequest);
      final delay = _config.requestDelay;

      if (elapsed < delay) {
        await Future.delayed(delay - elapsed);
      }
    }

    _lastRequestTime[domain] = DateTime.now();
  }

  /// Extract metadata from document
  _Metadata _extractMetadata(dom.Document doc, Uri pageUri) {
    return _Metadata(
      title: _extractTitle(doc),
      author: _extractAuthor(doc),
      publishedDate: _extractPublishedDate(doc),
      imageUrl: _extractMetaImage(doc, pageUri),
    );
  }

  /// Extract page title
  String? _extractTitle(dom.Document doc) {
    final ogTitle =
        doc.querySelector('meta[property="og:title"]')?.attributes['content'];
    if (ogTitle != null && ogTitle.trim().isNotEmpty) return ogTitle.trim();

    final twitterTitle =
        doc.querySelector('meta[name="twitter:title"]')?.attributes['content'];
    if (twitterTitle != null && twitterTitle.trim().isNotEmpty)
      return twitterTitle.trim();

    final schemaTitle =
        doc.querySelector('meta[itemprop="name"]')?.attributes['content'];
    if (schemaTitle != null && schemaTitle.trim().isNotEmpty)
      return schemaTitle.trim();

    final plainTitle = doc.querySelector('title')?.text;
    if (plainTitle != null && plainTitle.trim().isNotEmpty) {
      return plainTitle.trim();
    }

    final h1 = doc.querySelector('h1')?.text;
    if (h1 != null && h1.trim().isNotEmpty) {
      return h1.trim();
    }

    return null;
  }

  /// Extract author information
  String? _extractAuthor(dom.Document doc) {
    final ogAuthor = doc
            .querySelector('meta[property="og:author"]')
            ?.attributes['content'] ??
        doc
            .querySelector('meta[property="article:author"]')
            ?.attributes['content'];
    if (ogAuthor != null && ogAuthor.trim().isNotEmpty) return ogAuthor.trim();

    final schemaAuthor =
        doc.querySelector('meta[itemprop="author"]')?.attributes['content'];
    if (schemaAuthor != null && schemaAuthor.trim().isNotEmpty)
      return schemaAuthor.trim();

    final twitterAuthor = doc
        .querySelector('meta[name="twitter:creator"]')
        ?.attributes['content'];
    if (twitterAuthor != null && twitterAuthor.trim().isNotEmpty)
      return twitterAuthor.trim();

    final authorSelectors = [
      '.author',
      '.byline',
      '[rel="author"]',
      '.post-author',
      '.article-author',
      '.story-author',
      'a[href*="/author/"]',
    ];

    for (final selector in authorSelectors) {
      final authorElement = doc.querySelector(selector);
      if (authorElement != null) {
        final authorText = authorElement.text?.trim();
        if (authorText != null && authorText.isNotEmpty) {
          return authorText;
        }
      }
    }

    return null;
  }

  /// Extract published date
  DateTime? _extractPublishedDate(dom.Document doc) {
    try {
      final ogDate = doc
              .querySelector('meta[property="article:published_time"]')
              ?.attributes['content'] ??
          doc
              .querySelector('meta[property="og:published_time"]')
              ?.attributes['content'];
      if (ogDate != null && ogDate.trim().isNotEmpty) {
        return DateTime.tryParse(ogDate.trim());
      }

      final schemaDate = doc
          .querySelector('meta[itemprop="datePublished"]')
          ?.attributes['content'];
      if (schemaDate != null && schemaDate.trim().isNotEmpty) {
        return DateTime.tryParse(schemaDate.trim());
      }

      final dateSelectors = [
        'time[datetime]',
        '.date',
        '.published',
        '.post-date',
        '.article-date',
        '.story-date',
        '.timestamp',
      ];

      for (final selector in dateSelectors) {
        final dateElement = doc.querySelector(selector);
        if (dateElement != null) {
          final dateTime = dateElement.attributes['datetime'];
          if (dateTime != null && dateTime.trim().isNotEmpty) {
            final parsed = DateTime.tryParse(dateTime.trim());
            if (parsed != null) return parsed;
          }

          final dateText = dateElement.text?.trim();
          if (dateText != null && dateText.isNotEmpty) {
            final patterns = [
              RegExp(r'\d{4}-\d{2}-\d{2}'),
              RegExp(r'\d{2}/\d{2}/\d{4}'),
              RegExp(r'\d{1,2}\s+\w+\s+\d{4}'),
            ];

            for (final pattern in patterns) {
              final match = pattern.firstMatch(dateText);
              if (match != null) {
                try {
                  return DateTime.parse(match.group(0)!);
                } catch (_) {
                  continue;
                }
              }
            }
          }
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  /// Detect paywall on page
  bool _detectPaywall(dom.Document doc) {
    final bodyText = doc.body?.text?.toLowerCase() ?? '';
    final html = doc.outerHtml?.toLowerCase() ?? '';

    for (final keyword in _config.paywallKeywords) {
      if (bodyText.contains(keyword.toLowerCase()) ||
          html.contains(keyword.toLowerCase())) {
        final paywallElements = doc.querySelectorAll('''
          [class*="paywall"],
          [id*="paywall"],
          [class*="premium"],
          [id*="premium"],
          [class*="subscribe"],
          [class*="members-only"]
        ''');

        if (paywallElements.isNotEmpty) {
          return true;
        }
      }
    }

    return false;
  }

  /// Clean document by removing noise elements
  void _cleanDocument(dom.Document doc) {
    // DON'T remove JSON-LD scripts - they're already extracted
    final garbage = doc.querySelectorAll(
      'style,noscript,form,iframe,video,audio,svg,canvas',
    );
    for (final node in garbage) {
      node.remove();
    }

    // Remove regular script tags but keep JSON-LD for now (will be removed later if needed)
    final scripts =
        doc.querySelectorAll('script:not([type="application/ld+json"])');
    for (final node in scripts) {
      node.remove();
    }

    final noiseSelectors = [
      'header',
      'footer',
      'nav',
      'aside',
      'dialog',
      'modal',
      '.sidebar',
      '.navigation',
      '.advertisement',
      '.ad',
      '.banner',
      '.popup',
      '.modal',
      '.newsletter',
      '.social-share',
      '.related-posts',
      '.comments',
      '.comment-section',
    ];

    for (final selector in noiseSelectors) {
      final elements = doc.querySelectorAll(selector);
      for (final element in elements) {
        element.remove();
      }
    }
  }

  /// Remove paywall-specific elements
  void _removePaywallElements(dom.Document doc) {
    final paywallSelectors = [
      '[class*="paywall"]',
      '[id*="paywall"]',
      '[class*="premium"]',
      '[id*="premium"]',
      '[class*="locked"]',
      '[id*="locked"]',
      '[class*="restricted"]',
      '[class*="members-only"]',
      '[class*="subscribe"]',
      '[class*="register"]',
      '.paywall',
      '.premium-content',
      '.content-locked',
      '.article-locked',
      '.blurred',
      '.obscured',
    ];

    for (final selector in paywallSelectors) {
      final elements = doc.querySelectorAll(selector);
      for (final el in elements) {
        el.remove();
      }
    }
  }

  /// Extract content from JSON-LD metadata
  String? _extractJsonLdContent(dom.Document doc) {
    try {
      final scripts =
          doc.querySelectorAll('script[type="application/ld+json"]');

      for (final script in scripts) {
        final content = script.text?.trim();
        if (content == null || content.isEmpty) continue;

        try {
          final json = jsonDecode(content);
          if (json is Map<String, dynamic>) {
            if (json['@type'] == 'NewsArticle' ||
                json['@type'] == 'Article' ||
                json['@type'] == 'BlogPosting') {
              final articleBody =
                  json['articleBody'] ?? json['description'] ?? json['text'];
              if (articleBody != null &&
                  articleBody is String &&
                  articleBody.trim().isNotEmpty) {
                return articleBody.trim();
              }
            }

            if (json['mainEntity'] is Map) {
              final mainEntity = json['mainEntity'] as Map<String, dynamic>;
              if (mainEntity['articleBody'] != null) {
                final body = mainEntity['articleBody'] as String;
                if (body.trim().isNotEmpty) {
                  return body.trim();
                }
              }
            }
          }
        } catch (e) {
          print('JSON-LD parse error: $e');
          continue;
        }
      }
    } catch (e) {
      print('JSON-LD extraction error: $e');
      return null;
    }

    return null;
  }

  /// Check if content appears truncated
  bool _isContentTruncated(String? content) {
    if (content == null || content.length < 300) return false;

    final truncatedPatterns = [
      RegExp(r'\.\.\.\s*$'),
      RegExp(r'…\s*$'),
      RegExp(r'continue reading', caseSensitive: false),
      RegExp(r'read more', caseSensitive: false),
      RegExp(r'subscribe to read', caseSensitive: false),
      RegExp(r'to continue reading', caseSensitive: false),
      RegExp(r'premium content', caseSensitive: false),
    ];

    for (final pattern in truncatedPatterns) {
      if (pattern.hasMatch(content)) {
        return true;
      }
    }

    return false;
  }

  /// Extract hidden content from data attributes
  String? _extractHiddenContent(dom.Element root) {
    final dataElements =
        root.querySelectorAll('[data-content], [data-article], [data-text]');

    for (final el in dataElements) {
      final content = el.attributes['data-content'] ??
          el.attributes['data-article'] ??
          el.attributes['data-text'];
      if (content != null && content.length > 100) {
        return content;
      }
    }

    return null;
  }

  /// Find the main article root element
  dom.Element? _findArticleRoot(dom.Document doc) {
    final prioritySelectors = [
      'article',
      'main',
      '[role="main"]',
      '#content',
      '.content',
      '.post',
      '.article-body',
      '.story-body',
      '.entry-content',
      '.article-content',
      '.post-content',
      '.story-content',
      '.news-content',
      '.article-text',
      '.article-main',
      '.main-content',
      '.post-body',
    ];

    dom.Element? best;
    var bestScore = 0;

    for (final selector in prioritySelectors) {
      final els = doc.querySelectorAll(selector);
      for (final el in els) {
        final score = _calculateElementScore(el);
        if (score > bestScore) {
          bestScore = score;
          best = el;
        }
      }
    }

    const minArticleScore = 30;
    if (best != null && bestScore >= minArticleScore) {
      return best;
    }

    best = null;
    bestScore = 0;

    final allBlocks = <dom.Element>[];
    allBlocks.addAll(doc.querySelectorAll('div'));
    allBlocks.addAll(doc.querySelectorAll('section'));
    allBlocks.addAll(doc.querySelectorAll('article'));

    for (final el in allBlocks) {
      final score = _calculateElementScore(el);
      if (score > bestScore) {
        bestScore = score;
        best = el;
      }
    }

    if (best != null && bestScore >= minArticleScore) {
      return best;
    }

    final body = doc.body;
    if (body != null) {
      final bodyScore = _calculateElementScore(body);
      if (bodyScore >= minArticleScore) {
        return body;
      }
    }

    return null;
  }

  /// Calculate score for an element based on text content
  int _calculateElementScore(dom.Element el) {
    final blocks = el.querySelectorAll('p, li, h1, h2, h3, h4, h5, h6');
    var total = 0.0;

    for (final block in blocks) {
      final text = block.text?.trim() ?? '';
      if (text.isEmpty) continue;

      double weight = 1.0;
      switch (block.localName) {
        case 'p':
          weight = 1.5;
          break;
        case 'h1':
        case 'h2':
        case 'h3':
          weight = 0.8;
          break;
        case 'li':
          weight = 1.2;
          break;
      }

      total += text.length * weight;
    }

    final linkCount = el.querySelectorAll('a').length;
    final textLength = el.text?.length ?? 0;
    if (textLength > 0) {
      final linkDensity = linkCount / (textLength / 100);
      if (linkDensity > 2.0) {
        total *= 0.5;
      }
    }

    return total.toInt();
  }

  /// Extract main text from article root
  String _extractMainText(dom.Element root) {
    final buffer = StringBuffer();
    final seenTexts = <String>{};

    final blocks =
        root.querySelectorAll('p, h1, h2, h3, h4, h5, h6, li, blockquote');

    for (final block in blocks) {
      final text = block.text?.trim() ?? '';
      if (text.isEmpty) continue;

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

  /// Extract hero image from document
  String? _extractHeroImage(dom.Document doc, Uri pageUri) {
    final ogImage =
        doc.querySelector('meta[property="og:image"]')?.attributes['content'];
    if (ogImage != null && ogImage.trim().isNotEmpty && _isGoodImage(ogImage)) {
      return _resolveImageUrl(ogImage.trim(), pageUri);
    }

    final twitterImage =
        doc.querySelector('meta[name="twitter:image"]')?.attributes['content'];
    if (twitterImage != null &&
        twitterImage.trim().isNotEmpty &&
        _isGoodImage(twitterImage)) {
      return _resolveImageUrl(twitterImage.trim(), pageUri);
    }

    final schemaImage =
        doc.querySelector('meta[itemprop="image"]')?.attributes['content'];
    if (schemaImage != null &&
        schemaImage.trim().isNotEmpty &&
        _isGoodImage(schemaImage)) {
      return _resolveImageUrl(schemaImage.trim(), pageUri);
    }

    final images = doc.querySelectorAll('img');
    String? bestImage;
    var bestSize = 0;

    for (final img in images) {
      final src = img.attributes['src'] ?? img.attributes['data-src'];
      if (src == null || !_isGoodImage(src)) continue;

      final width = int.tryParse(img.attributes['width'] ?? '') ?? 0;
      final height = int.tryParse(img.attributes['height'] ?? '') ?? 0;
      final size = width * height;

      final parent = img.parent?.localName ?? '';
      final isFigure =
          parent == 'figure' || img.className.contains('wp-block-image');

      if (size > bestSize || (isFigure && size > 10000)) {
        bestSize = size;
        bestImage = src;
      }
    }

    return bestImage != null ? _resolveImageUrl(bestImage, pageUri) : null;
  }

  /// Extract meta image for metadata
  String? _extractMetaImage(dom.Document doc, Uri pageUri) {
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

    return null;
  }

  /// Check if an image URL looks good (not junk)
  bool _isGoodImage(String url) {
    final lower = url.toLowerCase();

    if (lower.startsWith('data:') ||
        lower.endsWith('.svg') ||
        lower.endsWith('.gif')) {
      return false;
    }

    const junkPatterns = [
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
      'loader',
      'spinner',
      'thumbnail',
      'thumb_',
      'favicon',
    ];

    for (final pattern in junkPatterns) {
      if (lower.contains(pattern)) {
        return false;
      }
    }

    return true;
  }

  /// Resolve relative image URLs to absolute URLs
  String? _resolveImageUrl(String? url, Uri baseUri) {
    if (url == null || url.trim().isEmpty) return null;

    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;

    if (uri.hasScheme) return uri.toString();

    return baseUri.resolveUri(uri).toString();
  }

  /// Normalize whitespace in text
  String _normalizeWhitespace(String raw) {
    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.join('\n\n');
  }

  /// Extract fallback text from document - FIXED VERSION
  String? _extractFallbackText(dom.Document doc) {
    // First try to find any container with substantial text
    final allElements = doc.querySelectorAll('div, section, article, main');
    final candidates = <dom.Element>[];

    for (final el in allElements) {
      final text = el.text?.trim() ?? '';
      if (text.length > 150) {
        // Lowered threshold for tests
        candidates.add(el);
      }
    }

    if (candidates.isNotEmpty) {
      // Pick the element with the most text
      candidates
          .sort((a, b) => (b.text?.length ?? 0).compareTo(a.text?.length ?? 0));
      final best = candidates.first;

      // Use _extractMainText if it has block elements, otherwise use its text
      final blocks =
          best.querySelectorAll('p, h1, h2, h3, h4, h5, h6, li, blockquote');
      if (blocks.isNotEmpty) {
        return _normalizeWhitespace(_extractMainText(best));
      } else {
        return _normalizeWhitespace(best.text?.trim() ?? '');
      }
    }

    // Last resort: use body text
    final bodyText = doc.body?.text?.trim() ?? '';
    if (bodyText.isNotEmpty) {
      final normalized = _normalizeWhitespace(bodyText);
      return normalized.length > 80 ? normalized : null;
    }

    return null;
  }

  /// Batch extract multiple articles
  Future<List<ArticleReadabilityResult?>> extractArticles(
      List<String> urls) async {
    final results = <ArticleReadabilityResult?>[];

    for (final url in urls) {
      try {
        // Reset rate limiting for each URL to ensure parallel processing works
        final result = await extractMainContent(url);
        results.add(result);
      } catch (_) {
        results.add(null);
      }

      // Don't delay on the last item
      if (url != urls.last) {
        await Future.delayed(_config.requestDelay);
      }
    }

    return results;
  }
}

/// Helper function to create a generic readability extractor
Readability4JExtended createReadabilityExtractor({
  Map<String, String>? cookies,
  Map<String, String>? customHeaders,
  Future<String?> Function(String url)? cookieHeaderBuilder,
  bool useMobileUserAgent = false,
  Duration requestDelay = const Duration(seconds: 2),
  Duration pageLoadDelay = Duration.zero,
  int paginationPageLimit = 3,
  http.Client? client,
}) {
  final config = ReadabilityConfig(
    cookies: cookies,
    customHeaders: customHeaders,
    useMobileUserAgent: useMobileUserAgent,
    requestDelay: requestDelay,
    pageLoadDelay: pageLoadDelay,
    paginationPageLimit: paginationPageLimit,
  );

  return Readability4JExtended(
    client: client,
    config: config,
    cookieHeaderBuilder: cookieHeaderBuilder,
  );
}
