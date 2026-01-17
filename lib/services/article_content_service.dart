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
  /// Uses simple HTTP extraction by default. WebView extraction can be enabled
  /// per-feed via feed settings (like the Java project approach).
  /// [delayTime] - seconds to wait after page loads (from feed settings)
  /// [maxRetries] - max retry attempts for failed/empty content (like Java's retryCountMap)
  Future<Map<String, ArticleReadabilityResult>> backfillMissingContent(
    List<FeedItem> items, {
    bool useWebView = false,
    int delayTime = 0,
    int maxRetries = 3,
  }) async {
    final updated = <String, ArticleReadabilityResult>{};
    final failedItems = <FeedItem>[]; // Like Java's failedIds
    final retryCount = <String, int>{}; // Like Java's retryCountMap

    // First pass: try all items
    for (final item in items) {
      // Skip items that don't need enrichment
      if (!_needsEnrichment(item)) continue;

      final result = await _extractSingleItem(
        item,
        useWebView: useWebView,
        delayTime: delayTime,
      );

      if (result != null) {
        await articleDao.updateContent(item.id, result.mainText, result.imageUrl);
        updated[item.id] = result;
      } else {
        // Add to failed list for retry (like Java's failedIds.add())
        failedItems.add(item);
        retryCount[item.id] = 0;
      }
    }

    // Retry failed items (like Java's retry logic lines 117-126)
    while (failedItems.isNotEmpty) {
      final item = failedItems.removeAt(0);
      final attempts = retryCount[item.id] ?? 0;

      if (attempts < maxRetries) {
        retryCount[item.id] = attempts + 1;
        print('🔄 Retrying ${item.title} (attempt ${attempts + 1}/$maxRetries)');

        final result = await _extractSingleItem(
          item,
          useWebView: useWebView,
          delayTime: delayTime,
        );

        if (result != null) {
          await articleDao.updateContent(item.id, result.mainText, result.imageUrl);
          updated[item.id] = result;
          print('   ✅ Retry successful!');
        } else {
          // Still failed, add back to queue if more retries left
          if (attempts + 1 < maxRetries) {
            failedItems.add(item);
          } else {
            print('   ❌ Max retries reached for: ${item.title}');
          }
        }
      }
    }

    return updated;
  }

  /// Check if item needs enrichment
  bool _needsEnrichment(FeedItem item) {
    if (item.link.isEmpty) return false;
    final existingText = (item.mainText ?? '').trim();
    final needsBetterText = _looksLikeTeaser(existingText);
    final needsImage = (item.imageUrl ?? '').trim().isEmpty;
    return needsBetterText || needsImage;
  }

  /// Extract content for a single item
  /// Returns null if extraction failed or content is empty/too short
  Future<ArticleReadabilityResult?> _extractSingleItem(
    FeedItem item, {
    required bool useWebView,
    required int delayTime,
  }) async {
    final existingText = (item.mainText ?? '').trim();
    final needsBetterText = _looksLikeTeaser(existingText);
    final needsImage = (item.imageUrl ?? '').trim().isEmpty;

    print('🔍 Enriching: ${item.title}');
    print('   URL: ${item.link}');
    if (useWebView) {
      print('   WebView: true, delay: ${delayTime}s');
    }

    final content = await readability.extractMainContent(
      item.link,
      useWebView: useWebView,
      delayTime: delayTime,
    );

    if (content == null) {
      print('   ❌ Extraction failed (returned null)');
      return null;
    }

    final extractedLength = content.mainText?.trim().length ?? 0;
    print('   ✓ Extracted ${extractedLength} chars (source: ${content.source})');

    // Like Java: if content is empty, treat as failed (line 354, 407-409)
    if (extractedLength < 150) {
      print('   ⚠️ Content too short (< 150 chars), will retry');
      return null;
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

    if (updates.isEmpty) return null;

    return ArticleReadabilityResult(
      mainText: updates['mainText'],
      imageUrl: updates['imageUrl'],
      pageTitle: content.pageTitle,
    );
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