// lib/screens/news_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/feed_item.dart';
import '../providers/rss_provider.dart';
import '../providers/settings_provider.dart';

import 'article_webview_page.dart';
import 'feed_page.dart';
import 'news_search_page.dart';
import 'settings_page.dart';

// Local-only filter state (does NOT modify provider)
enum _LocalReadFilter { all, unreadOnly, readOnly }
enum _LocalBookmarkFilter { all, bookmarkedOnly }
enum _LocalSortOrder { latestFirst, oldestFirst }

class NewsPage extends StatefulWidget {
  const NewsPage({super.key});
  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

@override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<RssProvider>().backfillArticleContent();
    });
  }

  // Local filter state (defaults = show all)
  _LocalReadFilter _readFilter = _LocalReadFilter.all;
  _LocalBookmarkFilter _bmFilter = _LocalBookmarkFilter.all;
  _LocalSortOrder _sortOrder = _LocalSortOrder.latestFirst;

  bool get _hasActiveFilter =>
      _readFilter != _LocalReadFilter.all ||
      _bmFilter != _LocalBookmarkFilter.all ||
      _sortOrder != _LocalSortOrder.latestFirst;

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  Future<void> _openFilterSheet(BuildContext context) async {
    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _FilterSheet(
        readFilter: _readFilter,
        bmFilter: _bmFilter,
        sortOrder: _sortOrder,
      ),
    );

    if (result != null) {
      setState(() {
        _readFilter = result.read;
        _bmFilter = result.bm;
        _sortOrder = result.sort;
      });
    }
  }

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NewsSearchPage()),
    );
  }

 // 0 = unread, 1 = read, 2 = hidden

  // Otherwise use isRead directly (we store 0/1/2 there)
  int _rcOf(FeedItem it) {
    // If model has a readCode field, use it
    try {
      final dynamic dyn = it as dynamic;
      final rc = dyn.readCode;
      if (rc is int) return rc;
    } catch (_) {
      // ignore and fall through
    }
     final v = it.isRead;
    if (v == 0 || v == 1 || v == 2) return v;

    // Safety fallback for weird values
    return v == 1 ? 1 : 0;
  }



  List<FeedItem> _buildAllFeeds(RssProvider rss) {
  List<FeedItem> list = List<FeedItem>.from(rss.allItems);
    final bool bookmarkedOnly =
        _bmFilter == _LocalBookmarkFilter.bookmarkedOnly;
    final bool unreadOnly = _readFilter == _LocalReadFilter.unreadOnly;
    final bool readOnly = _readFilter == _LocalReadFilter.readOnly;
    // 1) Hide rc==2 by default, BUT keep them if Read-only OR Bookmarked-only is active.
    if (!(bookmarkedOnly || readOnly)) {
      list.removeWhere((it) => _rcOf(it) == 2);
    }


   // 2) Bookmark filter
    if (bookmarkedOnly) {
      list.retainWhere((e) => e.isBookmarked);
    }

  // 3) Read filter
 if (unreadOnly) {
      list.retainWhere((e) => _rcOf(e) == 0);
    } else if (readOnly) {
      list.retainWhere((e) => _rcOf(e) >= 1); // includes hidden (2)
    }

  // 4) Sort
    int t(FeedItem x) => x.pubDate?.millisecondsSinceEpoch ?? 0;
    list.sort(
      (a, b) => _sortOrder == _LocalSortOrder.latestFirst
      ? t(b).compareTo(t(a)): t(a).compareTo(t(b)),
    );

    return list;
  }


  @override
  Widget build(BuildContext context) {
    final rss = context.watch<RssProvider>();
    final List<FeedItem> allFeeds = _buildAllFeeds(rss);

    return Scaffold(
      key: _scaffoldKey,
      drawer: const _NewsDrawer(),

      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(icon: const Icon(Icons.menu), onPressed: _openDrawer),
        title: const Text('News', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.tune), onPressed: () => _openFilterSheet(context)),
          IconButton(icon: const Icon(Icons.search), onPressed: () => _openSearch(context)),
        ],
      ),

      body: RefreshIndicator(
        onRefresh: rss.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            // ---------- MAIN FEED ----------
            Row(
              children: [
                Text(
                  _hasActiveFilter ? 'All feeds (filtered)' : 'All feeds',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (_hasActiveFilter)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _readFilter = _LocalReadFilter.all;
                      _bmFilter = _LocalBookmarkFilter.all;
                      _sortOrder = _LocalSortOrder.latestFirst;
                    }),
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            _UnreadChip(count: rss.unreadCount),

            if (rss.error != null) ...[
              const SizedBox(height: 8),
              Text('Error: ${rss.error}', style: const TextStyle(color: Colors.red)),
            ],

            if (rss.loading && allFeeds.isEmpty) ...const [
              SizedBox(height: 64),
              Center(child: CircularProgressIndicator()),
            ],

            const SizedBox(height: 8),
            ...allFeeds.map((it) => _ArticleRow(item: it)),
            const SizedBox(height: 24),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.read<RssProvider>().hideReadNow(),
        backgroundColor: Theme.of(context).colorScheme.primary,
        shape: const StadiumBorder(),
        icon: const Icon(Icons.done_all),
        label: const Text('Hide read'),
      ),
    );
  }
}

// ---------------- Filter bottom sheet (LOCAL controls) ----------------

class _FilterResult {
  final _LocalReadFilter read;
  final _LocalBookmarkFilter bm;
  final _LocalSortOrder sort;
  const _FilterResult(this.read, this.bm, this.sort);
}

class _FilterSheet extends StatefulWidget {
  final _LocalReadFilter readFilter;
  final _LocalBookmarkFilter bmFilter;
  final _LocalSortOrder sortOrder;
  const _FilterSheet({
    required this.readFilter,
    required this.bmFilter,
    required this.sortOrder,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late _LocalReadFilter _read;
  late _LocalBookmarkFilter _bm;
  late _LocalSortOrder _sort;

  @override
  void initState() {
    super.initState();
    _read = widget.readFilter;
    _bm = widget.bmFilter;
    _sort = widget.sortOrder;
  }

  Widget _choice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    final border = Colors.grey.shade400;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? Colors.transparent : border),
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Read filter
            const Text('Read filter', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12, runSpacing: 12, children: [
                _choice(
                  label: 'All',
                  selected: _read == _LocalReadFilter.all,
                  onTap: () => setState(() => _read = _LocalReadFilter.all),
                ),
                _choice(
                  label: 'Unread only',
                  selected: _read == _LocalReadFilter.unreadOnly,
                  onTap: () => setState(() => _read = _LocalReadFilter.unreadOnly),
                ),
                _choice(
                  label: 'Read only',
                  selected: _read == _LocalReadFilter.readOnly,
                  onTap: () => setState(() => _read = _LocalReadFilter.readOnly),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Bookmark filter
            const Text('Bookmark filter', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12, runSpacing: 12, children: [
                _choice(
                  label: 'All',
                  selected: _bm == _LocalBookmarkFilter.all,
                  onTap: () => setState(() => _bm = _LocalBookmarkFilter.all),
                ),
                _choice(
                  label: 'Bookmarked only',
                  selected: _bm == _LocalBookmarkFilter.bookmarkedOnly,
                  onTap: () => setState(() => _bm = _LocalBookmarkFilter.bookmarkedOnly),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Sort
            const Text('Sort by', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12, runSpacing: 12, children: [
                _choice(
                  label: 'Latest first',
                  selected: _sort == _LocalSortOrder.latestFirst,
                  onTap: () => setState(() => _sort = _LocalSortOrder.latestFirst),
                ),
                _choice(
                  label: 'Oldest first',
                  selected: _sort == _LocalSortOrder.oldestFirst,
                  onTap: () => setState(() => _sort = _LocalSortOrder.oldestFirst),
                ),
              ],
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.pop(context, _FilterResult(_read, _bm, _sort)),
                  icon: const Icon(Icons.check),
                  label: const Text('Apply'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    const _FilterResult(
                      _LocalReadFilter.all,
                      _LocalBookmarkFilter.all,
                      _LocalSortOrder.latestFirst,
                    ),
                  ),
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Drawer ----------------

class _NewsDrawer extends StatelessWidget {
  const _NewsDrawer();

  @override
  Widget build(BuildContext context) {
    final rss = context.watch<RssProvider>();
    final settings = context.watch<SettingsProvider>();
    final accent = Theme.of(context).colorScheme.primary;

    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(16)),
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
                    child: Text('Feed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_copy_outlined),
                    title: const Text('All feeds'),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  for (final source in rss.sources)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        source.title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                    ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: const Text('Add more feed'),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FeedPage()));
                    },
                  ),
                  const Divider(height: 24, thickness: 1),
                  ListTile(
                    leading: const Icon(Icons.settings),
                    title: const Text('Settings'),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.dark_mode),
                        const SizedBox(width: 16),
                        const Expanded(child: Text('Dark theme', style: TextStyle(fontSize: 16))),
                        // Non-deprecated APIs
                        Switch(
                          value: settings.darkTheme,
                          thumbColor: WidgetStateProperty.resolveWith<Color?>(
                            (states) => states.contains(WidgetState.selected) ? accent : null,
                          ),
                          trackColor: WidgetStateProperty.resolveWith<Color?>(
                            (states) =>
                                states.contains(WidgetState.selected) ? accent.withValues(alpha: 0.35) : null,
                          ),
                          onChanged: (v) => context.read<SettingsProvider>().toggleDarkTheme(v),
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

// ---------------- UI bits ----------------

class _UnreadChip extends StatelessWidget {
  final int count;
  const _UnreadChip({required this.count});

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final bg = Colors.grey.shade300;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text('$count unread', style: TextStyle(fontSize: 13, color: textColor)),
    );
  }
}

class _ArticleRow extends StatelessWidget {
  final FeedItem item;
  const _ArticleRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final rss = context.read<RssProvider>();
    final ago = rss.niceTimeAgo(item.pubDate);
    final isBookmarked = item.isBookmarked;
    final bool isReadLike = item.isRead >= 1; // 1 and 2 both count as "read"
    final bool hasMainArticle = (item.mainText ?? '').isNotEmpty;
    final Color unreadTitleColor = Theme.of(context).colorScheme.onSurface;
    final Color readTitleColor = Colors.grey.shade600;

    final TextStyle titleStyle = TextStyle(
      color: isReadLike ? readTitleColor : unreadTitleColor,
      fontSize: 18,
      fontWeight: isReadLike ? FontWeight.w400 : FontWeight.w600,
      height: 1.3,
    );

    final Color metaColor = item.isRead==1 ? Colors.grey.shade500 : Colors.grey.shade700;

    final thumbUrl = item.imageUrl ?? '';
    final url = item.link; // if your model uses String?, make it `item.link ?? ''`
    final Color accentRing = hasMainArticle ? Colors.green : Colors.grey.shade400;
    return InkWell(
      onTap: () {
        rss.markRead(item);
        if (url.isEmpty) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('No article URL available.')));
          return;
        }
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArticleWebviewPage(url: url)));
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // LEFT
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.sourceTitle,
                    style: TextStyle(color: metaColor, fontSize: 14, fontWeight: FontWeight.w500, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  Text(item.title, style: titleStyle),
                  const SizedBox(height: 8),
                  Text(ago, style: TextStyle(fontSize: 14, color: metaColor, height: 1.4)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                          size: 20,
                          color: item.isRead==1 ? Colors.grey.shade600 : null,
                        ),
                        onPressed: () => rss.toggleBookmark(item),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(Icons.more_vert, size: 20, color: item.isRead==1 ? Colors.grey.shade600 : null),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),

            // RIGHT thumb (null-safe)
            SizedBox(
              width: 90,
              height: 90,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accentRing, width: 3),
                ),
                padding: const EdgeInsets.all(4),
                child: ClipOval(
                  child: thumbUrl.isNotEmpty
                      ? Image.network(thumbUrl, fit: BoxFit.cover)
                      : Container(
                          color: Colors.grey.shade300,
                          alignment: Alignment.center,
                          child: const Icon(Icons.image_not_supported),
                        ),
                ),),
            ),
          ],
        ),
      ),
    );
  }
}
