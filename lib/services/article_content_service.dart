import '../models/feed_item.dart';
import 'article_dao.dart';
import 'readability_service.dart';

class ArticleContentService {
  final Readability4JExtended readability;
  final ArticleDao articleDao;

  ArticleContentService({required this.readability, required this.articleDao});

  /// Fetches main article text/images for any FeedItem missing them.
  /// Returns a map of article id -> extracted content for rows that were updated.
  ///
  /// Automatically detects paywalled sites and uses WebView extraction with delays.
  /// Set allowWebView=false for background tasks where WebView is unavailable.
  Future<Map<String, ArticleReadabilityResult>> backfillMissingContent(
    List<FeedItem> items, {
    int defaultDelayMs = 2000,
    bool allowWebView = true,
  }) async {
    final updated = <String, ArticleReadabilityResult>{};

    for (final item in items) {
      if (item.link.isEmpty) continue;
      final existingText = (item.mainText ?? '').trim();
      final needsBetterText = _looksLikeTeaser(existingText);
      final needsImage = (item.imageUrl ?? '').trim().isEmpty;

      if (!needsBetterText && !needsImage) continue;

      // Auto-detect if this URL requires WebView extraction (paywalled sites)
      // Only use WebView if allowed (not available in background tasks)
      final shouldUseWebView = allowWebView && _isPaywalledDomain(item.link);
      final delayMs = shouldUseWebView ? _getOptimalDelay(item.link) : 0;

      print('🔍 Enriching: ${item.title}');
      print('   URL: ${item.link}');
      print('   WebView: $shouldUseWebView, Delay: ${delayMs}ms');

      final content = await readability.extractMainContent(
        item.link,
        useWebView: shouldUseWebView,
        delayMs: delayMs,
      );

      if (content == null) {
        print('   ❌ Extraction failed (returned null)');
        continue;
      }

      final extractedLength = content.mainText?.trim().length ?? 0;
      print('   ✓ Extracted ${extractedLength} chars (source: ${content.source})');

      if (extractedLength < 150) {
        print('   ⚠️ Content too short (< 150 chars), likely incomplete');
      }

      final updates = <String, String?>{};
      final trimmedText = content.mainText?.trim();
      if ((needsBetterText || needsImage) && (trimmedText ?? '').isNotEmpty) {
        final longerThanExisting =
            (existingText.isEmpty) || ((trimmedText?.length ?? 0) > existingText.length);
        if (longerThanExisting || needsBetterText) {
          updates['mainText'] = trimmedText;
        }
      }

      final leadImage = content.imageUrl?.trim();
      if (needsImage && (leadImage ?? '').isNotEmpty) {
        updates['imageUrl'] = leadImage;
      }

      if (updates.isEmpty) continue;

      await articleDao.updateContent(item.id, updates['mainText'], updates['imageUrl']);
      updated[item.id] = ArticleReadabilityResult(
        mainText: updates['mainText'],
        imageUrl: updates['imageUrl'],
        pageTitle: content.pageTitle,
      );
    }

    return updated;
  }

  Future<void> saveExtractedContent({
    required String articleId,
    String? mainText,
    String? imageUrl,
  }) async {
    final trimmedText = mainText?.trim() ?? '';
    final trimmedImage = imageUrl?.trim() ?? '';

    if (trimmedText.isEmpty && trimmedImage.isEmpty) return;

    final existing = await articleDao.findById(articleId);
    if (existing == null) return;

    final updates = <String, String?>{};
    final currentText = (existing.mainText ?? '').trim();
    if (trimmedText.isNotEmpty) {
      final needsBetterText =
          _looksLikeTeaser(currentText) || trimmedText.length > currentText.length;
      if (needsBetterText) {
        updates['mainText'] = trimmedText;
      }
    }

    final hasImage = (existing.imageUrl ?? '').trim().isNotEmpty;
    if (!hasImage && trimmedImage.isNotEmpty) {
      updates['imageUrl'] = trimmedImage;
    }

    if (updates.isEmpty) return;

    await articleDao.updateContent(
      articleId,
      updates['mainText'],
      updates['imageUrl'],
    );
  }
}

bool _looksLikeTeaser(String? text) {
  if (text == null) return true;
  final trimmed = text.trim();
  if (trimmed.isEmpty) return true;

  // Check length - content under 500 chars is likely just RSS description
  if (trimmed.length < 500) return true;

  // Check for paywall/teaser indicators
  final lower = trimmed.toLowerCase();
  const patterns = [
    'continue reading',
    'subscribe to read',
    'to continue reading',
    'login to read',
    'premium content',
  ];

  if (trimmed.endsWith('...') || trimmed.endsWith('…')) return true;

  for (final pattern in patterns) {
    if (lower.contains(pattern)) return true;
  }

  return false;
}

/// Detects if a URL is from a known paywalled domain or Javascript-heavy site
/// that requires WebView extraction with delays.
/// Returns true for sites like Malaysiakini, NYT, WSJ, Harian Metro, etc.
bool _isPaywalledDomain(String url) {
  try {
    final uri = Uri.parse(url);
    final host = uri.host.toLowerCase();

    // List of known paywalled domains and Javascript-heavy sites
    const paywalledDomains = [
      'malaysiakini.com',
      'nytimes.com',
      'wsj.com',
      'bloomberg.com',
      'ft.com',
      'economist.com',
      'washingtonpost.com',
      'medium.com',
      'wired.com',
      'theatlantic.com',
      'hmetro.com.my',           // Harian Metro - Javascript-heavy
      'harakahdaily.net',        // Javascript-heavy Malaysian news
      'sinchew.com.my',          // Sin Chew Daily - Javascript-heavy
      'orientaldaily.com.my',    // Oriental Daily - Javascript-heavy
      'thestar.com.my',          // The Star - Some articles paywalled
      'freemalaysiatoday.com',   // Javascript-heavy
    ];

    for (final domain in paywalledDomains) {
      if (host.contains(domain)) {
        return true;
      }
    }

    return false;
  } catch (_) {
    return false;
  }
}

/// Returns the optimal WebView delay for a given URL
/// Different sites require different delays for JavaScript to fully load
int _getOptimalDelay(String url) {
  try {
    final uri = Uri.parse(url);
    final host = uri.host.toLowerCase();

    // Malaysian news sites with heavy JavaScript/authentication
    // These need longer delays to fully load subscriber content
    // Increased delays to ensure full content capture
    const heavyJsSites = {
      'malaysiakini.com': 8000,      // Malaysiakini needs 8 seconds for auth and full content
      'mkini.bz': 8000,               // Malaysiakini short domain
      'hmetro.com.my': 7000,          // Harian Metro - increased for full content
      'harakahdaily.net': 7000,       // Harakah Daily - increased for full content
      'sinchew.com.my': 7000,         // Sin Chew Daily - increased for full content
      'orientaldaily.com.my': 7000,   // Oriental Daily - increased for full content
      'freemalaysiatoday.com': 6000,  // FMT - increased for full content
    };

    // International paywall sites
    // These also need extra time for authentication checks
    // Increased delays to ensure full content capture
    const internationalPaywalls = {
      'nytimes.com': 7000,        // Increased for full content
      'wsj.com': 7000,            // Increased for full content
      'bloomberg.com': 6000,      // Increased for full content
      'ft.com': 7000,             // Increased for full content
      'economist.com': 6000,      // Increased for full content
      'washingtonpost.com': 6000, // Increased for full content
      'medium.com': 5000,         // Increased for full content
      'wired.com': 5000,          // Increased for full content
      'theatlantic.com': 5000,    // Increased for full content
    };

    // Check Malaysian sites first (higher priority)
    for (final entry in heavyJsSites.entries) {
      if (host.contains(entry.key)) {
        return entry.value;
      }
    }

    // Check international sites
    for (final entry in internationalPaywalls.entries) {
      if (host.contains(entry.key)) {
        return entry.value;
      }
    }

    // Default delay for other paywalled sites (increased for better content capture)
    return 5000;
  } catch (_) {
    return 3000; // Default 3 seconds
  }
}