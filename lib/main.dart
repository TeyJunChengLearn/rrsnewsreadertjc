// lib/main.dart
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/settings_provider.dart';
import 'providers/rss_provider.dart';

import 'services/database_service.dart';
import 'services/article_dao.dart';
import 'services/feed_source_dao.dart';
import 'services/readability_service.dart';
import 'services/article_content_service.dart';
import 'services/cookie_bridge.dart';
import 'services/android_webview_extractor.dart';
import 'services/background_task_service.dart';

import 'data/http_feed_fetcher.dart';
import 'data/rss_atom_parser.dart';
import 'services/rss_service.dart';

import 'data/feed_repository.dart';
import 'screens/root_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background task service for periodic article fetching
  await BackgroundTaskService.initialize();

  runApp(const AppBootstrap());
}

class AppBootstrap extends StatelessWidget {
  const AppBootstrap({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // SETTINGS
        ChangeNotifierProvider(
          create: (_) => SettingsProvider()..loadFromStorage(),
        ),

        // DB SERVICE
        Provider<DatabaseService>(
          create: (_) => DatabaseService(),
        ),

        // ARTICLE DAO
        ProxyProvider<DatabaseService, ArticleDao>(
          update: (_, db, __) => ArticleDao(db),
        ),

        // FEED SOURCE DAO
        ProxyProvider<DatabaseService, FeedSourceDao>(
          update: (_, db, __) => FeedSourceDao(db),
        ),

        // COOKIE BRIDGE (for WebView cookies and authentication)
        Provider<CookieBridge>(
          create: (_) => CookieBridge(),
        ),

        // READABILITY SERVICE (Simplified but fully functional)
        Provider<Readability4JExtended>(
          create: (ctx) {
            final cookieBridge = ctx.read<CookieBridge>();
            final webRenderer = Platform.isAndroid
                ? AndroidWebViewExtractor()
                : null;
            
            return Readability4JExtended(
              config: ReadabilityConfig(
                requestDelay: const Duration(milliseconds: 500),
                attemptRssFallback: true,
                // Use mobile user agent for better paywall bypass
                // Many sites (like Malaysiakini) serve full content to mobile
                userAgent: ReadabilityConfig.mobileUserAgent,
              ),
              cookieHeaderBuilder: cookieBridge.buildHeader,
              webViewExtractor: webRenderer,
            );
          },
        ),

        // ARTICLE CONTENT SERVICE
        ProxyProvider2<Readability4JExtended, ArticleDao,
            ArticleContentService>(
          update: (_, readability, articleDao, __) => ArticleContentService(
            readability: readability,
            articleDao: articleDao,
          ),
        ),

        // RSS SERVICE
        Provider<RssService>(
          create: (ctx) {
            final cookieBridge = ctx.read<CookieBridge>();
            return RssService(
              fetcher: HttpFeedFetcher(
                cookieHeaderBuilder: cookieBridge.buildHeader,
              ),
              parser: RssAtomParser(),
            );
          },
        ),

        // FEED REPOSITORY
        ProxyProvider4<RssService, ArticleDao, FeedSourceDao,
            ArticleContentService, FeedRepository>(
          update:
              (_, rssService, articleDao, feedSourceDao, articleContent, __) =>
                  FeedRepository(
            rssService: rssService,
            articleDao: articleDao,
            feedSourceDao: feedSourceDao,
            articleContentService: articleContent,
          ),
        ),

        // UI PROVIDER
        ChangeNotifierProvider<RssProvider>(
          create: (ctx) {
            final repo = ctx.read<FeedRepository>();
            final p = RssProvider(repo: repo);
            p.loadInitial();
            return p;
          },
        ),
      ],
      child: const MyApp(),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        final isDark = settings.darkTheme;

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Flutter RSS Reader',
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: Colors.blue,
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: Colors.blue,
            brightness: Brightness.dark,
          ),
          home: const RootShell(),
        );
      },
    );
  }
}
