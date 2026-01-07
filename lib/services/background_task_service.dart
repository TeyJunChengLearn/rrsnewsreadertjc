// lib/services/background_task_service.dart
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'database_service.dart';
import 'article_dao.dart';
import 'feed_source_dao.dart';
import 'readability_service.dart';
import 'article_content_service.dart';
import 'cookie_bridge.dart';
import 'android_webview_extractor.dart';
import '../data/http_feed_fetcher.dart';
import '../data/rss_atom_parser.dart';
import 'rss_service.dart';
import '../data/feed_repository.dart';

const String fetchArticlesTaskName = 'fetchAndEnrichArticles';

/// Background task callback - runs when WorkManager triggers the task
@pragma('vm:entry-point')
void backgroundTaskCallback() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('📱 Background task started: $task');

    try {
      // Initialize all services
      final dbService = DatabaseService();
      final articleDao = ArticleDao(dbService);
      final feedSourceDao = FeedSourceDao(dbService);
      final cookieBridge = CookieBridge();

      final webRenderer = Platform.isAndroid ? AndroidWebViewExtractor() : null;

      final readability = Readability4JExtended(
        config: ReadabilityConfig(
          requestDelay: const Duration(milliseconds: 500),
          attemptRssFallback: true,
          userAgent: ReadabilityConfig.mobileUserAgent,
        ),
        cookieHeaderBuilder: cookieBridge.buildHeader,
        webViewExtractor: webRenderer,
      );

      final articleContentService = ArticleContentService(
        readability: readability,
        articleDao: articleDao,
      );

      final rssService = RssService(
        fetcher: HttpFeedFetcher(
          cookieHeaderBuilder: cookieBridge.buildHeader,
        ),
        parser: RssAtomParser(),
      );

      final repository = FeedRepository(
        rssService: rssService,
        articleDao: articleDao,
        feedSourceDao: feedSourceDao,
        articleContentService: articleContentService,
      );

      // Fetch new articles
      debugPrint('📰 Fetching RSS feeds...');
      final sources = await feedSourceDao.getAllSources();
      await repository.loadAll(sources);
      await repository.cleanupOldArticlesForSources(sources);

      // Get articles that need enrichment
      final allArticles = await articleDao.getAllArticles();
      debugPrint('📋 Found ${allArticles.length} total articles');

      // Filter articles that need content
      final needsContent = allArticles.where((item) {
        if (item.link.isEmpty) return false;
        final existingText = (item.mainText ?? '').trim();

        // Only skip if article has SUBSTANTIAL content (500+ chars)
        // This prevents skipping articles with short RSS descriptions
        final hasSubstantialContent = existingText.length >= 500;
        final hasImage = (item.imageUrl ?? '').trim().isNotEmpty;

        // Enrich if missing substantial content OR missing image
        return !hasSubstantialContent || !hasImage;
      }).toList();

      debugPrint('🔍 ${needsContent.length} articles need enrichment');

      // Get user's sort preference
      final prefs = await SharedPreferences.getInstance();
      final sortOrderPref = prefs.getString('sortOrder') ?? 'latestFirst';
      final isLatestFirst = sortOrderPref == 'latestFirst';

      // Sort articles based on user preference
      needsContent.sort((a, b) {
        final ad = a.pubDate?.millisecondsSinceEpoch ?? 0;
        final bd = b.pubDate?.millisecondsSinceEpoch ?? 0;
        final cmp = ad.compareTo(bd);
        return isLatestFirst ? -cmp : cmp;
      });

      debugPrint('📊 Enrichment order: ${isLatestFirst ? "NEWEST" : "OLDEST"} first');

      // Enrich up to 60 articles per run (balanced approach)
      final toProcess = needsContent.take(60).toList();
      int enrichedCount = 0;

      debugPrint('📋 Processing ${toProcess.length} of ${needsContent.length} articles');

      for (final item in toProcess) {
        try {
          debugPrint('📖 Enriching: ${item.title}');

          // Use HTTP-only extraction in background (no WebView)
          // WebView requires UI context and may fail when app is closed
          final content = await readability.extractMainContent(
            item.link,
            useWebView: false,  // Force HTTP extraction in background
            delayMs: 0,
          );

          if (content != null && content.hasContent) {
            // Save to database
            await articleContentService.saveExtractedContent(
              articleId: item.id,
              mainText: content.mainText,
              imageUrl: content.imageUrl,
            );

            enrichedCount++;
            debugPrint('✅ Enriched article: ${item.title}');
          } else {
            debugPrint('⚠️ No content extracted for: ${item.title}');
          }
        } catch (e) {
          debugPrint('❌ Failed to enrich ${item.title}: $e');
        }
      }

      debugPrint('✨ Background task completed: enriched $enrichedCount articles');
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
