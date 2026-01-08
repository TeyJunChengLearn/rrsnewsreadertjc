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
      final delayMs = shouldUseWebView ? defaultDelayMs : 0;

      final content = await readability.extractMainContent(
        item.link,
        useWebView: shouldUseWebView,
        delayMs: delayMs,
      );
      if (content == null) continue;

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