import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/rss_provider.dart';
import '../models/feed_source.dart';

import 'package:http/http.dart' as http;
import 'package:webfeed_plus/webfeed_plus.dart';

import 'site_login_page.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }
    String _guessLoginUrl(String feedUrl) {
    final uri = Uri.tryParse(feedUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return feedUrl; // fallback
    }

    var host = uri.host; // e.g. feeds.bbci.co.uk

    // Strip common feed subdomains
    if (host.startsWith('feeds.')) {
      host = host.substring('feeds.'.length); // bbci.co.uk
    } else if (host.startsWith('rss.')) {
      host = host.substring('rss.'.length);
    }

    return '${uri.scheme}://$host'; // e.g. https://bbci.co.uk
  }

  @override
  void dispose() {
    _tabController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  /// Try to detect feed title from the RSS/Atom XML.
  /// Returns null if we cannot detect.
  Future<String?> _autoDetectFeedTitle(String url) async {
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) return null;

      final body = resp.body;

      // Try RSS first
      try {
        final rss = RssFeed.parse(body);
        final t = (rss.title ?? '').trim();
        if (t.isNotEmpty) return t;
      } catch (_) {
        // not RSS, fall through
      }

      // Then try Atom
      try {
        final atom = AtomFeed.parse(body);
        final t = (atom.title ?? '').trim();
        if (t.isNotEmpty) return t;
      } catch (_) {
        // not Atom or parse failed
      }
    } catch (_) {
      // network or parse error – just ignore
    }
    return null;
  }

  /// Show a dialog asking whether this feed needs login.
  /// Returns true if user tapped Yes.
  Future<bool> _askRequiresLogin() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: const [
              Icon(Icons.error_outline, color: Colors.amber),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Does this news feed require a login account?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          content: const Text(
            'An account is required to extract the full content of SOME websites. '
            'If you have an account to sign in into the website, please click Yes '
            'and you will be redirected to the website for signing in with your account.\n\n'
            '(Note: if you did not sign in and your new feed is extracted, you still can '
            're-extract the feed at the add feed page after signing in.)',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final rss = context.watch<RssProvider>();
    final sources = rss.sources;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Add'),
            Tab(text: 'Manage'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ----------------- Add tab -----------------
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.rss_feed),
                    hintText: 'Paste the RSS URL here',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 16),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    final url = _urlController.text.trim();
                    if (url.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter feed URL'),
                        ),
                      );
                      return;
                    }

                    // Try to auto-detect feed title from RSS/Atom
                    String titleText = url;
                    final detected = await _autoDetectFeedTitle(url);
                    if (detected != null && detected.isNotEmpty) {
                      titleText = detected;
                    }

                    // Ask the user whether this feed needs login
                    final requiresLogin = await _askRequiresLogin();

                    // Save source as usual
                    await context.read<RssProvider>().addSource(
                          FeedSource(title: titleText, url: url),
                        );

                    _urlController.clear();

                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Added "$titleText"'),
                      ),
                    );

                    // If user said Yes, open login webview for this site
                    if (requiresLogin) {
  final loginUrl = _guessLoginUrl(url);
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => SiteLoginPage(
        initialUrl: loginUrl,
        siteName: titleText,
      ),
    ),
  );
}

                  },
                  child: const Text('Add feed'),
                ),
                const Spacer(),
                const Text(
                  'Search RSS feeds by keywords using this link:\nhttps://rssfinder.app/',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),

          // ----------------- Manage tab -----------------
          Padding(
            padding: const EdgeInsets.all(16),
            child: sources.isEmpty
                ? const Center(
                    child: Text(
                      'No feeds yet.\nAdd some RSS URLs in the Add tab.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: sources.length,
                    itemBuilder: (context, index) {
                      final src = sources[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          title: Text(src.title),
                          subtitle: Text(src.url),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                tooltip: 'Refresh all feeds',
                                onPressed: () async {
                                  await context.read<RssProvider>().refresh();
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Refreshed ${src.title}'),
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                tooltip: 'Remove this feed',
                                onPressed: () {
                                  context
                                      .read<RssProvider>()
                                      .deleteSource(src);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Removed ${src.title}'),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
