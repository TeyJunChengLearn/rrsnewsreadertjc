// lib/providers/rss_provider.dart

import 'package:flutter/foundation.dart';

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
    Iterable<FeedItem> data = _items;

    // 1) bookmark filter
    if (_bookmarkFilter == BookmarkFilter.bookmarkedOnly) {
      data = data.where((e) => e.isBookmarked);
    }

    // 2) read filter
    switch (_readFilter) {
      case ReadFilter.all:
        break;
      case ReadFilter.unreadOnly:
        data = data.where((e) => !(e.isRead==1));
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
  Future<void> loadInitial() async {
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
              await backfillArticleContent();
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
         await backfillArticleContent();
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
    if (source.id != null) {
      await repo.deleteSource(source.id!);
    }
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
  Future<void> backfillArticleContent() async {
    if (_backfillInProgress) return;
    _backfillInProgress = true;
    try {
      final updates = await repo.populateArticleContent(_items);
      if (updates.isEmpty) return;

      for (var i = 0; i < _items.length; i++) {
        final content = updates[_items[i].id];
        if (content != null) {
          _items[i] = _items[i].copyWith(
            mainText: content.mainText ?? _items[i].mainText,
            imageUrl: content.imageUrl ?? _items[i].imageUrl,
          );
        }
      }
      notifyListeners();
    } finally {
      _backfillInProgress = false;
    }
  }
  // ---------------------------------------------------------------------------
  // FILTERS / SORTING (the ones news_page.dart calls)
  // ---------------------------------------------------------------------------
  void setSortOrder(SortOrder order) {
    _sortOrder = order;
    notifyListeners();
  }

  void setBookmarkFilter(BookmarkFilter filter) {
    _bookmarkFilter = filter;
    notifyListeners();
  }

  void setReadFilter(ReadFilter filter) {
    _readFilter = filter;
    notifyListeners();
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
