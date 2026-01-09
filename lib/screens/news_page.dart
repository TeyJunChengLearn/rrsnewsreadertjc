// lib/screens/news_page.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/feed_item.dart';
import '../providers/rss_provider.dart';
import '../providers/settings_provider.dart';

import 'article_webview_page.dart' show ArticleWebviewPage, isGlobalTtsPlaying, getGlobalTtsArticleTitle, getGlobalTtsArticleId, getGlobalTtsProgress, stopGlobalTts, stopGlobalTtsForArticle, toggleGlobalTts;
import 'feed_page.dart';
import 'news_search_page.dart';
import 'settings_page.dart';
import 'trash_page.dart';

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

  static const _kSortOrderKey = 'news_sort_order';

  // TTS state tracking
  Timer? _ttsCheckTimer;
  bool _isTtsPlaying = false;
  String _ttsArticleTitle = '';
  String _ttsProgress = '';

  // Selection mode state
  bool _isSelectionMode = false;
  Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadSavedSortOrder();
    _startTtsStateCheck();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<RssProvider>().backfillArticleContent();
    });
  }

  @override
  void dispose() {
    _ttsCheckTimer?.cancel();
    super.dispose();
  }

  void _startTtsStateCheck() {
    // Check immediately after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateTtsState();
    });

    // Then check periodically to update UI
    _ttsCheckTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _updateTtsState();
    });
  }

  void _updateTtsState() {
    if (!mounted) return;
    final playing = isGlobalTtsPlaying();
    final title = getGlobalTtsArticleTitle();
    final progress = getGlobalTtsProgress();

    if (playing != _isTtsPlaying || title != _ttsArticleTitle || progress != _ttsProgress) {
      setState(() {
        _isTtsPlaying = playing;
        _ttsArticleTitle = title;
        _ttsProgress = progress;
      });
    }
  }

  // Local filter state (defaults = show all)
  _LocalReadFilter _readFilter = _LocalReadFilter.all;
  _LocalBookmarkFilter _bmFilter = _LocalBookmarkFilter.all;
  _LocalSortOrder _sortOrder = _LocalSortOrder.latestFirst;
  String? _selectedSourceTitle; // null = all feeds, otherwise filter by this source title

  bool get _hasActiveFilter =>
      _readFilter != _LocalReadFilter.all ||
      _bmFilter != _LocalBookmarkFilter.all ||
      _selectedSourceTitle != null;

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  // Selection mode methods
  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _selectAll(List<FeedItem> items) {
    setState(() {
      _selectedIds = items.map((e) => e.id).toSet();
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final rss = context.read<RssProvider>();
    final itemsToDelete = rss.allItems
        .where((e) => _selectedIds.contains(e.id))
        .toList();

    // Stop TTS for any selected articles
    for (final item in itemsToDelete) {
      await stopGlobalTtsForArticle(item.id);
    }

    // Hide all selected (move to trash)
    for (final item in itemsToDelete) {
      await rss.hideArticle(item);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${itemsToDelete.length} article(s) moved to trash'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              for (final item in itemsToDelete) {
                await rss.restoreFromTrash(item);
              }
            },
          ),
        ),
      );
      _clearSelection();
    }
  }

  void _enterSelectionMode(String id) {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(id);
    });
  }

  Future<void> _loadSavedSortOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kSortOrderKey);
    if (!mounted) return;

    final loadedOrder = saved == 'oldest'
        ? _LocalSortOrder.oldestFirst
        : _LocalSortOrder.latestFirst;

    setState(() {
      _sortOrder = loadedOrder;
    });

    // CRITICAL: Sync with RssProvider on app start
    final rss = context.read<RssProvider>();
    final providerSortOrder = loadedOrder == _LocalSortOrder.latestFirst
        ? SortOrder.latestFirst
        : SortOrder.oldestFirst;
    rss.setSortOrder(providerSortOrder);
  }

  Future<void> _persistSortOrder(_LocalSortOrder order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kSortOrderKey,
      order == _LocalSortOrder.latestFirst ? 'latest' : 'oldest',
    );
  }

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

      _persistSortOrder(result.sort);

      // CRITICAL: Sync with RssProvider to update enrichment order
      if (!mounted) return;
      final rss = context.read<RssProvider>();

      // Map local sort order to provider sort order
      final providerSortOrder = result.sort == _LocalSortOrder.latestFirst
          ? SortOrder.latestFirst
          : SortOrder.oldestFirst;
      rss.setSortOrder(providerSortOrder);

      // Map local filters to provider filters
      final providerReadFilter = result.read == _LocalReadFilter.unreadOnly
          ? ReadFilter.unreadOnly
          : result.read == _LocalReadFilter.readOnly
              ? ReadFilter.readOnly
              : ReadFilter.all;
      rss.setReadFilter(providerReadFilter);

      final providerBookmarkFilter = result.bm == _LocalBookmarkFilter.bookmarkedOnly
          ? BookmarkFilter.bookmarkedOnly
          : BookmarkFilter.all;
      rss.setBookmarkFilter(providerBookmarkFilter);
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

    // 0) Source filter - filter by selected feed/source
    if (_selectedSourceTitle != null) {
      list.retainWhere((e) => e.sourceTitle == _selectedSourceTitle);
    }

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
          ? t(b).compareTo(t(a))
          : t(a).compareTo(t(b)),
    );

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final rss = context.watch<RssProvider>();
    final List<FeedItem> allFeeds = _buildAllFeeds(rss);

    return Scaffold(
      key: _scaffoldKey,
      drawer: _isSelectionMode ? null : _NewsDrawer(
        selectedSourceTitle: _selectedSourceTitle,
        onSourceSelected: (title) => setState(() => _selectedSourceTitle = title),
      ),
      appBar: AppBar(
        titleSpacing: 0,
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
                tooltip: 'Cancel selection',
              )
            : IconButton(icon: const Icon(Icons.menu), onPressed: _openDrawer),
        title: _isSelectionMode
            ? Text('${_selectedIds.length} selected',
                style: const TextStyle(fontWeight: FontWeight.w600))
            : const Text('News', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: _isSelectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  onPressed: () => _selectAll(allFeeds),
                  tooltip: 'Select all',
                ),
              ]
            : [
                IconButton(
                    icon: const Icon(Icons.tune),
                    onPressed: () => _openFilterSheet(context)),
                IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () => _openSearch(context)),
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
                Expanded(
                  child: Text(
                    _selectedSourceTitle ?? (_hasActiveFilter ? 'All feeds (filtered)' : 'All feeds'),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_hasActiveFilter)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _readFilter = _LocalReadFilter.all;
                        _bmFilter = _LocalBookmarkFilter.all;
                        _selectedSourceTitle = null;
                      });

                      // Sync with RssProvider to reset filters (keep sort order unchanged)
                      final rss = context.read<RssProvider>();
                      rss.setReadFilter(ReadFilter.all);
                      rss.setBookmarkFilter(BookmarkFilter.all);
                    },
                    icon: const Icon(Icons.clear),
                    label: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            _UnreadChip(count: rss.unreadCount),

            if (rss.error != null) ...[
              const SizedBox(height: 8),
              Text('Error: ${rss.error}',
                  style: const TextStyle(color: Colors.red)),
            ],

            if (rss.loading && allFeeds.isEmpty) ...const [
              SizedBox(height: 64),
              Center(child: CircularProgressIndicator()),
            ],

            const SizedBox(height: 8),
            ...List.generate(allFeeds.length, (index) {
              final item = allFeeds[index];
              // Pass the full article list for navigation (respects current sort order and filters)
              return _ArticleRow(
                item: item,
                allArticles: allFeeds,
                isSelectionMode: _isSelectionMode,
                isSelected: _selectedIds.contains(item.id),
                onToggleSelection: () => _toggleSelection(item.id),
                onLongPress: () => _enterSelectionMode(item.id),
              );
            }),
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
      bottomNavigationBar: _isSelectionMode && _selectedIds.isNotEmpty
          ? _SelectionActionBar(
              selectedCount: _selectedIds.length,
              onDelete: _deleteSelected,
            )
          : (_isTtsPlaying || _ttsArticleTitle.isNotEmpty
              ? _TtsControlBar(
                  isPlaying: _isTtsPlaying,
                  articleTitle: _ttsArticleTitle,
                  progress: _ttsProgress,
                  onPlayPause: () async {
                    await toggleGlobalTts();
                    setState(() {
                      _isTtsPlaying = isGlobalTtsPlaying();
                    });
                  },
                  onStop: () async {
                    await stopGlobalTts();
                    setState(() {
                      _isTtsPlaying = false;
                      _ttsArticleTitle = '';
                      _ttsProgress = '';
                    });
                  },
                  onTap: () {
                    // Navigate to the currently playing article
                    final articleId = getGlobalTtsArticleId();
                    if (articleId.isEmpty) return;

                    // Find the article in the list
                    final article = allFeeds.cast<FeedItem?>().firstWhere(
                      (a) => a?.id == articleId,
                      orElse: () => null,
                    );

                    if (article != null) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ArticleWebviewPage(
                            articleId: article.id,
                            url: article.link,
                            title: article.title,
                            sourceTitle: article.sourceTitle,
                            initialMainText: article.mainText,
                            initialImageUrl: article.imageUrl,
                            allArticles: allFeeds,
                            autoPlay: false, // Don't restart, TTS is already playing
                          ),
                        ),
                      );
                    }
                  },
                )
              : null),
    );
  }
}

// ---------------- Selection Action Bar ----------------

class _SelectionActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onDelete;

  const _SelectionActionBar({
    required this.selectedCount,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      elevation: 8,
      color: isDark ? Colors.grey.shade900 : Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: Text('Delete $selectedCount article(s)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- TTS Control Bar ----------------

class _TtsControlBar extends StatelessWidget {
  final bool isPlaying;
  final String articleTitle;
  final String progress;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;
  final VoidCallback onTap;

  const _TtsControlBar({
    required this.isPlaying,
    required this.articleTitle,
    required this.progress,
    required this.onPlayPause,
    required this.onStop,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      elevation: 8,
      color: isDark ? Colors.grey.shade900 : Colors.white,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Play/Pause button
                IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    size: 40,
                    color: theme.colorScheme.primary,
                  ),
                  onPressed: onPlayPause,
                ),
                const SizedBox(width: 8),
                // Article info
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        articleTitle.isNotEmpty ? articleTitle : 'Reading...',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (progress.isNotEmpty)
                        Text(
                          isPlaying ? 'Playing $progress' : 'Paused $progress',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
                // Stop button
                IconButton(
                  icon: Icon(
                    Icons.stop_circle_outlined,
                    size: 32,
                    color: Colors.red.shade400,
                  ),
                  onPressed: onStop,
                  tooltip: 'Stop reading',
                ),
              ],
            ),
          ),
        ),
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
            const Text('Read filter',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _choice(
                  label: 'All',
                  selected: _read == _LocalReadFilter.all,
                  onTap: () => setState(() => _read = _LocalReadFilter.all),
                ),
                _choice(
                  label: 'Unread only',
                  selected: _read == _LocalReadFilter.unreadOnly,
                  onTap: () =>
                      setState(() => _read = _LocalReadFilter.unreadOnly),
                ),
                _choice(
                  label: 'Read only',
                  selected: _read == _LocalReadFilter.readOnly,
                  onTap: () =>
                      setState(() => _read = _LocalReadFilter.readOnly),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Bookmark filter
            const Text('Bookmark filter',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _choice(
                  label: 'All',
                  selected: _bm == _LocalBookmarkFilter.all,
                  onTap: () => setState(() => _bm = _LocalBookmarkFilter.all),
                ),
                _choice(
                  label: 'Bookmarked only',
                  selected: _bm == _LocalBookmarkFilter.bookmarkedOnly,
                  onTap: () =>
                      setState(() => _bm = _LocalBookmarkFilter.bookmarkedOnly),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Sort
            const Text('Sort by',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _choice(
                  label: 'Latest first',
                  selected: _sort == _LocalSortOrder.latestFirst,
                  onTap: () =>
                      setState(() => _sort = _LocalSortOrder.latestFirst),
                ),
                _choice(
                  label: 'Oldest first',
                  selected: _sort == _LocalSortOrder.oldestFirst,
                  onTap: () =>
                      setState(() => _sort = _LocalSortOrder.oldestFirst),
                ),
              ],
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                TextButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, _FilterResult(_read, _bm, _sort)),
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
  final String? selectedSourceTitle;
  final void Function(String? sourceTitle) onSourceSelected;

  const _NewsDrawer({
    required this.selectedSourceTitle,
    required this.onSourceSelected,
  });

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
                    child: Text('Feed',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.folder_copy_outlined,
                      color: selectedSourceTitle == null ? accent : null,
                    ),
                    title: Text(
                      'All feeds',
                      style: TextStyle(
                        fontWeight: selectedSourceTitle == null
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selectedSourceTitle == null ? accent : null,
                      ),
                    ),
                    selected: selectedSourceTitle == null,
                    onTap: () {
                      onSourceSelected(null);
                      Navigator.of(context).pop();
                    },
                  ),
                  for (final source in rss.sources)
                    ListTile(
                      leading: Icon(
                        Icons.rss_feed,
                        color: selectedSourceTitle == source.title ? accent : null,
                      ),
                      title: Text(
                        source.title,
                        style: TextStyle(
                          fontWeight: selectedSourceTitle == source.title
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selectedSourceTitle == source.title ? accent : null,
                        ),
                      ),
                      selected: selectedSourceTitle == source.title,
                      onTap: () {
                        onSourceSelected(source.title);
                        Navigator.of(context).pop();
                      },
                    ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: const Text('Add more feed'),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const FeedPage()));
                    },
                  ),
                  const Divider(height: 24, thickness: 1),
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Trash'),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const TrashPage()));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings),
                    title: const Text('Settings'),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const SettingsPage()));
                    },
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.dark_mode),
                        const SizedBox(width: 16),
                        const Expanded(
                            child: Text('Dark theme',
                                style: TextStyle(fontSize: 16))),
                        // Non-deprecated APIs
                        Switch(
                          value: settings.darkTheme,
                          thumbColor: WidgetStateProperty.resolveWith<Color?>(
                            (states) => states.contains(WidgetState.selected)
                                ? accent
                                : null,
                          ),
                          trackColor: WidgetStateProperty.resolveWith<Color?>(
                            (states) => states.contains(WidgetState.selected)
                                ? accent.withValues(alpha: 0.35)
                                : null,
                          ),
                          onChanged: (v) => context
                              .read<SettingsProvider>()
                              .toggleDarkTheme(v),
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
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text('$count unread',
          style: TextStyle(fontSize: 13, color: textColor)),
    );
  }
}

class _ArticleRow extends StatelessWidget {
  final FeedItem item;
  final List<FeedItem> allArticles;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onToggleSelection;
  final VoidCallback onLongPress;

  const _ArticleRow({
    required this.item,
    required this.allArticles,
    this.isSelectionMode = false,
    this.isSelected = false,
    required this.onToggleSelection,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final rss = context.watch<RssProvider>();

    // Find the latest version of this item from the provider for live updates
    final currentItem = rss.items.firstWhere(
      (i) => i.id == item.id,
      orElse: () => item,
    );

    final ago = rss.niceTimeAgo(currentItem.pubDate);
    final agoLabel = ago.isNotEmpty ? ago : 'this article';
    final isBookmarked = currentItem.isBookmarked;
    final bool isReadLike = currentItem.isRead >= 1; // 1 and 2 both count as "read"
    final bool hasMainArticle = (currentItem.mainText ?? '').isNotEmpty;
    final bool hasFailed = currentItem.enrichmentAttempts >= 5;

    final Color unreadTitleColor = Theme.of(context).colorScheme.onSurface;
    final Color readTitleColor = Colors.grey.shade600;

    final TextStyle titleStyle = TextStyle(
      color: isReadLike ? readTitleColor : unreadTitleColor,
      fontSize: 18,
      fontWeight: isReadLike ? FontWeight.w400 : FontWeight.w600,
      height: 1.3,
    );

    final Color metaColor =
        currentItem.isRead == 1 ? Colors.grey.shade500 : Colors.grey.shade700;

    final thumbUrl = currentItem.imageUrl ?? '';
    final url =
        currentItem.link; // if your model uses String?, make it `item.link ?? ''`
    final Color accentRing = hasFailed
        ? Colors.red
        : hasMainArticle
            ? Colors.green
            : Colors.grey.shade400;
    Widget _greyscaleIfMissingContent(Widget child) {
      if (hasMainArticle) return child;
      // Desaturate thumbnail when Readability could not fetch content
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]),
        child: Opacity(opacity: 0.8, child: child),
      );
    }

    final Widget thumb = _greyscaleIfMissingContent(
      thumbUrl.isNotEmpty
          ? Image.network(
              thumbUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            )
          : Container(
              color: Colors.grey.shade300,
              alignment: Alignment.center,
              child: const Icon(Icons.image_not_supported),
            ),
    );
    return InkWell(
      onTap: () {
        if (isSelectionMode) {
          onToggleSelection();
          return;
        }
        rss.markRead(currentItem);
        if (url.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No article URL available.')));
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ArticleWebviewPage(
              articleId: currentItem.id,
              url: url,
              title: currentItem.title,
              sourceTitle: currentItem.sourceTitle,
              initialMainText: currentItem.mainText,
              initialImageUrl: currentItem.imageUrl,
              allArticles: allArticles,
            ),
          ),
        );
      },
      onLongPress: onLongPress,
      child: Container(
        color: isSelected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
            : null,
        child: Padding(
        padding: const EdgeInsets.only(bottom: 24.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Checkbox for selection mode
            if (isSelectionMode) ...[
              Checkbox(
                value: isSelected,
                onChanged: (_) => onToggleSelection(),
              ),
              const SizedBox(width: 8),
            ],
            // LEFT
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentItem.sourceTitle,
                    style: TextStyle(
                        color: metaColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  Text(currentItem.title, style: titleStyle),
                  const SizedBox(height: 8),
                  Text(ago,
                      style: TextStyle(
                          fontSize: 14, color: metaColor, height: 1.4)),
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
                          color: currentItem.isRead == 1 ? Colors.grey.shade600 : null,
                        ),
                        onPressed: () => rss.toggleBookmark(currentItem),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(Icons.share,
                            size: 20,
                            color:
                                currentItem.isRead == 1 ? Colors.grey.shade600 : null),
                        onPressed: () {
                          final shareText =
                              '${currentItem.title}\n${currentItem.link ?? ''}'.trim();
                          Share.share(shareText);
                        },
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(Icons.more_vert,
                            size: 20,
                            color:
                                currentItem.isRead == 1 ? Colors.grey.shade600 : null),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            showDragHandle: true,
                            builder: (ctx) {
                              return SafeArea(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Only show "Mark as unread" if article is already read
                                      if (currentItem.isRead >= 1)
                                        ListTile(
                                          leading: const Icon(Icons.mark_email_unread),
                                          title: const Text('Mark as unread'),
                                          subtitle: const Text(
                                              'Mark this article as unread to listen/read later'),
                                          onTap: () {
                                            Navigator.of(ctx).pop();
                                            rss.markUnread(currentItem);
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                  content: Text(
                                                      'Article marked as unread')),
                                            );
                                          },
                                        ),
                                      ListTile(
                                        leading: const Icon(Icons.share),
                                        title: const Text('Share this article'),
                                        subtitle: Text(currentItem.sourceTitle),
                                        onTap: () {
                                          Navigator.of(ctx).pop();
                                          final shareText =
                                              '${currentItem.title}\n${currentItem.link ?? ''}'
                                                  .trim();
                                          Share.share(shareText);
                                        },
                                      ),
                                      ListTile(
                                        leading:
                                            const Icon(Icons.visibility_off),
                                        title: const Text(
                                            'Hide news before this time'),
                                        subtitle: const Text(
                                            'Mark older items as hidden so they disappear from the list.'),
                                        onTap: () async {
                                          Navigator.of(ctx).pop();
                                          if (currentItem.pubDate == null) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                  content: Text(
                                                      'This article has no timestamp to use.')),
                                            );
                                            return;
                                          }
                                          await rss.hideOlderThan(currentItem);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                  content: Text(
                                                      'Hidden news older than $agoLabel.')),
                                            );
                                          }
                                        },
                                      ),
                                      ListTile(
                                        leading: Icon(Icons.delete_outline,
                                            color: Colors.red.shade400),
                                        title: Text('Delete this article',
                                            style: TextStyle(
                                                color: Colors.red.shade400)),
                                        subtitle: const Text(
                                            'Move to trash. Can be restored or permanently deleted later.'),
                                        onTap: () async {
                                          Navigator.of(ctx).pop();
                                          await stopGlobalTtsForArticle(currentItem.id);
                                          await rss.hideArticle(currentItem);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: const Text(
                                                    'Article moved to trash'),
                                                action: SnackBarAction(
                                                  label: 'Undo',
                                                  onPressed: () async {
                                                    await rss.restoreFromTrash(
                                                        currentItem);
                                                  },
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
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
              child: Stack(
                children: [
                  // Existing thumbnail with border - ensure perfect circle
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: accentRing, width: 3),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: ClipOval(
                      child: SizedBox(
                        width: 82,
                        height: 82,
                        child: thumb,
                      ),
                    ),
                  ),

                  // Badge indicator - green check for success, red X for failure
                  if (hasMainArticle)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    )
                  else if (hasFailed)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      ), // Close Container
    );
  }
}
