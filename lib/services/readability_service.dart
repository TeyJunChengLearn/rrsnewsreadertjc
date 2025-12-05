// readability_service.dart - COMPLETE FIXED VERSION
import 'dart:convert';
import 'dart:io';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'android_webview_extractor.dart';

/// Check if text looks like a paywall message rather than article content
bool _isPaywallMessage(String text) {
  if (text.length > 500) return false; // Long text is probably real content

  const paywallPhrases = [
    'subscribe to read',
    'continue reading',
    'members only',
    'sign in to read',
    'login to continue',
    'become a member',
    'join now',
    'subscribe now',
    'unlock this article',
    'this article is for subscribers',
    'get unlimited access',
    'start your subscription',
  ];

  final lowerText = text.toLowerCase();

  // Check if the text is SHORT and primarily a paywall message
  // For short text (< 200 chars), it should be mostly just the paywall phrase
  if (text.length < 200) {
    return paywallPhrases.any((phrase) => lowerText.contains(phrase));
  }

  // For longer text, only flag it if it's PREDOMINANTLY about subscribing
  // (multiple paywall phrases or a very high density of paywall words)
  var paywallPhraseCount = 0;
  for (final phrase in paywallPhrases) {
    if (lowerText.contains(phrase)) {
      paywallPhraseCount++;
    }
  }

  // If it has 2+ paywall phrases, it's probably a paywall message
  return paywallPhraseCount >= 2;
}

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

  /// Check if content is full/complete, not just a preview/teaser
  bool get hasFullContent {
    if (!hasContent) return false;

    final text = mainText?.trim() ?? '';
    if (text.isEmpty) return false;

    final normalizedParagraphs =
        text.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'));
    final paragraphCount =
        normalizedParagraphs.where((p) => p.trim().isNotEmpty).length;
    final hasMultipleParagraphs = paragraphCount >= 2;
    final meetsLengthThreshold = text.length >= 200;
    final passesBasicCompleteness =
        meetsLengthThreshold || hasMultipleParagraphs;

    // For non-paywalled content, require a minimum length or multiple paragraphs
    if (isPaywalled != true) return passesBasicCompleteness;

    // For paywalled content, check if it's substantial (not a teaser)
    if (!passesBasicCompleteness) return false;

    // Lowered from 600 to 400 - some legitimate articles are short
    // Especially after paywall removal, we should trust the content more
    if (text.length < 400) return false;

    // Check for teaser indicators
    final lowerText = text.toLowerCase();
    final teaserPhrases = [
      'continue reading',
      'subscribe to read',
      'to continue reading',
      'login to read',
      'sign in to read',
      'premium content',
      'subscriber exclusive',
      'read the full article',
      'unlock full article',
    ];

    // Only reject if teaser phrase appears at the END of content (likely a prompt)
    // If it's in the middle, it might just be part of the article text
    final last200 = text.length > 200 ? lowerText.substring(lowerText.length - 200) : lowerText;
    var hasTeaserAtEnd = false;
    for (final phrase in teaserPhrases) {
      if (last200.contains(phrase)) {
        hasTeaserAtEnd = true;
        break;
      }
    }

    if (hasTeaserAtEnd && text.length < 800) {
      return false;  // Teaser phrase at end + short text = likely preview
    }

    // Check if ends with ellipsis (but only if text is short)
    if ((text.endsWith('...') || text.endsWith('…')) && text.length < 800) {
      return false;
    }

    // If paywalled but substantial and no clear teaser indicators, consider it full
    return true;
  }

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
  final Duration webViewSnapshotInterval;
  final Duration webViewMaxSnapshotDuration;
  final Duration webViewRenderTimeoutBuffer;
  final int webViewMaxSnapshots;
  final double webViewChangeThreshold;
  final int paginationPageLimit;
  final bool useMobileUserAgent;
  final String userAgent;
  final Map<String, String> siteSpecificAuthHeaders;
  final Map<String, String> knownSubscriberFeeds;
  final Map<String, bool> cookieAuthOverrides;
  final Map<String, List<String>> siteSpecificAuthCookiePatterns;

  ReadabilityConfig({
    Map<String, String>? cookies,
    Map<String, String>? customHeaders,
    List<String>? paywallKeywords,
    bool? attemptRssFallback,
    bool? attemptAuthenticatedRss,
    Duration? requestDelay,
    Duration? pageLoadDelay,
    Duration? webViewSnapshotInterval,
    Duration? webViewMaxSnapshotDuration,
    Duration? webViewRenderTimeoutBuffer,
    int? webViewMaxSnapshots,
    double? webViewChangeThreshold,
    int? paginationPageLimit,
    bool? useMobileUserAgent,
    String? userAgent,
    Map<String, String>? siteSpecificAuthHeaders,
    Map<String, String>? knownSubscriberFeeds,
    Map<String, bool>? cookieAuthOverrides,
    Map<String, List<String>>? siteSpecificAuthCookiePatterns,
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
        pageLoadDelay = pageLoadDelay ?? const Duration(seconds: 3),
        webViewSnapshotInterval =
            webViewSnapshotInterval ?? const Duration(seconds: 2),
        webViewMaxSnapshotDuration =
            webViewMaxSnapshotDuration ?? const Duration(seconds: 12),
        webViewRenderTimeoutBuffer =
            webViewRenderTimeoutBuffer ?? const Duration(seconds: 20),
        webViewMaxSnapshots = webViewMaxSnapshots ?? 3,
        webViewChangeThreshold = webViewChangeThreshold ?? 0.02,
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
            },
        cookieAuthOverrides = cookieAuthOverrides ?? {},
        siteSpecificAuthCookiePatterns = siteSpecificAuthCookiePatterns ?? {};
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
  final Map<String, Future<ArticleReadabilityResult?>> _inflightExtractions = {};
  final Future<String?> Function(String url)? cookieHeaderBuilder;
  final AndroidWebViewExtractor? _webViewExtractor;
  final Map<String, bool> _feedSubscriptionStatus = {};

  Readability4JExtended({
    http.Client? client,
    ReadabilityConfig? config,
    this.cookieHeaderBuilder,
    AndroidWebViewExtractor? webViewExtractor,
  })  : _client = client ?? http.Client(),
        _config = config ?? ReadabilityConfig(),
        _rssParser = RssFeedParser(
          client: client,
          siteSpecificAuthHeaders: config?.siteSpecificAuthHeaders,
          cookieHeaderBuilder: cookieHeaderBuilder,
        ),
        _webViewExtractor = webViewExtractor;

  /// Main extraction method with subscription awareness
  Future<ArticleReadabilityResult?> extractMainContent(String url) async {
    final inFlight = _inflightExtractions[url];
    if (inFlight != null) {
      print('🔄 Reusing in-flight readability extraction for $url');
      return inFlight;
    }

    final future = _extractMainContentInternal(url);
    _inflightExtractions[url] = future;

    try {
      return await future;
    } finally {
      _inflightExtractions.remove(url);
    }
  }

  Future<ArticleReadabilityResult?> _extractMainContentInternal(String url) async {
    try {
      await _respectRateLimit(url);

      // Check if we have authentication cookies for this domain
      final hasCookies = await _hasAuthCookies(url);

      // For authenticated users, prioritize WebView rendering to get full JS-rendered content
      final strategies = <Future<ArticleReadabilityResult?>>[];

      if (hasCookies && _webViewExtractor != null) {
        // Authenticated: WebView FIRST to get subscriber content
        strategies.addAll([
          _extractWithAndroidWebView(
            url,
            forceAuthenticatedDelay: hasCookies,
          ),
          _extractFromKnownSubscriberFeeds(url),
          _extractWithDefaultStrategy(url),
          if (_config.attemptAuthenticatedRss) _extractFromAuthenticatedRssStrategy(url),
          if (_config.useMobileUserAgent) _extractWithMobileStrategy(url),
          if (_config.attemptRssFallback) _extractFromRssStrategy(url),
        ]);
      } else {
        // Not authenticated: standard extraction order
        strategies.addAll([
          if (_webViewExtractor != null)
            _extractWithAndroidWebView(
              url,
              forceAuthenticatedDelay: hasCookies,
            ),
          _extractWithDefaultStrategy(url),
          _extractFromKnownSubscriberFeeds(url),
          if (_config.useMobileUserAgent) _extractWithMobileStrategy(url),
          if (_config.attemptRssFallback) _extractFromRssStrategy(url),
          if (_config.attemptAuthenticatedRss) _extractFromAuthenticatedRssStrategy(url),
        ]);
      }

      ArticleReadabilityResult? bestResult;
      var bestLength = 0;

      for (final strategy in strategies) {
        try {
          final result = await strategy;
          if (result != null && result.hasContent) {
            final textLen = result.mainText?.length ?? 0;
            final isPaywalled = result.isPaywalled ?? false;
            final source = result.source ?? 'Unknown';

            print('Strategy "$source" extracted $textLen chars (paywalled: $isPaywalled, full: ${result.hasFullContent})');

            // Priority 1: If we found full content (not a teaser), return immediately
            if (result.hasFullContent) {
              print('✓ Returning full content from "$source"');
              return result;
            }

            // Priority 2: For authenticated users, keep tracking longest content
            if (hasCookies) {
              if (textLen > bestLength) {
                bestLength = textLen;
                bestResult = result;
                print('  Keeping as best result (authenticated user)');

                // If we got substantial content (>500 chars for authenticated users), accept it
                // Lowered from 800 to 500 since we have cookies and paywall removal
                if (textLen > 500) {
                  print('✓ Substantial content found (authenticated), returning from "$source"');
                  return result;
                }
              }
            } else {
              // Priority 3: Not authenticated, keep best partial result
              if (textLen > bestLength) {
                bestLength = textLen;
                bestResult = result;
                print('  Keeping as best partial result');
              }
            }
          }
        } catch (e) {
          continue;
        }
      }

      // Return best result we found
      if (bestResult != null) {
        final resultLen = bestResult.mainText?.length ?? 0;
        print('⚠ No full content found, returning best partial ($resultLen chars from ${bestResult.source})');
      }
      return bestResult;
    } catch (e) {
      print('Error extracting content from $url: $e');
      return null;
    }
  }

  /// Check if we have authentication cookies for this URL
  Future<bool> _hasAuthCookies(String url) async {
    String? cookies;

    try {
      if (cookieHeaderBuilder != null) {
        cookies = await cookieHeaderBuilder!(url);
      }

      cookies ??= _config.customHeaders?['Cookie'];

      if ((cookies == null || cookies.isEmpty) &&
          _config.cookies != null &&
          _config.cookies!.isNotEmpty) {
        cookies =
            _config.cookies!.entries.map((e) => '${e.key}=${e.value}').join('; ');
      }

      if (cookies == null || cookies.trim().isEmpty) {
        print('🔐 No cookies found for $url');
        return false;
      }

      final normalizedCookies = cookies.trim();

      // Check for common auth cookie patterns
      final lowerCookies = normalizedCookies.toLowerCase();
      final authPatterns = <String>[
        'session',
        'auth',
        'token',
        'logged',
        'user',
        'member',
        'subscriber',
        'premium',
      ];

      final host = Uri.tryParse(url)?.host;

      if (host != null && _config.siteSpecificAuthCookiePatterns.isNotEmpty) {
        for (final entry in _config.siteSpecificAuthCookiePatterns.entries) {
          if (host == entry.key || host.endsWith(entry.key)) {
            authPatterns
                .addAll(entry.value.map((pattern) => pattern.toLowerCase()));
          }
        }
      }

      final hasAuth = authPatterns.any((pattern) => lowerCookies.contains(pattern));
      final cookiePreview = normalizedCookies
          .substring(0, normalizedCookies.length > 100 ? 100 : normalizedCookies.length);
      if (hasAuth) {
        print('🔐 Auth-like cookies detected for $url');
        print('   Cookie preview: $cookiePreview${cookies.length > 100 ? '...' : ''}');
      } else {
        print('🔐 Cookies present without auth patterns for $url');
        print('   Cookie preview: $cookiePreview${cookies.length > 100 ? '...' : ''}');
      }

      bool? override;
      if (host != null && _config.cookieAuthOverrides.isNotEmpty) {
        for (final entry in _config.cookieAuthOverrides.entries) {
          if (host == entry.key || host.endsWith(entry.key)) {
            override = entry.value;
            break;
          }
        }
      }

      if (override != null) {
        print('🔐 Cookie auth override for $host: ${override ? 'enabled' : 'disabled'}');
        return override;
      }

      print('🔐 Cookies found for $url, treating as authenticated by default');
      return true;
    } catch (e) {
      print('🔐 Error checking cookies: $e');
      return false;
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

  /// Android-only strategy: render the page in an off-screen WebView so any
  /// authenticated session cookies and JavaScript-rendered content are
  /// captured before running Readability.
  Future<ArticleReadabilityResult?> _extractWithAndroidWebView(
    String url, {
    bool forceAuthenticatedDelay = false,
  }) async {
    try {
      final headers =
          await _buildRequestHeaders(url, mobile: _config.useMobileUserAgent);

      // Check if we have authentication cookies - give more time for authenticated pages
      final hasCookies =
          forceAuthenticatedDelay || (headers['Cookie']?.trim().isNotEmpty ?? false);
      final loadDelay = hasCookies
          ? _config.pageLoadDelay + const Duration(seconds: 3)
          : _config.pageLoadDelay;

      final html = await _captureStabilizedHtml(
        url: url,
        headers: headers,
        initialDelay: loadDelay,
      );

      ArticleReadabilityResult? bestResult;

      if (html != null && html.isNotEmpty) {
        bestResult = await extractFromHtml(
          url,
          html,
          strategyName: hasCookies
              ? 'Authenticated WebView'
              : 'Android WebView',
        );
      }

      final isTruncatedResult = bestResult == null ||
          (bestResult.mainText?.length ?? 0) < 1200 ||
          !bestResult.hasFullContent;
      final allowRetry = _config.webViewMaxSnapshots > 1;

      if (isTruncatedResult && allowRetry) {
        final retryHtml = await _captureStabilizedHtml(
          url: url,
          headers: headers,
          initialDelay: loadDelay + const Duration(seconds: 5),
          maxDurationOverride:
              _config.webViewMaxSnapshotDuration + const Duration(seconds: 8),
          maxSnapshotsOverride: _config.webViewMaxSnapshots + 2,
        );

        if (retryHtml != null && retryHtml.isNotEmpty) {
          final retryResult = await extractFromHtml(
            url,
            retryHtml,
            strategyName: hasCookies
                ? 'Authenticated WebView (retry)'
                : 'Android WebView (retry)',
          );

          if (retryResult != null && retryResult.hasContent) {
            final retryLength = retryResult.mainText?.length ?? 0;
            final bestLength = bestResult?.mainText?.length ?? 0;

            if (bestResult == null || retryLength > bestLength) {
              bestResult = retryResult;
            }
          }
        }
      }

      return bestResult;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _captureStabilizedHtml({
    required String url,
    required Map<String, String> headers,
    required Duration initialDelay,
    Duration? maxDurationOverride,
    int? maxSnapshotsOverride,
  }) async {
    if (_webViewExtractor == null) return null;

    final interval = _config.webViewSnapshotInterval;
    final maxDuration =
        maxDurationOverride ?? _config.webViewMaxSnapshotDuration;
    final maxSnapshots = maxSnapshotsOverride ?? _config.webViewMaxSnapshots;
    final stopwatch = Stopwatch()..start();

    String? lastHtml;
    String? stableHtml;

    for (var attempt = 0; attempt < maxSnapshots; attempt++) {
      final snapshotDelay = initialDelay + (interval * attempt);

      final html = await _webViewExtractor!.renderPage(
        url,
        timeout: snapshotDelay + _config.webViewRenderTimeoutBuffer,
        postLoadDelay: snapshotDelay,
        userAgent: headers['User-Agent'],
        cookieHeader: headers['Cookie'],
      );

      if (html == null || html.isEmpty) {
        if (stopwatch.elapsed >= maxDuration) break;
        continue;
      }

      if (lastHtml != null && !_hasSignificantDomChange(lastHtml, html)) {
        stableHtml = html;
        break;
      }

      stableHtml = html;
      lastHtml = html;

      final elapsed = stopwatch.elapsed;
      if (attempt == maxSnapshots - 1 || elapsed >= maxDuration) {
        break;
      }

      final remaining = maxDuration - elapsed;
      final waitTime = remaining < interval ? remaining : interval;
      if (waitTime > Duration.zero) {
        await Future.delayed(waitTime);
      }
    }

    return stableHtml;
  }

  bool _hasSignificantDomChange(String previous, String current) {
    if (previous.isEmpty && current.isNotEmpty) return true;

    final lengthDiff = (previous.length - current.length).abs();
    final avgLength = (previous.length + current.length) / 2;

    if (avgLength == 0) return false;

    return (lengthDiff / avgLength) > _config.webViewChangeThreshold;
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

    // IMPORTANT: Try to extract hidden subscriber content BEFORE cleaning
    // Many paywalled sites hide the full content in CSS-hidden elements
    String? hiddenSubscriberContent;
    if (isPaywalled || metadata.isSubscriberContent) {
      hiddenSubscriberContent = _extractFromHiddenElements(doc.body ?? doc.documentElement!);
    }

    _cleanDocument(doc);
    _removePaywallElements(doc);

    String? content;
    String? source = strategyName;

    // Priority 1: JSON-LD structured data
    if (jsonLdContent != null && jsonLdContent.trim().isNotEmpty) {
      content = jsonLdContent.trim();
      source = 'JSON-LD';
    }

    // Priority 2: Hidden subscriber content (often the most complete)
    if (hiddenSubscriberContent != null &&
        hiddenSubscriberContent.length > (content?.length ?? 0)) {
      content = hiddenSubscriberContent;
      source = 'Hidden Subscriber Content';
    }

    // Priority 3: Regular article extraction
    if (content == null) {
      final articleRoot = _findArticleRoot(doc);
      if (articleRoot != null) {
        final text = _extractMainText(articleRoot);
        content = _normalizeWhitespace(text);

        // If content looks truncated or is too short, try hidden content
        final contentTooShort = content.isEmpty || content.length < 400;
        if (_isContentTruncated(content) || contentTooShort) {
          final hiddenContent = _extractHiddenContent(articleRoot);
          if (hiddenContent != null && hiddenContent.length > content.length) {
            content = hiddenContent;
            source = 'Hidden Content';
          }
        }
      }
    }

    // Priority 4: Fallback text extraction
    if (content == null || content.isEmpty) {
      content = _extractFallbackText(doc);
    }

    // If we found hidden subscriber content earlier but it was shorter,
    // use it now if the extracted content is still too short
    if ((content == null || content.length < 400) &&
        hiddenSubscriberContent != null &&
        hiddenSubscriberContent.length > 300) {
      content = hiddenSubscriberContent;
      source = 'Hidden Subscriber Content';
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
          ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'
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

  /// Remove paywall-specific elements (but preserve those with actual content)
  void _removePaywallElements(dom.Document doc) {
    // Only remove obvious paywall UI elements, not content containers
    final paywallUISelectors = [
      '.paywall-message',
      '.paywall-overlay',
      '.paywall-banner',
      '.subscribe-prompt',
      '.subscribe-button',
      '.register-prompt',
      '.login-prompt',
      '.membership-prompt',
      '[class*="paywall-popup"]',
      '[class*="subscribe-modal"]',
      '.blurred-overlay',
      '.content-gate',
    ];

    for (final selector in paywallUISelectors) {
      try {
        final elements = doc.querySelectorAll(selector);
        for (final el in elements) {
          // Only remove if it's actually a UI element (short text)
          final text = el.text?.trim() ?? '';
          if (text.length < 300 || _isPaywallMessage(text)) {
            el.remove();
          }
        }
      } catch (e) {
        continue;
      }
    }
  }

  /// Extract content from JSON-LD metadata
  String? _extractJsonLdContent(dom.Document doc) {
    try {
      final scripts =
          doc.querySelectorAll('script[type="application/ld+json"]');

      String? bestBody;

      for (final script in scripts) {
        final content = script.text?.trim();
        if (content == null || content.isEmpty) continue;

        try {
          final json = jsonDecode(content);
          final bodies = _collectJsonLdBodies(json);

          for (final body in bodies) {
            if (body.trim().isEmpty) continue;
            if (bestBody == null || body.length > bestBody.length) {
              bestBody = body.trim();
            }
          }
        } catch (_) {
          continue;
        }
      }

      return bestBody;
    } catch (_) {
      return null;
    }
  }

  /// Collect possible article bodies from common JSON-LD shapes (object, list,
  /// @graph, nested mainEntity, etc.). Returns all candidates so the caller can
  /// pick the longest.
  List<String> _collectJsonLdBodies(dynamic json) {
    final bodies = <String>[];

    void handleNode(dynamic node) {
      if (node is Map<String, dynamic>) {
        final type = node['@type'];
        final types = <String>[];

        if (type is String) {
          types.add(type.toLowerCase());
        } else if (type is List) {
          types.addAll(
              type.whereType<String>().map((t) => t.toLowerCase()).toList());
        }

        bool isArticleType() {
          return types.any((t) =>
              t.contains('newsarticle') ||
              t.contains('article') ||
              t.contains('blogposting'));
        }

        String? normalizeBody(dynamic body) {
          if (body == null) return null;
          if (body is String) return body.trim();
          if (body is List) {
            final parts = body
                .where((element) => element is String && element.trim().isNotEmpty)
                .cast<String>()
                .toList();
            if (parts.isNotEmpty) return parts.join('\n').trim();
          }
          if (body is Map<String, dynamic>) {
            final value = body['@value'] ?? body['text'] ?? body['content'];
            if (value is String && value.trim().isNotEmpty) {
              return value.trim();
            }
          }
          return null;
        }

        final mainEntity = node['mainEntity'];
        final candidates = [
          normalizeBody(node['articleBody']),
          normalizeBody(node['text']),
          normalizeBody(node['description']),
          if (mainEntity is Map<String, dynamic>)
            normalizeBody(
                mainEntity['articleBody'] ?? mainEntity['text'] ?? mainEntity),
        ].whereType<String>();

        for (final body in candidates) {
          // Prefer article-typed nodes, but allow long text from others if no
          // explicit type is present.
          if (isArticleType() || body.length > 180) {
            bodies.add(body);
          }
        }

        // Dive into nested structures: mainEntity, graph lists, or array
        // properties that may hold additional article bodies.
        if (mainEntity != null) {
          handleNode(mainEntity);
        }

        if (node['@graph'] is List) {
          for (final item in node['@graph']) {
            handleNode(item);
          }
        }
      } else if (node is List) {
        for (final item in node) {
          handleNode(item);
        }
      }
    }

    handleNode(json);
    return bodies;
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

  /// Extract hidden content from data attributes and CSS-hidden elements
  String? _extractHiddenContent(dom.Element root) {
    // Try data attributes first
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

    // Try CSS-hidden elements that might contain full subscriber content
    final hiddenContent = _extractFromHiddenElements(root);
    if (hiddenContent != null && hiddenContent.length > 100) {
      return hiddenContent;
    }

    return null;
  }

  /// Extract content from CSS-hidden elements (display:none, visibility:hidden, etc.)
  String? _extractFromHiddenElements(dom.Element root) {
    // Look for elements that are commonly used to hide subscriber content
    final hiddenSelectors = [
      // Inline style hiding
      '[style*="display: none"]',
      '[style*="display:none"]',
      '[style*="visibility: hidden"]',
      '[style*="visibility:hidden"]',
      '[style*="opacity: 0"]',
      '[style*="opacity:0"]',
      '[style*="height: 0"]',
      '[style*="height:0"]',

      // Generic classes
      '.hidden-content',
      '.locked-content',
      '.premium-content',
      '.subscriber-content',
      '.member-content',
      '.paywalled-content',
      '.article-content-premium',
      '.full-article-hidden',
      '[aria-hidden="true"]',
      '.js-hidden',
      '.no-js-hide',

      // Malaysiakini specific
      '.subscriber-only',
      '.premium-article-content',
      '[data-subscriber="true"]',
      '[data-premium="true"]',

      // Common subscription site patterns
      '.paywall-content',
      '.gated-content',
      '.registration-required',
      '.auth-required',
      '.logged-in-content',
      '[data-auth-required]',
      '[data-subscription-required]',

      // Data attributes that might hold full content
      '[data-full-content]',
      '[data-article-content]',
      '[data-body-text]',
    ];

    String? bestContent;
    var bestLength = 0;

    for (final selector in hiddenSelectors) {
      try {
        final elements = root.querySelectorAll(selector);
        for (final el in elements) {
          // First check if the entire element is just a paywall message
          final fullText = el.text?.trim() ?? '';
          if (fullText.isNotEmpty && _isPaywallMessage(fullText)) {
            continue; // Skip entire element if it's a paywall message
          }

          // Extract text from paragraphs within hidden elements
          final paragraphs = el.querySelectorAll('p');
          if (paragraphs.isNotEmpty) {
            final buffer = StringBuffer();
            var hasRealContent = false;

            for (final p in paragraphs) {
              final text = p.text?.trim() ?? '';
              if (text.isEmpty) continue;

              // Skip if this specific paragraph is a paywall message
              if (_isPaywallMessage(text)) continue;

              if (buffer.isNotEmpty) buffer.write('\n\n');
              buffer.write(text);
              hasRealContent = true;
            }

            if (hasRealContent) {
              final extracted = buffer.toString();
              if (extracted.length > bestLength) {
                bestLength = extracted.length;
                bestContent = extracted;
              }
            }
          } else {
            // No paragraphs, just get the text
            if (fullText.length > bestLength && !_isPaywallMessage(fullText)) {
              bestLength = fullText.length;
              bestContent = fullText;
            }
          }
        }
      } catch (e) {
        // Selector might not work, continue with next one
        continue;
      }
    }

    return bestContent != null && bestContent.isNotEmpty
        ? _normalizeWhitespace(bestContent)
        : null;
  }

  /// Find the main article root element
  dom.Element? _findArticleRoot(dom.Document doc) {
    // Site-specific selectors for known subscription sites
    final siteSpecificSelectors = _getSiteSpecificSelectors(doc);
    if (siteSpecificSelectors.isNotEmpty) {
      for (final selector in siteSpecificSelectors) {
        try {
          final elements = doc.querySelectorAll(selector);
          if (elements.isNotEmpty) {
            // Return the one with most content
            dom.Element? best;
            var bestScore = 0;
            for (final el in elements) {
              final score = _calculateElementScore(el);
              if (score > bestScore) {
                bestScore = score;
                best = el;
              }
            }
            if (best != null && bestScore >= 30) {
              return best;
            }
          }
        } catch (e) {
          continue;
        }
      }
    }

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

      // Skip blocks that are inside hidden/paywall elements
      if (_isInsideHiddenOrPaywallElement(block)) continue;

      // Skip if it's a paywall message
      if (_isPaywallMessage(text)) continue;

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

  /// Get site-specific content selectors based on the page URL/domain
  List<String> _getSiteSpecificSelectors(dom.Document doc) {
    // Try to detect site from meta tags or URL patterns
    final ogSiteName = doc.querySelector('meta[property="og:site_name"]')?.attributes['content']?.toLowerCase() ?? '';
    final url = doc.querySelector('link[rel="canonical"]')?.attributes['href']?.toLowerCase() ?? '';
    final domain = doc.querySelector('meta[property="og:url"]')?.attributes['content']?.toLowerCase() ?? '';

    final siteIdentifier = '$ogSiteName $url $domain'.toLowerCase();

    // Malaysiakini
    if (siteIdentifier.contains('malaysiakini') || siteIdentifier.contains('mkini')) {
      return [
        '.article-content',
        '.article__content',
        '.content-body',
        '.story-content',
        '#article-content',
        '[itemprop="articleBody"]',
        '.field-name-body',
        '.article-wrapper',
      ];
    }

    // The Star (Malaysia)
    if (siteIdentifier.contains('thestar') && siteIdentifier.contains('.my')) {
      return [
        '.story-body',
        '.article-body',
        '[itemprop="articleBody"]',
        '.story__body',
      ];
    }

    // New York Times
    if (siteIdentifier.contains('nytimes')) {
      return [
        '.article-body',
        '[name="articleBody"]',
        'section[name="articleBody"]',
        '.StoryBodyCompanionColumn',
      ];
    }

    // Washington Post
    if (siteIdentifier.contains('washingtonpost')) {
      return [
        '.article-body',
        '[data-qa="article-body"]',
        '.paywall-window',
      ];
    }

    // Medium
    if (siteIdentifier.contains('medium.com')) {
      return [
        'article section',
        '[data-selectable-paragraph]',
        '.postArticle-content',
      ];
    }

    // Bloomberg
    if (siteIdentifier.contains('bloomberg')) {
      return [
        '.article-body',
        '[data-component="article-body"]',
        '.body-content',
      ];
    }

    // Wall Street Journal
    if (siteIdentifier.contains('wsj.com')) {
      return [
        '.article-content',
        '[class*="article-body"]',
        '.wsj-snippet-body',
      ];
    }

    // Financial Times
    if (siteIdentifier.contains('ft.com')) {
      return [
        '.article__content-body',
        '[data-trackable="article-body"]',
        '.article-body',
      ];
    }

    // The Guardian
    if (siteIdentifier.contains('theguardian')) {
      return [
        '[data-gu-name="body"]',
        '.article-body-commercial-selector',
        '.content__article-body',
      ];
    }

    // Reuters
    if (siteIdentifier.contains('reuters')) {
      return [
        '[data-testid="ArticleBody"]',
        '.article-body',
        '.StandardArticleBody_body',
      ];
    }

    return [];
  }

  /// Check if an element is inside a hidden or paywall container
  bool _isInsideHiddenOrPaywallElement(dom.Element element) {
    var current = element.parent;
    while (current != null) {
      // Check for hidden styles
      final style = current.attributes['style']?.toLowerCase() ?? '';
      if (style.contains('display:none') ||
          style.contains('display: none') ||
          style.contains('visibility:hidden') ||
          style.contains('visibility: hidden')) {
        return true;
      }

      // Check for paywall-related classes (but only UI elements, not content containers)
      final className = current.className.toLowerCase();
      final paywallUIClasses = [
        'paywall-message',
        'paywall-overlay',
        'subscribe-prompt',
        'subscribe-button',
      ];

      for (final paywallClass in paywallUIClasses) {
        if (className.contains(paywallClass)) {
          return true;
        }
      }

      current = current.parent;
    }
    return false;
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
  Duration pageLoadDelay = const Duration(seconds: 3),
  Duration webViewSnapshotInterval = const Duration(seconds: 2),
  Duration webViewMaxSnapshotDuration = const Duration(seconds: 12),
  Duration webViewRenderTimeoutBuffer = const Duration(seconds: 20),
  int webViewMaxSnapshots = 3,
  double webViewChangeThreshold = 0.02,
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
    webViewSnapshotInterval: webViewSnapshotInterval,
    webViewMaxSnapshotDuration: webViewMaxSnapshotDuration,
    webViewRenderTimeoutBuffer: webViewRenderTimeoutBuffer,
    webViewMaxSnapshots: webViewMaxSnapshots,
    webViewChangeThreshold: webViewChangeThreshold,
    paginationPageLimit: paginationPageLimit,
  );

  return Readability4JExtended(
    client: client,
    config: config,
    cookieHeaderBuilder: cookieHeaderBuilder,
  );
}