import '../models/feed_item.dart';
import '../models/feed_source.dart';

import '../services/rss_service.dart';
import '../services/article_dao.dart';

class FeedRepository {
  final RssService rssService;
  final ArticleDao articleDao;

  FeedRepository({
    required this.rssService,
    required this.articleDao,
  });

  // Loads all articles across all sources.
  // 1. Read local DB first
  // 2. Fetch new data from internet
  // 3. Merge read/bookmark state from DB
  // 4. Save merged back to DB
  Future<List<FeedItem>> loadAll(List<FeedSource> sources) async {
    final cached = await articleDao.getAllArticles();

    final List<FeedItem> fresh = [];
    for (final src in sources) {
      final itemsForFeed = await rssService.fetchFeedItems(src);
      fresh.addAll(itemsForFeed);
    }

    // preserve isRead/isBookmarked
    final cachedById = {
      for (final c in cached) c.id: c,
    };

    final merged = fresh.map((f) {
      final prev = cachedById[f.id];
      if (prev == null) return f;
      return f.copyWith(
        isRead: prev.isRead,
        isBookmarked: prev.isBookmarked,
      );
    }).toList();

    await articleDao.upsertArticles(merged);

    return merged;
  }

  // optional helper to refresh just one source
  Future<List<FeedItem>> loadSingle(FeedSource source) async {
    final cached = await articleDao.getAllArticles();
    final fresh = await rssService.fetchFeedItems(source);

    final cachedById = {
      for (final c in cached) c.id: c,
    };

    final merged = fresh.map((f) {
      final prev = cachedById[f.id];
      if (prev == null) return f;
      return f.copyWith(
        isRead: prev.isRead,
        isBookmarked: prev.isBookmarked,
      );
    }).toList();

    await articleDao.upsertArticles(merged);
    return merged;
  }

  Future<void> setRead(String id, bool isRead) async {
    await articleDao.updateReadStatus(id, isRead);
  }

  Future<void> setBookmark(String id, bool isBookmarked) async {
    await articleDao.updateBookmark(id, isBookmarked);
  }
}
