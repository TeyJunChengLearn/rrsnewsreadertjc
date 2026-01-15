// lib/providers/rss_provider.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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

      _restartBackfillWithNewPriority();
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
      _restartBackfillWithNewPriority();
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

  Future<void> markUnread(FeedItem item) async {
    await markRead(item, read: 0);
  }

  /// Reset enrichment for an article and mark it as unread
  /// This triggers re-enrichment for articles with incomplete content
  Future<void> resetEnrichment(FeedItem item) async {
    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx == -1) return;

    // Update local state: mark as unread and clear enrichment data
    final updated = item.copyWith(
      isRead: 0,
      mainText: '',
      enrichmentAttempts: 0,
    );
    _items[idx] = updated;
    notifyListeners();

    // Persist to database
    await repo.setRead(item.id, 0);
    await repo.resetEnrichment(item.id);

    // Trigger enrichment restart with new priority
    _restartBackfillWithNewPriority();
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
bool _needsRestart = false;
int _retryCount = 0;
static const int _maxRetries = 3; // Maximum retry attempts

 void _scheduleBackgroundBackfill() {
    unawaited(Future.microtask(backfillArticleContent));
  }

  void _restartBackfillWithNewPriority() {
    if (_backfillInProgress) {
      // Signal current backfill to stop and restart
      _shouldCancelBackfill = true;
      _needsRestart = true;
      debugPrint('RssProvider: Signaling enrichment to restart with new priority');
    } else {
      // Not running, start immediately
      _scheduleBackgroundBackfill();
    }
  }
  Future<void> backfillArticleContent() async {
    if (_backfillInProgress) return;
    _backfillInProgress = true;
    _shouldCancelBackfill = false;

    // Enable wakelock to prevent screen from turning off during enrichment
    try {
      await WakelockPlus.enable();
      debugPrint('RssProvider: 🔒 WakeLock enabled - screen will stay on during enrichment');
    } catch (e) {
      debugPrint('RssProvider: ⚠️ Failed to enable WakeLock: $e');
    }

    try {
      debugPrint('RssProvider: Starting background article enrichment for ${_items.length} items (one-by-one updates)');

      int enrichedCount = 0;
      int processedCount = 0;

      // FIRST: Filter to only items that need enrichment
      final itemsNeedingEnrichment = _items.where((item) {
        // Skip if no link
        if (item.link.isEmpty) return false;

        // Skip if mainText already captured
        final existingText = (item.mainText ?? '').trim();
        if (existingText.isNotEmpty) return false;

        // Skip if already failed 5 times
        if (item.enrichmentAttempts >= 5) return false;

        return true;
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

        // Enrich this article
        try {
          debugPrint('RssProvider: [$processedCount/${sortedItems.length}] 📖 NOW ENRICHING: "${item.title}" (Date: ${item.pubDate})');
          final content = await repo.populateArticleContent([item]);

          // Check cancellation after network call
          if (_shouldCancelBackfill) {
            debugPrint('RssProvider: Enrichment cancelled during network call');
            break;
          }

          if (content.isNotEmpty && content.containsKey(item.id)) {
            final extractedMainText = content[item.id]!.mainText;
            final extractedImageUrl = content[item.id]!.imageUrl;

            // Check if extraction succeeded
            if (extractedMainText != null && extractedMainText.trim().isNotEmpty) {
              // Success - update with content
              final idx = _items.indexWhere((e) => e.id == item.id);
              if (idx != -1) {
                _items[idx] = _items[idx].copyWith(
                  mainText: extractedMainText,
                  imageUrl: extractedImageUrl ?? _items[idx].imageUrl,
                );
                enrichedCount++;

                // Update UI immediately after each article is enriched
                debugPrint('RssProvider: ✓ Article $enrichedCount enriched - updating UI now!');
                notifyListeners();

                // Small delay to make the progressive update visible
                await Future.delayed(const Duration(milliseconds: 100));
              }
            } else {
              // Failed to extract content - increment attempts
              debugPrint('RssProvider: ⚠ Article $processedCount failed to extract content');
              await repo.incrementEnrichmentAttempts(item.id);

              // Update local item with incremented attempts
              final idx = _items.indexWhere((e) => e.id == item.id);
              if (idx != -1) {
                _items[idx] = _items[idx].copyWith(
                  enrichmentAttempts: _items[idx].enrichmentAttempts + 1,
                );
                notifyListeners();
              }
            }
          } else {
            // Failed - increment attempts
            debugPrint('RssProvider: ⚠ Article $processedCount failed to enrich');
            await repo.incrementEnrichmentAttempts(item.id);

            // Update local item with incremented attempts
            final idx = _items.indexWhere((e) => e.id == item.id);
            if (idx != -1) {
              _items[idx] = _items[idx].copyWith(
                enrichmentAttempts: _items[idx].enrichmentAttempts + 1,
              );
              notifyListeners();
            }
          }
        } catch (e) {
          debugPrint('RssProvider: ✗ Error enriching article $processedCount: $e');
          // Increment attempts on error too
          await repo.incrementEnrichmentAttempts(item.id);

          // Update local item with incremented attempts
          final idx = _items.indexWhere((e) => e.id == item.id);
          if (idx != -1) {
            _items[idx] = _items[idx].copyWith(
              enrichmentAttempts: _items[idx].enrichmentAttempts + 1,
            );
            notifyListeners();
          }
        }
      }

      debugPrint('RssProvider: ✓ All done! Enriched $enrichedCount of $processedCount articles');

      // Check if there are still articles needing enrichment
      final stillNeedEnrichment = _items.where((item) {
        if (item.link.isEmpty) return false;
        final existingText = (item.mainText ?? '').trim();
        if (existingText.isNotEmpty) return false;
        if (item.enrichmentAttempts >= 5) return false;
        return true;
      }).length;

      if (stillNeedEnrichment > 0 && _retryCount < _maxRetries) {
        _retryCount++;
        debugPrint('RssProvider: 🔄 $stillNeedEnrichment articles still need enrichment. Retry attempt $_retryCount/$_maxRetries');
        // Schedule retry after a short delay
        await Future.delayed(const Duration(seconds: 2));
        if (!_shouldCancelBackfill) {
          debugPrint('RssProvider: 🔄 Starting retry enrichment...');
          _backfillInProgress = false; // Reset flag to allow retry
          _scheduleBackgroundBackfill();
          return; // Don't disable WakeLock yet, continuing enrichment
        }
      } else if (stillNeedEnrichment > 0) {
        debugPrint('RssProvider: ⚠️ $stillNeedEnrichment articles still need enrichment but max retries reached');
      } else {
        debugPrint('RssProvider: ✅ All articles enriched successfully!');
      }

      // Reset retry count for next enrichment session
      _retryCount = 0;

    } finally {
      _backfillInProgress = false;

      // Disable wakelock when enrichment is done
      try {
        await WakelockPlus.disable();
        debugPrint('RssProvider: 🔓 WakeLock disabled - screen can turn off now');
      } catch (e) {
        debugPrint('RssProvider: ⚠️ Failed to disable WakeLock: $e');
      }

      // If restart was requested while we were running, start a new enrichment
      if (_needsRestart) {
        _needsRestart = false;
        _retryCount = 0; // Reset retry count for new session
        debugPrint('RssProvider: Restarting enrichment with updated items');
        _scheduleBackgroundBackfill();
      }
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

  /// Hide a single article (move to trash, isRead = 2)
  Future<void> hideArticle(FeedItem item) async {
    await repo.updateReadStatus(item.id, 2);
    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx >= 0) {
      _items[idx] = item.copyWith(isRead: 2);
      notifyListeners();
    }
  }

  /// Get all hidden/trashed articles
  Future<List<FeedItem>> getHiddenArticles() async {
    return repo.getHiddenArticles();
  }

  /// Restore an article from trash
  Future<void> restoreFromTrash(FeedItem item) async {
    await repo.restoreFromTrash(item.id);
    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx >= 0) {
      _items[idx] = item.copyWith(isRead: 1);
    } else {
      // Article might not be in memory, reload from DB
      final restored = await repo.findById(item.id);
      if (restored != null) {
        _items.add(restored);
      }
    }
    notifyListeners();
  }

  /// Restore multiple articles from trash
  Future<void> restoreMultipleFromTrash(List<FeedItem> items) async {
    final ids = items.map((e) => e.id).toList();
    await repo.restoreMultipleFromTrash(ids);
    // Reload from DB to get updated items
    final merged = await repo.readAllFromDb();
    _items..clear()..addAll(merged);
    notifyListeners();
  }

  /// Permanently delete an article
  Future<void> permanentlyDeleteArticle(FeedItem item) async {
    await repo.permanentlyDeleteById(item.id);
    _items.removeWhere((e) => e.id == item.id);
    notifyListeners();
  }

  /// Permanently delete multiple articles
  Future<void> permanentlyDeleteMultiple(List<FeedItem> items) async {
    final ids = items.map((e) => e.id).toList();
    await repo.permanentlyDeleteByIds(ids);
    _items.removeWhere((e) => ids.contains(e.id));
    notifyListeners();
  }

  /// Permanently delete all hidden articles
  Future<void> permanentlyDeleteAllHidden() async {
    await repo.permanentlyDeleteAllHidden();
    _items.removeWhere((e) => e.isRead == 2);
    notifyListeners();
  }

  @override
  void dispose() {
    // Cancel ongoing enrichment and release WakeLock when provider is disposed
    _shouldCancelBackfill = true;

    // Ensure WakeLock is released
    WakelockPlus.disable().catchError((e) {
      debugPrint('RssProvider: Failed to disable WakeLock on dispose: $e');
    });

    super.dispose();
  }
}
