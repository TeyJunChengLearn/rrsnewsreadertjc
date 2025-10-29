import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/rss_provider.dart';
import '../providers/settings_provider.dart';
import '../models/feed_item.dart';

import 'article_webview_page.dart';
import 'feed_page.dart';
import 'settings_page.dart';
import 'news_search_page.dart';

class NewsPage extends StatefulWidget {
  const NewsPage({super.key});

  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void _openFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return const _FilterSheet();
      },
    );
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NewsSearchPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rss = context.watch<RssProvider>();
    final items = rss.visibleItems; // <-- use filtered/sorted list now

    return Scaffold(
      key: _scaffoldKey,

      drawer: const _NewsDrawer(),

      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: _openDrawer,
        ),
        title: const Text(
          'News',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () => _openFilterSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _openSearch(context),
          ),
        ],
      ),

      body: RefreshIndicator(
        onRefresh: rss.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            Text(
              'All feeds',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),

            _UnreadChip(count: rss.unreadCount),
            const SizedBox(height: 16),

            if (rss.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Error: ${rss.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              ),

            if (rss.loading && items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 64),
                child: Center(child: CircularProgressIndicator()),
              ),

            ...items.map((item) => _ArticleRow(item: item)),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // could be "mark all read"
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        shape: const StadiumBorder(),
        icon: const Icon(Icons.check),
        label: const SizedBox.shrink(),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

// Drawer with feeds, settings, dark theme toggle
class _NewsDrawer extends StatelessWidget {
  const _NewsDrawer();

  @override
  Widget build(BuildContext context) {
    final rss = context.watch<RssProvider>();
    final settings = context.watch<SettingsProvider>();
    final accent = Theme.of(context).colorScheme.primary;

    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          bottomRight: Radius.circular(16),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      'Feed',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  ListTile(
                    leading: const Icon(Icons.folder_copy_outlined),
                    title: const Text('All feeds'),
                    onTap: () {
                      Navigator.of(context).pop();
                    },
                  ),

                  for (final source in rss.sources)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: 4,
                        top: 8,
                      ),
                      child: Text(
                        source.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                  const SizedBox(height: 8),

                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: const Text('Add more feed'),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const FeedPage(),
                        ),
                      );
                    },
                  ),

                  ListTile(
                    leading: const Icon(Icons.download),
                    title: const Text('Load app state'),
                    onTap: () {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Load app state (not implemented)'),
                        ),
                      );
                    },
                  ),

                  ListTile(
                    leading: const Icon(Icons.upload),
                    title: const Text('Save app state'),
                    onTap: () {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Save app state (not implemented)'),
                        ),
                      );
                    },
                  ),

                  const Divider(height: 24, thickness: 1),

                  ListTile(
                    leading: const Icon(Icons.settings),
                    title: const Text('Settings'),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsPage(),
                        ),
                      );
                    },
                  ),

                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('Help'),
                    onTap: () {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Help (not implemented)'),
                        ),
                      );
                    },
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.dark_mode),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Text(
                            'Dark theme',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        Switch(
                          value: settings.darkTheme,
                          activeColor: accent,
                          onChanged: (v) {
                            context
                                .read<SettingsProvider>()
                                .toggleDarkTheme(v);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// The white chip from screenshot ("1050 unread")
class _UnreadChip extends StatelessWidget {
  final int count;
  const _UnreadChip({required this.count});

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final bg = Colors.grey.shade300;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$count unread',
        style: TextStyle(
          fontSize: 13,
          color: textColor,
        ),
      ),
    );
  }
}

// News list row
class _ArticleRow extends StatelessWidget {
  final FeedItem item;
  const _ArticleRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final rss = context.read<RssProvider>();
    final ago = rss.niceTimeAgo(item.pubDate);
    final isBookmarked = item.isBookmarked;

    final Color unreadTitleColor =
        Theme.of(context).colorScheme.onSurface;
    final Color readTitleColor = Colors.grey.shade600;

    final TextStyle titleStyle = TextStyle(
      color: item.isRead ? readTitleColor : unreadTitleColor,
      fontSize: 18,
      fontWeight: item.isRead ? FontWeight.w400 : FontWeight.w600,
      height: 1.3,
    );

    final Color metaColor =
        item.isRead ? Colors.grey.shade500 : Colors.grey.shade700;

    // summary under title
    final String? cleanedSummary = _cleanSummary(item.description);
    final bool hasSummary =
        cleanedSummary != null && cleanedSummary.trim().isNotEmpty;

    return InkWell(
      onTap: () {
        // optimistic mark read
        rss.markRead(item);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ArticleWebViewPage(item: item),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // LEFT SECTION (text)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Source name
                  Text(
                    item.sourceTitle,
                    style: TextStyle(
                      color: metaColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Title
                  Text(
                    item.title,
                    style: titleStyle,
                  ),
                  const SizedBox(height: 8),

                  // Time ago (e.g. "2 hours ago")
                  Text(
                    ago,
                    style: TextStyle(
                      fontSize: 14,
                      color: metaColor,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Bookmark + more menu
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          isBookmarked
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                          size: 20,
                          color: item.isRead
                              ? Colors.grey.shade600
                              : null,
                        ),
                        onPressed: () {
                          rss.toggleBookmark(item);
                        },
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          Icons.more_vert,
                          size: 20,
                          color: item.isRead
                              ? Colors.grey.shade600
                              : null,
                        ),
                        onPressed: () {
                          // TODO: share, open in browser, etc.
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 16),

            // RIGHT SECTION (thumbnail + status dot)
            _ThumbWithStatus(
              imageUrl: item.imageUrl,
              isRead: item.isRead,
              hasSummary: hasSummary, // <-- pass this now
            ),
          ],
        ),
      ),
    );
  }

  // strip HTML tags and collapse whitespace
  String? _cleanSummary(String? html) {
    if (html == null) return null;
    final noTags = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
    final squished =
        noTags.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (squished.isEmpty) return null;
    return squished;
  }
}


// thumbnail with yellow dot (your screenshot shows yellow, not green)
class _ThumbWithStatus extends StatelessWidget {
  final String? imageUrl;
  final bool isRead;
  final bool hasSummary;

  const _ThumbWithStatus({
    required this.imageUrl,
    required this.isRead,
    required this.hasSummary,
  });

  @override
  Widget build(BuildContext context) {
    const double size = 90;

    // dot color logic:
    // read        -> grey
    // unread + summary -> green
    // unread + no summary -> amber/yellow
    final Color dotColor;
    if (isRead) {
      dotColor = Colors.grey;
    } else if (hasSummary) {
      dotColor = Colors.green;
    } else {
      dotColor = Colors.amber;
    }

    Widget img;
    if (imageUrl == null || imageUrl!.isEmpty) {
      img = Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.image_not_supported, size: 28),
      );
    } else {
      img = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          height: size,
          width: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            height: size,
            width: size,
            alignment: Alignment.center,
            child: const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            height: size,
            width: size,
            color: Colors.grey.shade300,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image),
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        img,
        Positioned(
          right: 4,
          bottom: 4,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: dotColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.white,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}


// bottom sheet widget (Sort by / Filter by)
class _FilterSheet extends StatelessWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context) {
    final rss = context.watch<RssProvider>();
    final accent = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surface;
    final borderColor = Colors.grey.shade400;

    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? accent : surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? Colors.transparent : borderColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check, size: 18, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sort by
            const Text(
              'Sort by',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                chip(
                  label: 'Latest first',
                  selected: rss.isLatestFirst,
                  onTap: () {
                    context
                        .read<RssProvider>()
                        .setSortOrder(SortOrder.latestFirst);
                  },
                ),
                chip(
                  label: 'Oldest first',
                  selected: rss.isOldestFirst,
                  onTap: () {
                    context
                        .read<RssProvider>()
                        .setSortOrder(SortOrder.oldestFirst);
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Filter by
            const Text(
              'Filter by',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                chip(
                  label: 'All articles',
                  selected: rss.showAllArticles,
                  onTap: () {
                    // reset bookmark filter + read filter to all
                    context
                        .read<RssProvider>()
                        .setBookmarkFilter(BookmarkFilter.all);
                    context
                        .read<RssProvider>()
                        .setReadFilter(ReadFilter.all);
                  },
                ),
                chip(
                  label: 'Bookmark only',
                  selected: rss.showBookmarkedOnly,
                  onTap: () {
                    context
                        .read<RssProvider>()
                        .setBookmarkFilter(BookmarkFilter.bookmarkedOnly);
                  },
                ),
                chip(
                  label: 'Read only',
                  selected: rss.showReadOnly,
                  onTap: () {
                    context
                        .read<RssProvider>()
                        .setReadFilter(ReadFilter.readOnly);
                  },
                ),
                chip(
                  label: 'Unread only',
                  selected: rss.showUnreadOnly,
                  onTap: () {
                    context
                        .read<RssProvider>()
                        .setReadFilter(ReadFilter.unreadOnly);
                  },
                ),
              ],
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
