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
        print('   ⚠️ WARNING: Content too short (< 150 chars), likely incomplete or paywalled');
        print('   ⚠️ This may indicate cookies are not working or content not fully loaded');
      } else if (extractedLength < 500) {
        print('   ℹ️ Content short (< 500 chars), may be just RSS teaser rather than full article');
      } else {
        print('   ✓ Content length looks good (${extractedLength} chars)');
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
/// Focuses on Malaysian news sites. Other international sites use dynamic detection.
bool _isPaywalledDomain(String url) {
  try {
    final uri = Uri.parse(url);
    final host = uri.host.toLowerCase();

    // Malaysian paywalled/Javascript-heavy sites (need WebView)
    const malaysianPaywalledSites = [
      'malaysiakini.com',
      'mkini.bz',                // Malaysiakini short domain
      'hmetro.com.my',           // Harian Metro
      'harakahdaily.net',        // Harakah Daily
      'sinchew.com.my',          // Sin Chew Daily
      'orientaldaily.com.my',    // Oriental Daily
      'thestar.com.my',          // The Star
      'freemalaysiatoday.com',   // FMT
    ];

    // Common international paywalled sites (for dynamic detection)
    const internationalPaywalledSites = [
      'nytimes.com',
      'wsj.com',
      'bloomberg.com',
      'ft.com',
      'economist.com',
      'washingtonpost.com',
      'medium.com',
      'wired.com',
      'theatlantic.com',
    ];

    // Check Malaysian sites
    for (final domain in malaysianPaywalledSites) {
      if (host.contains(domain)) {
        return true;
      }
    }

    // Check international sites
    for (final domain in internationalPaywalledSites) {
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
    // These delays are MINIMUM wait times - system will continue monitoring
    // until content stabilizes (no changes for 2 seconds) or max timeout
    const heavyJsSites = {
      'malaysiakini.com': 8000,      // Minimum 8s for auth, then wait for stability
      'mkini.bz': 8000,               // Malaysiakini short domain
      'hmetro.com.my': 7000,          // Minimum wait for Harian Metro
      'harakahdaily.net': 7000,       // Minimum wait for Harakah Daily
      'sinchew.com.my': 7000,         // Minimum wait for Sin Chew Daily
      'orientaldaily.com.my': 7000,   // Minimum wait for Oriental Daily
      'freemalaysiatoday.com': 6000,  // Minimum wait for FMT
    };

    // Check Malaysian sites first (these need minimum delays)
    for (final entry in heavyJsSites.entries) {
      if (host.contains(entry.key)) {
        return entry.value;
      }
    }

    // For all other sites (including international paywalls):
    // Use dynamic content detection - wait until content stops changing
    // This is more reliable than fixed delays and works for any site
    return 3000; // Minimum 3 seconds, then wait for content stability
  } catch (_) {
    return 3000; // Default 3 seconds
  }
}