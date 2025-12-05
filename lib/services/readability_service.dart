// readability_service.dart - COMPLETE FIXED VERSION
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

/// Enhanced metadata extraction with paid content flags
class _Metadata {
  final String? title;
  final String? author;
  final DateTime? publishedDate;
  final String? imageUrl;
  final bool isSubscriberContent;
  final String? feedType;

  _Metadata({
    this.title,
    this.author,
    this.publishedDate,
    this.imageUrl,
    this.isSubscriberContent = false,
    this.feedType,
  });
}

/// Enhanced RSS item content with subscription info
class _RssItemContent {
  final String text;
  final String? imageUrl;
  final String? title;
  final String? author;
  final DateTime? publishedDate;
  final bool isSubscriberContent;
  final String? subscriptionTier;

  const _RssItemContent({
    required this.text,
    this.imageUrl,
    this.title,
    this.author,
    this.publishedDate,
    this.isSubscriberContent = false,
    this.subscriptionTier,
  });

  bool get hasContent => text.trim().isNotEmpty;
}

/// Configuration for the readability service - ENHANCED
class ReadabilityConfig {
  final Map<String, String>? cookies;
  final Map<String, String>? customHeaders;
  final List<String> paywallKeywords;
  final bool attemptRssFallback;
  final bool attemptAuthenticatedRss;
  final Duration requestDelay;
  final Duration pageLoadDelay;
  final int paginationPageLimit;
  final bool useMobileUserAgent;
  final String userAgent;
  final Map<String, String> siteSpecificAuthHeaders;
  final Map<String, String> knownSubscriberFeeds;

  ReadabilityConfig({
    Map<String, String>? cookies,
    Map<String, String>? customHeaders,
    List<String>? paywallKeywords,
    bool? attemptRssFallback,
    bool? attemptAuthenticatedRss,
    Duration? requestDelay,
    Duration? pageLoadDelay,
    int? paginationPageLimit,
    bool? useMobileUserAgent,
    String? userAgent,
    Map<String, String>? siteSpecificAuthHeaders,
    Map<String, String>? knownSubscriberFeeds,
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
        attemptAuthenticatedRss = attemptAuthenticatedRss ?? true,
        requestDelay = requestDelay ?? const Duration(seconds: 2),
        pageLoadDelay = pageLoadDelay ?? Duration.zero,
        paginationPageLimit = paginationPageLimit ?? 3,
        useMobileUserAgent = useMobileUserAgent ?? false,
        userAgent = userAgent ??
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        siteSpecificAuthHeaders = siteSpecificAuthHeaders ?? {},
        knownSubscriberFeeds = knownSubscriberFeeds ??
            {
              'nytimes.com': 'https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml',
              'wsj.com': 'https://feeds.a.dj.com/rss/RSSWSJD.xml',
              'ft.com': 'https://www.ft.com/?format=rss',
              'economist.com': 'https://www.economist.com/rss',
              'bloomberg.com': 'https://www.bloomberg.com/feed/podcast/etf-report.xml',
              'washingtonpost.com': 'https://feeds.washingtonpost.com/rss/rss_compost',
              'theguardian.com': 'https://www.theguardian.com/world/rss',
              'reuters.com': 'https://www.reutersagency.com/feed/',
              'apnews.com': 'https://apnews.com/feed',
            };
}

/// Enhanced RSS feed parser with subscription detection
class RssFeedParser {
  final http.Client _client;
  final Map<String, String>? _siteSpecificAuthHeaders;
  final Future<String?> Function(String url)? cookieHeaderBuilder;

  RssFeedParser({
    http.Client? client,
    Map<String, String>? siteSpecificAuthHeaders,
    this.cookieHeaderBuilder,
  })  : _client = client ?? http.Client(),
        _siteSpecificAuthHeaders = siteSpecificAuthHeaders;

  /// Extract article content and metadata from RSS feed with subscription support
  Future<_RssItemContent?> extractFromRss(
    String rssUrl,
    String targetUrl, {
    Map<String, String>? headers,
    bool isSubscriberFeed = false,
  }) async {
    try {
      final enhancedHeaders = await _enhanceHeadersForRss(
        rssUrl,
        headers ?? {},
        isSubscriberFeed: isSubscriberFeed,
      );

      final response = await _client.get(
        Uri.parse(rssUrl),
        headers: enhancedHeaders,
      );
      
      if (response.statusCode != 200) {
        return null;
      }

      final xmlDoc = XmlDocument.parse(response.body);
      final normalizedTarget = _normalizeUrl(targetUrl);

      final isSubscriberContent = _detectSubscriberContent(xmlDoc);

      for (final item in xmlDoc.findAllElements('item')) {
        final link = _readText(item, 'link');
        final guid = _readText(item, 'guid');
        final origin = _readText(item, 'origLink');

        final candidateLinks = [link, guid, origin]
            .where((candidate) => candidate != null)
            .cast<String>();

        final matched = candidateLinks.any((candidate) =>
            _matchesTarget(_normalizeUrl(candidate), normalizedTarget));

        if (!matched) continue;

        final content = _readText(item, 'encoded', namespace: 'content') ??
            _readText(item, 'full-text', namespace: 'content') ??
            _readText(item, 'content') ??
            _readText(item, 'description');

        final cleanedText = _cleanRssContent(content);
        
        final subscriptionTier = _extractSubscriptionTier(item);

        final imageUrl = _extractImageUrl(item) ??
            _extractImageFromHtml(content) ??
            _extractImageFromEnclosure(item);

        final author = _readText(item, 'creator', namespace: 'dc') ??
            _readText(item, 'author') ??
            _readText(item, 'contributor', namespace: 'dc');

        final pubDate = _parseDate(_readText(item, 'pubDate')) ??
            _parseDate(_readText(item, 'published')) ??
            _parseDate(_readText(item, 'updated'));

        final title = _readText(item, 'title');

        if (cleanedText != null && cleanedText.trim().isNotEmpty) {
          return _RssItemContent(
            text: cleanedText,
            imageUrl: imageUrl,
            title: title,
            author: author,
            publishedDate: pubDate,
            isSubscriberContent: isSubscriberContent,
            subscriptionTier: subscriptionTier,
          );
        }
      }
    } catch (e) {
      print('RSS parsing error: $e');
    }
    return null;
  }

  /// Enhance headers for subscriber RSS feeds
  Future<Map<String, String>> _enhanceHeadersForRss(
    String rssUrl,
    Map<String, String> baseHeaders, {
    bool isSubscriberFeed = false,
  }) async {
    final enhanced = Map<String, String>.from(baseHeaders);
    
    final cookie = cookieHeaderBuilder != null 
        ? await cookieHeaderBuilder!(rssUrl) 
        : null;
    
    if (cookie != null && cookie.isNotEmpty) {
      enhanced['Cookie'] = cookie;
    }

    final uri = Uri.tryParse(rssUrl);
    if (uri != null && _siteSpecificAuthHeaders != null) {
      final host = uri.host;
      for (final entry in _siteSpecificAuthHeaders!.entries) {
        if (host.contains(entry.key)) {
          enhanced['Authorization'] = entry.value;
          break;
        }
      }
    }

    if (isSubscriberFeed) {
      enhanced['X-Requested-With'] = 'XMLHttpRequest';
      enhanced['X-Subscriber'] = 'true';
    }

    return enhanced;
  }

  /// Detect if RSS feed contains subscriber-only content
  bool _detectSubscriberContent(XmlDocument doc) {
    final channel = doc.findAllElements('channel').firstOrNull;
    if (channel != null) {
      final copyright = _readText(channel, 'copyright')?.toLowerCase() ?? '';
      final description = _readText(channel, 'description')?.toLowerCase() ?? '';
      
      const subscriberIndicators = [
        'subscriber',
        'premium',
        'members-only',
        'paid',
        'exclusive',
      ];
      
      for (final indicator in subscriberIndicators) {
        if (copyright.contains(indicator) || description.contains(indicator)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Extract subscription tier information
  String? _extractSubscriptionTier(XmlElement item) {
    final categories = item.findElements('category');
    for (final category in categories) {
      final text = category.text.toLowerCase();
      if (text.contains('premium') || text.contains('subscriber')) {
        return category.text;
      }
    }
    return null;
  }

  /// Enhanced image extraction from enclosure
  String? _extractImageFromEnclosure(XmlElement item) {
    final enclosures = item.findElements('enclosure');
    for (final enclosure in enclosures) {
      final type = enclosure.getAttribute('type')?.toLowerCase() ?? '';
      final url = enclosure.getAttribute('url');
      
      if (url != null && (type.startsWith('image/') || type.isEmpty)) {
        return url;
      }
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
    
    final candidateParts = Uri.tryParse(candidate);
    final targetParts = Uri.tryParse(normalizedTarget);
    
    if (candidateParts != null && targetParts != null) {
      final candidatePath = candidateParts.pathSegments.join('/');
      final targetPath = targetParts.pathSegments.join('/');
      
      if (candidatePath.isNotEmpty && targetPath.isNotEmpty) {
        if (candidatePath.contains(targetPath) || targetPath.contains(candidatePath)) {
          return true;
        }
      }
      
      final candidateId = candidateParts.queryParameters['id'] ?? 
                         candidateParts.queryParameters['article'];
      final targetId = targetParts.queryParameters['id'] ?? 
                      targetParts.queryParameters['article'];
      
      if (candidateId != null && targetId != null && candidateId == targetId) {
        return true;
      }
    }
    
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
              !entry.key.toLowerCase().startsWith('fbclid') &&
              !entry.key.toLowerCase().startsWith('_ga') &&
              entry.key.toLowerCase() != 'ref' &&
              entry.key.toLowerCase() != 'source',
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

    final paywallElements = fragment.querySelectorAll('''
      .paywall-message,
      .subscription-required,
      .premium-content-message,
      .article-locked
    ''');
    
    for (final element in paywallElements) {
      element.remove();
    }

    final paragraphs = fragment.querySelectorAll('p, li, blockquote, pre');
    if (paragraphs.isEmpty) {
      return _normalizeWhitespace(fragment.text ?? '');
    }

    final buffer = StringBuffer();
    for (final element in paragraphs) {
      final text = element.text.trim();
      if (text.isNotEmpty && !_isPaywallMessage(text)) {
        if (buffer.isNotEmpty) buffer.write('\n\n');
        buffer.write(text);
      }
    }

    return _normalizeWhitespace(buffer.toString());
  }

  bool _isPaywallMessage(String text) {
    const paywallPhrases = [
      'subscribe to read',
      'continue reading',
      'premium content',
      'members only',
      'subscriber exclusive',
    ];
    
    final lowerText = text.toLowerCase();
    return paywallPhrases.any((phrase) => lowerText.contains(phrase));
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

    return null;
  }

  String? _extractImageFromHtml(String? html) {
    if (html == null || html.isEmpty) return null;
    final fragment = html_parser.parseFragment(html);
    
    final img = fragment.querySelector('img[src]');
    if (img != null) {
      return img.attributes['src'];
    }
    
    final picture = fragment.querySelector('picture source[srcset]');
    if (picture != null) {
      final srcset = picture.attributes['srcset'];
      if (srcset != null && srcset.isNotEmpty) {
        return srcset.split(',').first.split(' ').first;
      }
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

/// Enhanced main readability class with ALL methods properly integrated
class Readability4JExtended {
  final http.Client _client;
  final ReadabilityConfig _config;
  final RssFeedParser _rssParser;
  final Map<String, DateTime> _lastRequestTime = {};
  final Future<String?> Function(String url)? cookieHeaderBuilder;
  final Map<String, bool> _feedSubscriptionStatus = {};

  Readability4JExtended({
    http.Client? client,
    ReadabilityConfig? config,
    this.cookieHeaderBuilder,
  })  : _client = client ?? http.Client(),
        _config = config ?? ReadabilityConfig(),
        _rssParser = RssFeedParser(
          client: client,
          siteSpecificAuthHeaders: config?.siteSpecificAuthHeaders,
          cookieHeaderBuilder: cookieHeaderBuilder,
        );

  /// Main extraction method with subscription awareness
  Future<ArticleReadabilityResult?> extractMainContent(String url) async {
    try {
      await _respectRateLimit(url);

      final strategies = [
        _extractWithDefaultStrategy(url),
        _extractFromKnownSubscriberFeeds(url),
        if (_config.useMobileUserAgent) _extractWithMobileStrategy(url),
        if (_config.attemptRssFallback) _extractFromRssStrategy(url),
        if (_config.attemptAuthenticatedRss) _extractFromAuthenticatedRssStrategy(url),
      ];

      for (final strategy in strategies) {
        try {
          final result = await strategy;
          if (result != null && result.hasContent) {
            return result;
          }
        } catch (e) {
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
  Future<ArticleReadabilityResult?> _extractWithDefaultStrategy(String url) async {
    try {
      final headers = await _buildRequestHeaders(url);
      return await _extractContent(url, headers, 'Desktop');
    } catch (e) {
      return null;
    }
  }

  /// NEW STRATEGY: Try known subscriber RSS feeds
  Future<ArticleReadabilityResult?> _extractFromKnownSubscriberFeeds(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    for (final domain in _config.knownSubscriberFeeds.keys) {
      if (uri.host.contains(domain)) {
        final rssUrl = _config.knownSubscriberFeeds[domain]!;
        
        final rssContent = await _rssParser.extractFromRss(
          rssUrl,
          url,
          isSubscriberFeed: true,
        );
        
        if (rssContent != null && rssContent.hasContent) {
          return _createResultFromRssContent(rssContent, 'Subscriber Feed');
        }
      }
    }
    
    return null;
  }

  /// NEW STRATEGY: Try authenticated RSS feeds
  Future<ArticleReadabilityResult?> _extractFromAuthenticatedRssStrategy(String url) async {
    try {
      final authenticatedRssUrls = _generateAuthenticatedRssUrls(url);
      
      for (final rssUrl in authenticatedRssUrls) {
        try {
          final rssContent = await _rssParser.extractFromRss(
            rssUrl,
            url,
            isSubscriberFeed: true,
          );
          
          if (rssContent != null && rssContent.hasContent) {
            return _createResultFromRssContent(rssContent, 'Authenticated RSS');
          }
        } catch (_) {
          continue;
        }
      }
    } catch (e) {
      print('Authenticated RSS strategy failed: $e');
    }
    
    return null;
  }

  /// Generate authenticated RSS URLs for subscriber content
  List<String> _generateAuthenticatedRssUrls(String url) {
    final uri = Uri.parse(url);
    final baseUrl = '${uri.scheme}://${uri.host}';

    return [
      '$baseUrl/feed/?auth=true',
      '$baseUrl/rss/?auth=true',
      '$baseUrl/feed/subscribers',
      '$baseUrl/rss/subscribers',
      '$baseUrl/members/feed',
      '$baseUrl/subscribers/feed',
      '$baseUrl/premium/feed',
      '$baseUrl/feed/?token=subscriber',
      '$baseUrl/feed/?subscription=true',
    ];
  }

  /// Strategy 2: Extract with mobile user agent
  Future<ArticleReadabilityResult?> _extractWithMobileStrategy(String url) async {
    try {
      final headers = await _buildRequestHeaders(url, mobile: true);
      return await _extractContent(url, headers, 'Mobile');
    } catch (e) {
      return null;
    }
  }

  /// Strategy 3: Try regular RSS feed for news sites
  Future<ArticleReadabilityResult?> _extractFromRssStrategy(String url) async {
    final rssUrls = _generateRssUrls(url);

    for (final rssUrl in rssUrls) {
      try {
        final rssContent = await _rssParser.extractFromRss(rssUrl, url);
        if (rssContent != null && rssContent.hasContent) {
          return _createResultFromRssContent(rssContent, 'RSS');
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  /// Create result from RSS content with subscription info
  ArticleReadabilityResult _createResultFromRssContent(
    _RssItemContent rssContent,
    String source,
  ) {
    return ArticleReadabilityResult(
      mainText: _normalizeWhitespace(rssContent.text),
      imageUrl: rssContent.imageUrl,
      pageTitle: rssContent.title,
      isPaywalled: rssContent.isSubscriberContent,
      source: rssContent.isSubscriberContent ? 'Subscriber $source' : source,
      author: rssContent.author,
      publishedDate: rssContent.publishedDate,
    );
  }

  /// Enhanced RSS URL generation - FIXED VERSION
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
      '$baseUrl/feed/atom',
      '$baseUrl/feed/rss2',
      '$baseUrl/feed/atom.xml',
      '$baseUrl/wp/feed',
      '$baseUrl/wordpress/feed',
      '$baseUrl/blog/feed',
      '$baseUrl/news/feed',
    ];

    // Section/category feeds - FIXED VARIABLE SCOPE
    if (path.contains('/')) {
      final segments = path.split('/').where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        final section = segments.first;
        rssUrls.addAll([
          '$baseUrl/$section/feed',
          '$baseUrl/$section/rss',
          '$baseUrl/category/$section/feed',
          '$baseUrl/tag/$section/feed',
        ]);
        
        if (segments.length > 1) {
          final subSection = segments[1];
          rssUrls.addAll([
            '$baseUrl/$section/$subSection/feed',
            '$baseUrl/category/$subSection/feed',
          ]);
        }
      }
    }

    return rssUrls;
  }

  /// Extract from existing HTML (e.g., WebView DOM)
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

  /// Common extraction logic
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

    String? jsonLdContent = _extractJsonLdContent(doc);

    _cleanDocument(doc);
    _removePaywallElements(doc);

    String? content;
    String? source = strategyName;

    if (jsonLdContent != null && jsonLdContent.trim().isNotEmpty) {
      content = jsonLdContent.trim();
      source = 'JSON-LD';
    }

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
      isPaywalled: isPaywalled || metadata.isSubscriberContent,
      source: metadata.isSubscriberContent ? 'Subscriber $source' : source,
      author: metadata.author,
      publishedDate: metadata.publishedDate,
    );
  }

  /// Enhanced metadata extraction
  _Metadata _extractMetadata(dom.Document doc, Uri pageUri) {
    final isSubscriberContent = _detectSubscriberMetadata(doc);
    final feedType = _extractFeedType(doc);
    
    return _Metadata(
      title: _extractTitle(doc),
      author: _extractAuthor(doc),
      publishedDate: _extractPublishedDate(doc),
      imageUrl: _extractMetaImage(doc, pageUri),
      isSubscriberContent: isSubscriberContent,
      feedType: feedType,
    );
  }

  /// Detect subscriber metadata
  bool _detectSubscriberMetadata(dom.Document doc) {
    final metaTags = [
      'meta[property="article:content_tier"]',
      'meta[name="subscription"]',
      'meta[property="og:content_tier"]',
    ];
    
    for (final selector in metaTags) {
      final meta = doc.querySelector(selector);
      if (meta != null) {
        final content = meta.attributes['content']?.toLowerCase() ?? '';
        if (content.contains('premium') || content.contains('subscriber')) {
          return true;
        }
      }
    }
    
    return false;
  }

  /// Extract feed type from document
  String? _extractFeedType(dom.Document doc) {
    final link = doc.querySelector('link[type="application/rss+xml"]');
    if (link != null) {
      final title = link.attributes['title']?.toLowerCase() ?? '';
      if (title.contains('subscriber') || title.contains('premium')) {
        return 'Subscriber RSS';
      }
    }
    return null;
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

  /// Build request headers
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

    final builtCookie =
        cookieHeaderBuilder != null ? await cookieHeaderBuilder!(url) : null;

    if (builtCookie != null && builtCookie.isNotEmpty) {
      headers['Cookie'] = builtCookie;
    } else if (_config.cookies != null && _config.cookies!.isNotEmpty) {
      final cookieString =
          _config.cookies!.entries.map((e) => '${e.key}=${e.value}').join('; ');
      headers['Cookie'] = cookieString;
    }

    if (_config.customHeaders != null) {
      headers.addAll(_config.customHeaders!);
    }

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
    final garbage = doc.querySelectorAll(
      'style,noscript,form,iframe,video,audio,svg,canvas',
    );
    for (final node in garbage) {
      node.remove();
    }

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
          continue;
        }
      }
    } catch (e) {
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

  /// Extract fallback text from document
  String? _extractFallbackText(dom.Document doc) {
    final allElements = doc.querySelectorAll('div, section, article, main');
    final candidates = <dom.Element>[];

    for (final el in allElements) {
      final text = el.text?.trim() ?? '';
      if (text.length > 150) {
        candidates.add(el);
      }
    }

    if (candidates.isNotEmpty) {
      candidates
          .sort((a, b) => (b.text?.length ?? 0).compareTo(a.text?.length ?? 0));
      final best = candidates.first;

      final blocks =
          best.querySelectorAll('p, h1, h2, h3, h4, h5, h6, li, blockquote');
      if (blocks.isNotEmpty) {
        return _normalizeWhitespace(_extractMainText(best));
      } else {
        return _normalizeWhitespace(best.text?.trim() ?? '');
      }
    }

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
}

/// Helper function to create a generic readability extractor
Readability4JExtended createReadabilityExtractor({
  Map<String, String>? cookies,
  Map<String, String>? customHeaders,
  Future<String?> Function(String url)? cookieHeaderBuilder,
  bool useMobileUserAgent = false,
  bool attemptAuthenticatedRss = true,
  Duration requestDelay = const Duration(seconds: 2),
  Duration pageLoadDelay = Duration.zero,
  int paginationPageLimit = 3,
  Map<String, String>? siteSpecificAuthHeaders,
  Map<String, String>? knownSubscriberFeeds,
  http.Client? client,
}) {
  final config = ReadabilityConfig(
    cookies: cookies,
    customHeaders: customHeaders,
    siteSpecificAuthHeaders: siteSpecificAuthHeaders,
    knownSubscriberFeeds: knownSubscriberFeeds,
    useMobileUserAgent: useMobileUserAgent,
    attemptAuthenticatedRss: attemptAuthenticatedRss,
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