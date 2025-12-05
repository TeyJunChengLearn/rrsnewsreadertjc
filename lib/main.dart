// lib/main.dart
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

import 'data/http_feed_fetcher.dart';
import 'data/rss_atom_parser.dart';
import 'services/rss_service.dart';

import 'data/feed_repository.dart';
import 'screens/root_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
          // ⬇⬇⬇ use loadFromStorage, not load
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

        // FEED SOURCE DAO (BBC, Yahoo, etc. stored in SQLite)
        ProxyProvider<DatabaseService, FeedSourceDao>(
          update: (_, db, __) => FeedSourceDao(db),
        ),
        Provider<CookieBridge>(
          create: (_) => CookieBridge(),
        ),

        // In main.dart, update the Readability4JExtended provider
// Update the Readability4JExtended provider in main.dart
        Provider<Readability4JExtended>(
          create: (ctx) {
            final cookieBridge = ctx.read<CookieBridge>();
            return Readability4JExtended(
              config: ReadabilityConfig(
                pageLoadDelay: const Duration(seconds: 10),
                useMobileUserAgent: true,
                attemptAuthenticatedRss: true,
              ),
              cookieHeaderBuilder: cookieBridge.buildHeader,
            );
          },
        ),

        ProxyProvider2<Readability4JExtended, ArticleDao,
            ArticleContentService>(
          update: (_, readability, articleDao, __) => ArticleContentService(
            readability: readability,
            articleDao: articleDao,
          ),
        ),

        // LOW LEVEL RSS
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

        // REPOSITORY = RSS + DB
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
