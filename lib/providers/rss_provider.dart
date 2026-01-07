// lib/providers/rss_provider.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/feed_item.dart';
import '../models/feed_source.dart';
import '../data/feed_repository.dart';

/// Old UI uses this
enum SortOrder {
  latestFirst,
  oldestFirst,
}

/// Old UI uses this
enum BookmarkFilter {
  all,
  bookmarkedOnly,
}

/// We already had this, keep it
enum ReadFilter {
  all,
  unreadOnly,
  readOnly,
}

class RssProvider extends ChangeNotifier {
  final FeedRepository repo;

  RssProvider({required this.repo});

  // ---------------------------------------------------------------------------
  // STATE
  // ---------------------------------------------------------------------------
  final List<FeedItem> _items = [];
  final List<FeedSource> _sources = [];

  bool _loading = false;
  String? _error;

  // these 3 drive the filters/sorting
  SortOrder _sortOrder = SortOrder.latestFirst;
  BookmarkFilter _bookmarkFilter = BookmarkFilter.all;
  ReadFilter _readFilter = ReadFilter.all;

  String _searchQuery = '';

  // ---------------------------------------------------------------------------
  // GETTERS
  // ---------------------------------------------------------------------------
  bool get loading => _loading;
  String? get error => _error;

  List<FeedItem> get items => List.unmodifiable(_items);
  List<FeedSource> get sources => List.unmodifiable(_sources);

  int get unreadCount => _items.where((e) => e.isRead == 0).length;

  // for bottom sheet chips
  bool get isLatestFirst => _sortOrder == SortOrder.latestFirst;
  bool get isOldestFirst => _sortOrder == SortOrder.oldestFirst;

  bool get showAllArticles =>
      _bookmarkFilter == BookmarkFilter.all && _readFilter == ReadFilter.all;
  bool get showBookmarkedOnly =>
      _bookmarkFilter == BookmarkFilter.bookmarkedOnly;
  bool get showUnreadOnly => _readFilter == ReadFilter.unreadOnly;
  bool get showReadOnly => _readFilter == ReadFilter.readOnly;
List<FeedItem> get allItems => List.unmodifiable(_items);

  String get searchQuery => _searchQuery;

  // ---------------------------------------------------------------------------
  // VISIBLE LIST (this is what news_page.dart shows)
  // ---------------------------------------------------------------------------
  List<FeedItem> get visibleItems {
    // Always hide entries that were archived (isRead == 2)
    Iterable<FeedItem> data = _items.where((e) => e.isRead != 2);

    // 1) bookmark filter
    if (_bookmarkFilter == BookmarkFilter.bookmarkedOnly) {
      data = data.where((e) => e.isBookmarked);
    }

    // 2) read filter
    switch (_readFilter) {
      case ReadFilter.all:
        break;
      case ReadFilter.unreadOnly:
        // Only show genuinely unread items; exclude archived entries
        data = data.where((e) => e.isRead == 0);
        break;
      case ReadFilter.readOnly:
        data = data.where((e) => (e.isRead==1));
        break;
    }

    // 3) sorting
    final list = data.toList()
      ..sort((a, b) {
        final ad = a.pubDate?.millisecondsSinceEpoch ?? 0;
        final bd = b.pubDate?.millisecondsSinceEpoch ?? 0;
        final cmp = ad.compareTo(bd);
        return _sortOrder == SortOrder.latestFirst ? -cmp : cmp;
      });

    return list;
  }

  // for NewsSearchPage – apply text search on top of _items
  List<FeedItem> get searchResults {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _items.where((item) {
      // Hide archived items from search results too
      if (item.isRead == 2) return false;
      return item.title.toLowerCase().contains(q) ||
          (item.description ?? '').toLowerCase().contains(q) ||
          item.sourceTitle.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) {
        final ad = a.pubDate?.millisecondsSinceEpoch ?? 0;
        final bd = b.pubDate?.millisecondsSinceEpoch ?? 0;
        return bd.compareTo(ad);
      });
  }

  // ---------------------------------------------------------------------------
  // LIFECYCLE / LOADING
  // ---------------------------------------------------------------------------
  Future<void> loadInitial({bool skipCleanup = false}) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final sources = await repo.getAllSources();

      // FETCH + UPSERT newest items into DB
      await repo.loadAll(sources);

      // Trim per-feed to limit (bookmarks never deleted)
      // Skip cleanup after restore to keep all imported articles
      if (!skipCleanup) {
        await repo.cleanupOldArticlesForSources(sources);
      } else {
        debugPrint('RssProvider: Skipping article cleanup (restore mode)');
      }

      // Read trimmed list from DB (no extra network)
      final merged = await repo.readAllFromDb();

      _sources
        ..clear()
        ..addAll(sources);
      _items
        ..clear()
        ..addAll(merged);

      _scheduleBackgroundBackfill();
    } catch (e) {
      _error = '$e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final sources = await repo.getAllSources();

      // FETCH + UPSERT newest items into DB
      await repo.loadAll(sources);

      // Trim per-feed to limit (bookmarks never deleted)
      await repo.cleanupOldArticlesForSources(sources);

      // Read trimmed list from DB (no extra network)
      final merged = await repo.readAllFromDb();

      _sources
        ..clear()
        ..addAll(sources);
      _items
        ..clear()
        ..addAll(merged);
_scheduleBackgroundBackfill();
    } catch (e) {
      _error = '$e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // FEED MGMT
  // ---------------------------------------------------------------------------
  Future<void> addSource(FeedSource source) async {
    await repo.addSource(source);
    await refresh();
  }

  Future<void> deleteSource(FeedSource source) async {
    await repo.deleteSource(source);
    await refresh();
  }

  Future<void> updateFeedTitle(int id, String newTitle) async {
    await repo.updateFeedTitle(id, newTitle);
    await refresh();
  }

  // ---------------------------------------------------------------------------
  // ARTICLE ACTIONS
  // ---------------------------------------------------------------------------
  Future<void> toggleBookmark(FeedItem item) async {
    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx == -1) return;

    final updated = item.copyWith(isBookmarked: !item.isBookmarked);
    _items[idx] = updated;
    notifyListeners();

    await repo.setBookmark(item.id, updated.isBookmarked);
  }

  Future<void> markRead(FeedItem item, {int read = 1}) async {
    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx == -1) return;

    final updated = item.copyWith(isRead: read);
    _items[idx] = updated;
    notifyListeners();

    await repo.setRead(item.id, read);
  }
  Future<void> hideOlderThan(FeedItem item) async {
    final cutoff = item.pubDate;
    if (cutoff == null) return;

    _loading = true;
    notifyListeners();

    try {
      await repo.hideOlderThan(cutoff);
      final merged = await repo.readAllFromDb();
      _items
        ..clear()
        ..addAll(merged);
    } catch (e) {
      _error = '$e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
bool _backfillInProgress = false;
bool _shouldCancelBackfill = false;

 void _scheduleBackgroundBackfill() {
    unawaited(Future.microtask(backfillArticleContent));
  }

  void _restartBackfillWithNewPriority() {
    if (_backfillInProgress) {
      // Signal current backfill to stop
      _shouldCancelBackfill = true;
      debugPrint('RssProvider: Signaling enrichment to restart with new priority');
    }
    // Schedule new backfill (will start after current one stops)
    _scheduleBackgroundBackfill();
  }
  Future<void> backfillArticleContent() async {
    if (_backfillInProgress) return;
    _backfillInProgress = true;
    _shouldCancelBackfill = false;
    try {
      debugPrint('RssProvider: Starting background article enrichment for ${_items.length} items (one-by-one updates)');

      int enrichedCount = 0;
      int processedCount = 0;

      // FIRST: Filter to only items that need enrichment
      final itemsNeedingEnrichment = _items.where((item) {
        if (item.link.isEmpty) return false;
        final existingText = (item.mainText ?? '').trim();

        // Only skip if article has SUBSTANTIAL content (500+ chars)
        // This prevents skipping articles with short RSS descriptions
        final hasSubstantialContent = existingText.length >= 500;
        final hasImage = (item.imageUrl ?? '').trim().isNotEmpty;

        // Enrich if missing substantial content OR missing image
        return !hasSubstantialContent || !hasImage;
      }).toList();

      debugPrint('RssProvider: ${itemsNeedingEnrichment.length} of ${_items.length} articles need enrichment');

      // SECOND: Prioritize visible items first
      final visibleIds = visibleItems.map((e) => e.id).toSet();

      // Separate visible and hidden items (from filtered list)
      final visibleNeedingEnrichment = <FeedItem>[];
      final hiddenNeedingEnrichment = <FeedItem>[];

      for (final item in itemsNeedingEnrichment) {
        if (visibleIds.contains(item.id)) {
          visibleNeedingEnrichment.add(item);
        } else {
          hiddenNeedingEnrichment.add(item);
        }
      }

      // Sort both lists based on user's preference
      final sortFn = (FeedItem a, FeedItem b) {
        final ad = a.pubDate?.millisecondsSinceEpoch ?? 0;
        final bd = b.pubDate?.millisecondsSinceEpoch ?? 0;
        final cmp = ad.compareTo(bd);
        return _sortOrder == SortOrder.latestFirst ? -cmp : cmp;
      };

      visibleNeedingEnrichment.sort(sortFn);
      hiddenNeedingEnrichment.sort(sortFn);

      // Process visible items first, then hidden ones
      final sortedItems = [...visibleNeedingEnrichment, ...hiddenNeedingEnrichment];

      debugPrint('RssProvider: Enriching ${visibleNeedingEnrichment.length} visible items first, then ${hiddenNeedingEnrichment.length} hidden items');
      debugPrint('RssProvider: Enrichment order: ${_sortOrder == SortOrder.oldestFirst ? "OLDEST" : "NEWEST"} first');

      // Debug: Show first and last article dates to verify sort order
      if (sortedItems.isNotEmpty) {
        final first = sortedItems.first;
        final last = sortedItems.last;
        debugPrint('RssProvider: 🔍 FIRST article to enrich: "${first.title}" (${first.pubDate})');
        debugPrint('RssProvider: 🔍 LAST article to enrich: "${last.title}" (${last.pubDate})');
      }

      // Process each article individually to update UI progressively
      for (final item in sortedItems) {
        // Check if we should cancel and restart with new priority
        if (_shouldCancelBackfill) {
          debugPrint('RssProvider: Enrichment cancelled, restarting with new filter priority');
          break;
        }

        processedCount++;

        // Enrich this article (already filtered, no need to check again)
        try {
          debugPrint('RssProvider: [$processedCount/${sortedItems.length}] 📖 NOW ENRICHING: "${item.title}" (Date: ${item.pubDate})');
          final content = await repo.populateArticleContent([item]);

          if (content.isNotEmpty && content.containsKey(item.id)) {
            // Find the item in the original list and update it
            final idx = _items.indexWhere((e) => e.id == item.id);
            if (idx != -1) {
              _items[idx] = _items[idx].copyWith(
                mainText: content[item.id]!.mainText ?? _items[idx].mainText,
                imageUrl: content[item.id]!.imageUrl ?? _items[idx].imageUrl,
              );
              enrichedCount++;

              // Update UI immediately after each article is enriched
              debugPrint('RssProvider: ✓ Article $enrichedCount enriched - updating UI now!');
              notifyListeners();

              // Small delay to make the progressive update visible
              await Future.delayed(const Duration(milliseconds: 150));
            }
          } else {
            debugPrint('RssProvider: ⚠ Article $processedCount failed to enrich');
          }
        } catch (e) {
          debugPrint('RssProvider: ✗ Error enriching article $processedCount: $e');
        }
      }

      debugPrint('RssProvider: ✓ All done! Enriched $enrichedCount of $processedCount articles');
    } finally {
      _backfillInProgress = false;
    }
  }
  // ---------------------------------------------------------------------------
  // FILTERS / SORTING (the ones news_page.dart calls)
  // ---------------------------------------------------------------------------
  void setSortOrder(SortOrder order) async {
    if (_sortOrder == order) return;
    _sortOrder = order;

    // Save to SharedPreferences for background task
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sortOrder', order == SortOrder.latestFirst ? 'latestFirst' : 'oldestFirst');

    notifyListeners();
    // Restart enrichment with new sort priority
    _restartBackfillWithNewPriority();
  }

  void setBookmarkFilter(BookmarkFilter filter) {
    if (_bookmarkFilter == filter) return;
    _bookmarkFilter = filter;
    notifyListeners();
    // Restart enrichment to prioritize newly visible items
    _restartBackfillWithNewPriority();
  }

  void setReadFilter(ReadFilter filter) {
    if (_readFilter == filter) return;
    _readFilter = filter;
    notifyListeners();
    // Restart enrichment to prioritize newly visible items
    _restartBackfillWithNewPriority();
  }

  void setSearchQuery(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // UTIL
  // ---------------------------------------------------------------------------
  String niceTimeAgo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);

    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  Future<void> hideReadNow() async {
  if (_loading) return;
  _loading = true;
  notifyListeners();

  try {
    await repo.hideAllRead();                 // set isRead = 2
    final merged = await repo.readAllFromDb();// reload from DB (2 is excluded)
    _items..clear()..addAll(merged);
  } catch (e) {
    _error = '$e';
  } finally {
    _loading = false;
    notifyListeners();
  }
}

}
