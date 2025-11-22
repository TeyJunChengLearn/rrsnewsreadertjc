import '../models/feed_item.dart';
import 'article_dao.dart';
import 'readability_service.dart';

class ArticleContentService {
  final Readability4JExtended readability;
  final ArticleDao articleDao;

  ArticleContentService({required this.readability, required this.articleDao});

  /// Fetches main article text/images for any FeedItem missing them.
  /// Returns a map of article id -> extracted content for rows that were updated.
  Future<Map<String, ArticleReadabilityResult>> backfillMissingContent(
    List<FeedItem> items,
  ) async {
    final updated = <String, ArticleReadabilityResult>{};

    for (final item in items) {
      if (item.link.isEmpty) continue;
      final needsText = (item.mainText ?? '').trim().isEmpty;
      final needsImage = (item.imageUrl ?? '').trim().isEmpty;
      if (!needsText && !needsImage) continue;

      final content = await readability.extractMainContent(item.link);
      if (content == null) continue;

      final updates = <String, String?>{};
      final trimmedText = content.mainText?.trim();
      if (needsText && (trimmedText ?? '').isNotEmpty) {
        updates['mainText'] = trimmedText;
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
}