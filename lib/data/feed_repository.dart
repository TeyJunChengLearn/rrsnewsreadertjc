// lib/data/feed_repository.dart
import 'package:shared_preferences/shared_preferences.dart';

import '../models/feed_item.dart';
import '../models/feed_source.dart';

import '../services/rss_service.dart';
import '../services/article_dao.dart';
import '../services/feed_source_dao.dart';
import '../services/article_content_service.dart';
import '../services/readability_service.dart';

class FeedRepository {
  final RssService rssService;
  final ArticleDao articleDao;
  final FeedSourceDao feedSourceDao;
  final ArticleContentService articleContentService;
  FeedRepository({
    required this.rssService,
    required this.articleDao,
    required this.feedSourceDao,
    required this.articleContentService,
  });

  // ---------------------------------------------------------------------------
  // FEED SOURCES
  // ---------------------------------------------------------------------------
  Future<List<FeedSource>> getAllSources() async {
    return await feedSourceDao.getAllSources();
  }

  /// Insert a new feed source and return it with its generated id.
  Future<FeedSource> addSource(FeedSource src) async {
    // DAO handles conflict / duplicates.
    return await feedSourceDao.insertSource(src);
  }

  Future<void> deleteSource(int id) async {
    await feedSourceDao.deleteSource(id);
  }

  // ---------------------------------------------------------------------------
  // FETCH + MERGE
  // ---------------------------------------------------------------------------
  /// Fetch from network for each source, parse, upsert into DB, and return the
  /// merged list (network items + existing flags like read/bookmark preserved).
  Future<List<FeedItem>> loadAll(List<FeedSource> sources) async {
    // 1) read existing from DB
    final existing = await articleDao.getAllArticles();
    final existingById = {for (final a in existing) a.id: a};

    // 2) fetch all sources (ignore failures per-source)
    final fetched = <FeedItem>[];
    for (final src in sources) {
      try {
        final items = await rssService.fetchFeedItems(src);
        fetched.addAll(items);
      } catch (_) {
        // Ignore a single source failure; keep whatever is already in DB.
      }
    }

    // 3) merge (preserve isRead / isBookmarked)
    final Map<String, FeedItem> mergedMap = {};
    for (final item in fetched) {
      final old = existingById[item.id];
      if (old != null) {
        final incomingText = item.mainText?.trim() ?? '';
        final existingText = old.mainText?.trim() ?? '';

        final prefersIncoming = incomingText.isNotEmpty &&
            (existingText.isEmpty || incomingText.length >= existingText.length);

        mergedMap[item.id] = item.copyWith(
          isRead: old.isRead,
          isBookmarked: old.isBookmarked,
          mainText: prefersIncoming ? item.mainText : old.mainText,
        );
      } else {
        mergedMap[item.id] = item;
      }
    }

    // 4) sort by newest first
    final merged = mergedMap.values.toList()
      ..sort((a, b) {
        final ad = a.pubDate?.millisecondsSinceEpoch ?? 0;
        final bd = b.pubDate?.millisecondsSinceEpoch ?? 0;
        return bd.compareTo(ad);
      });

    // 5) upsert into DB
    await articleDao.upsertArticles(merged);

    return merged;
  }

  // ---------------------------------------------------------------------------
  // ARTICLE FLAGS
  // ---------------------------------------------------------------------------
  Future<void> setRead(String id, int isRead) async {
    await articleDao.updateReadStatus(id, isRead);
  }

  Future<void> setBookmark(String id, bool isBookmarked) async {
    await articleDao.updateBookmark(id, isBookmarked);
  }

  Future<void> hideOlderThan(DateTime cutoff) async {
    await articleDao.hideOlderThan(cutoff);
  }
  // ---------------------------------------------------------------------------
  // DB READ (no network)
  // ---------------------------------------------------------------------------
  Future<List<FeedItem>> readAllFromDb() async {
    // ArticleDao already returns them ordered newest-first.
    return await articleDao.getAllArticles();
  }
  Future<Map<String, ArticleReadabilityResult>> populateArticleContent(
    List<FeedItem> items,
  ) async {
    return await articleContentService.backfillMissingContent(items);
  }
  // ---------------------------------------------------------------------------
  // CLEANUP
  // ---------------------------------------------------------------------------
  /// Enforce per-feed limit (keep newest N UNBOOKMARKED) for all source titles
  /// that exist either in the current sources list or in the articles table.
  /// Bookmarked items are never deleted.
  Future<void> cleanupOldArticlesForSources(
    List<FeedSource> currentSources,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final keepPerFeed = prefs.getInt('articleLimitPerFeed') ?? 1000;

    // Collect distinct titles we should enforce the limit for.
    final titles = <String>{};

    // Titles from current sources
    for (final s in currentSources) {
      final t = s.title.trim();
      if (t.isNotEmpty) titles.add(t);
    }

    // Titles from any existing article rows (covers deleted feeds too)
    final allArticles = await articleDao.getAllArticles();
    for (final a in allArticles) {
      final t = a.sourceTitle.trim();
      if (t.isNotEmpty) titles.add(t);
    }

    // Apply per-feed cap per title
    for (final title in titles) {
      await articleDao.enforceUnbookmarkedLimitForSourceTitle(
        title,
        keepPerFeed,
      );
    }
  }

  Future<void> hideAllRead() async {
    await articleDao.hideAllRead();
  }
}
