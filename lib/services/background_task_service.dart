// lib/services/background_task_service.dart
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'database_service.dart';
import 'article_dao.dart';
import 'feed_source_dao.dart';
import 'cookie_bridge.dart';
import '../data/http_feed_fetcher.dart';
import '../data/rss_atom_parser.dart';
import 'rss_service.dart';
import '../data/feed_repository.dart';
import 'article_content_service.dart';
import 'readability_service.dart';

const String fetchArticlesTaskName = 'fetchArticles';

/// Background task callback - runs when WorkManager triggers the task
/// Only fetches RSS feeds, does NOT enrich articles (enrichment happens on-screen only)
@pragma('vm:entry-point')
void backgroundTaskCallback() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('📱 Background task started: $task');

    try {
      // Initialize minimal services for RSS fetching only
      final dbService = DatabaseService();
      final articleDao = ArticleDao(dbService);
      final feedSourceDao = FeedSourceDao(dbService);
      final cookieBridge = CookieBridge();

      final rssService = RssService(
        fetcher: HttpFeedFetcher(
          cookieHeaderBuilder: cookieBridge.buildHeader,
        ),
        parser: RssAtomParser(),
      );

      // Create a minimal ArticleContentService just for repository
      // (not used in background, but needed for repository constructor)
      final readability = Readability4JExtended(
        config: ReadabilityConfig(
          requestDelay: const Duration(milliseconds: 500),
          attemptRssFallback: true,
        ),
        cookieHeaderBuilder: cookieBridge.buildHeader,
      );

      final articleContentService = ArticleContentService(
        readability: readability,
        articleDao: articleDao,
      );

      final repository = FeedRepository(
        rssService: rssService,
        articleDao: articleDao,
        feedSourceDao: feedSourceDao,
        articleContentService: articleContentService,
      );

      // Fetch new articles from RSS feeds
      debugPrint('📰 Fetching RSS feeds...');
      final sources = await feedSourceDao.getAllSources();
      debugPrint('📋 Found ${sources.length} feed sources');

      await repository.loadAll(sources);
      await repository.cleanupOldArticlesForSources(sources);

      final allArticles = await articleDao.getAllArticles();
      debugPrint('✅ Background fetch completed: ${allArticles.length} total articles in database');
      debugPrint('ℹ️ Articles will be enriched on-screen when viewed');

      return Future.value(true);
    } catch (e, stack) {
      debugPrint('❌ Background task error: $e');
      debugPrint('Stack: $stack');
      return Future.value(false);
    }
  });
}

class BackgroundTaskService {
  static const String _uniqueTaskName = 'articleFetchTask';

  /// Initialize WorkManager and register periodic task
  static Future<void> initialize() async {
    debugPrint('🔧 Initializing WorkManager...');

    await Workmanager().initialize(
      backgroundTaskCallback,
    );

    // Register periodic task to run every 30 minutes
    await registerPeriodicTask();

    debugPrint('✅ WorkManager initialized');
  }

  /// Register a periodic task that runs every 30 minutes
  static Future<void> registerPeriodicTask() async {
    debugPrint('📅 Registering periodic task (every 30 minutes)...');

    await Workmanager().registerPeriodicTask(
      _uniqueTaskName,
      fetchArticlesTaskName,
      frequency: const Duration(minutes: 30),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      initialDelay: const Duration(minutes: 1), // Start after 1 minute
    );

    debugPrint('✅ Periodic task registered');
  }

  /// Cancel all background tasks
  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
    debugPrint('🛑 All background tasks cancelled');
  }

  /// Trigger a one-time background task immediately (for testing)
  static Future<void> runImmediately() async {
    debugPrint('🚀 Triggering immediate background task...');

    await Workmanager().registerOneOffTask(
      'immediateTask',
      fetchArticlesTaskName,
      initialDelay: const Duration(seconds: 5),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }
}
