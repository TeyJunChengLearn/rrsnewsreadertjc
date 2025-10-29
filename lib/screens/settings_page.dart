import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/rss_provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _pickUpdateInterval(BuildContext context) async {
    final settings = context.read<SettingsProvider>();

    final choices = const [15, 30, 60, 120];
    final picked = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Update interval (minutes)',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              ...choices.map((m) {
                return ListTile(
                  title: Text('$m minutes'),
                  onTap: () {
                    Navigator.of(context).pop(m);
                  },
                );
              }).toList(),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (picked != null) {
      await settings.setUpdateIntervalMinutes(picked);
    }
  }

  Future<void> _pickArticleLimit(BuildContext context) async {
    final settings = context.read<SettingsProvider>();

    final choices = const [500, 1000, 2000, 5000];
    final picked = await showModalBottomSheet<int>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Article limit per feed',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              ...choices.map((limit) {
                return ListTile(
                  title: Text('$limit articles'),
                  subtitle: const Text(
                    'Keep newest + bookmarks. Oldest unbookmarked will be removed above this limit.',
                    style: TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.of(context).pop(limit);
                  },
                );
              }).toList(),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (picked != null) {
      await settings.setArticleLimitPerFeed(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final rss = context.watch<RssProvider>();

    final themeSubtitle =
        settings.darkTheme ? 'Dark theme enabled' : 'Light theme enabled';

    final summarySubtitle = settings.displaySummary
        ? 'Open summary view first'
        : 'Open full article directly';

    final highlightSubtitle = settings.highlightText
        ? 'Keyword highlighting ON'
        : 'Keyword highlighting OFF';

    final intervalSubtitle =
        '${settings.updateIntervalMinutes} minutes between refreshes';

    final limitSubtitle =
        'Keep ~${settings.articleLimitPerFeed} newest per feed (unbookmarked old items may be cleaned)';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---------- Sync ----------
          const Text(
            'Sync',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),

          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Update interval'),
            subtitle: Text(intervalSubtitle),
            onTap: () => _pickUpdateInterval(context),
          ),

          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('Article limit for each feed'),
            subtitle: Text(
              '$limitSubtitle\n(Current unread: ${rss.unreadCount})',
            ),
            isThreeLine: true,
            onTap: () => _pickArticleLimit(context),
          ),

          const SizedBox(height: 24),

          // ---------- Interface ----------
          const Text(
            'Interface',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),

          SwitchListTile(
            value: settings.darkTheme,
            onChanged: (v) {
              settings.toggleDarkTheme(v);
            },
            secondary: const Icon(Icons.dark_mode),
            title: const Text('Dark theme'),
            subtitle: Text(themeSubtitle),
          ),

          SwitchListTile(
            value: settings.displaySummary,
            onChanged: (v) {
              settings.setDisplaySummary(v);
            },
            secondary: const Icon(Icons.article),
            title: const Text('Display summary first'),
            subtitle: Text(summarySubtitle),
          ),

          SwitchListTile(
            value: settings.highlightText,
            onChanged: (v) {
              settings.setHighlightText(v);
            },
            secondary: const Icon(Icons.highlight),
            title: const Text('Highlight text'),
            subtitle: Text(
              highlightSubtitle,
            ),
          ),
        ],
      ),
    );
  }
}
