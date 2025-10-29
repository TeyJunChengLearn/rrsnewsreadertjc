import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/settings_provider.dart';
import 'providers/rss_provider.dart';

import 'services/database_service.dart';
import 'services/article_dao.dart';

import '../data/http_feed_fetcher.dart';
import '../data/rss_atom_parser.dart';
import '../services/rss_service.dart';

import '../data/feed_repository.dart';
import 'screens/root_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. settings (persistent user prefs)
  final settingsProvider = SettingsProvider();
  await settingsProvider.loadFromStorage();

  // 2. data layer
  final dbService = DatabaseService();
  final articleDao = ArticleDao(dbService);

  final rssService = RssService(
    fetcher: HttpFeedFetcher(),
    parser: RssAtomParser(),
  );

  final repo = FeedRepository(
    rssService: rssService,
    articleDao: articleDao,
  );

  runApp(MyApp(
    settingsProvider: settingsProvider,
    repo: repo,
  ));
}

class MyApp extends StatelessWidget {
  final SettingsProvider settingsProvider;
  final FeedRepository repo;

  const MyApp({
    super.key,
    required this.settingsProvider,
    required this.repo,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // already created above, so .value is correct
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settingsProvider,
        ),

        // articles / read state / etc.
        ChangeNotifierProvider(
          create: (_) {
            final p = RssProvider(repo: repo);
            p.loadInitial();
            return p;
          },
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          final dark = settings.darkTheme;

          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Flutter RSS Reader',

            themeMode: dark ? ThemeMode.dark : ThemeMode.light,

            theme: ThemeData(
              brightness: Brightness.light,
              useMaterial3: true,
              colorSchemeSeed: Colors.red,
            ),

            darkTheme: ThemeData(
              brightness: Brightness.dark,
              useMaterial3: true,
              colorSchemeSeed: Colors.red,
            ),

            home: const RootShell(),
          );
        },
      ),
    );
  }
}
