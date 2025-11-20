import '../models/feed_item.dart';
import 'article_dao.dart';
import 'readability_service.dart';

class ArticleContentService {
  final Readability4JExtended readability;
  final ArticleDao articleDao;

  ArticleContentService({required this.readability, required this.articleDao});

  /// Fetches main article text for any FeedItem lacking it. Returns a map of
  /// article id -> extracted main text for rows that were updated.
  Future<Map<String, String>> backfillMissingContent(List<FeedItem> items) async {
    final updated = <String, String>{};

    for (final item in items) {
      if (item.link.isEmpty) continue;
      if ((item.mainText ?? '').isNotEmpty) continue;

      final mainText = await readability.extractMainText(item.link);
      if (mainText == null) continue;

      await articleDao.updateMainText(item.id, mainText);
      updated[item.id] = mainText;
    }

    return updated;
  }
}