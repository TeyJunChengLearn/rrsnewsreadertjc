import 'package:flutter/foundation.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/feed_item.dart';
import '../models/feed_source.dart';
import '../data/feed_repository.dart';

enum SortOrder { latestFirst, oldestFirst }
enum BookmarkFilter { all, bookmarkedOnly }
enum ReadFilter { all, readOnly, unreadOnly }

class RssProvider extends ChangeNotifier {
  final FeedRepository repo;

  RssProvider({required this.repo}) {
    timeago.setLocaleMessages('en_short', timeago.EnShortMessages());
  }

  // Feeds list (BBC, Yahoo...)
  final List<FeedSource> _sources = [...defaultSources];
  List<FeedSource> get sources => List.unmodifiable(_sources);

  // Articles
  final List<FeedItem> _items = [];
  List<FeedItem> get items => List.unmodifiable(_items);

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  SortOrder _sortOrder = SortOrder.latestFirst;
  BookmarkFilter _bookmarkFilter = BookmarkFilter.all;
  ReadFilter _readFilter = ReadFilter.all;
  String _searchQuery = '';

  SortOrder get sortOrder => _sortOrder;
  BookmarkFilter get bookmarkFilter => _bookmarkFilter;
  ReadFilter get readFilter => _readFilter;
  String get searchQuery => _searchQuery;

  int get unreadCount => _items.where((i) => !i.isRead).length;

  List<FeedItem> get visibleItems {
    Iterable<FeedItem> result = _items;

    // search
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((i) {
        final inTitle = i.title.toLowerCase().contains(q);
        final inDesc = (i.description ?? '').toLowerCase().contains(q);
        return inTitle || inDesc;
      });
    }

    // bookmark filter
    if (_bookmarkFilter == BookmarkFilter.bookmarkedOnly) {
      result = result.where((i) => i.isBookmarked);
    }

    // read/unread filter
    if (_readFilter == ReadFilter.readOnly) {
      result = result.where((i) => i.isRead);
    } else if (_readFilter == ReadFilter.unreadOnly) {
      result = result.where((i) => !i.isRead);
    }

    // sort
    final list = result.toList();
    list.sort((a, b) {
      final ad = a.pubDate?.millisecondsSinceEpoch ?? 0;
      final bd = b.pubDate?.millisecondsSinceEpoch ?? 0;
      if (_sortOrder == SortOrder.latestFirst) {
        return bd.compareTo(ad);
      } else {
        return ad.compareTo(bd);
      }
    });

    return list;
  }

  bool get isLatestFirst => _sortOrder == SortOrder.latestFirst;
  bool get isOldestFirst => _sortOrder == SortOrder.oldestFirst;

  bool get showAllArticles =>
      _bookmarkFilter == BookmarkFilter.all &&
      _readFilter == ReadFilter.all;

  bool get showBookmarkedOnly =>
      _bookmarkFilter == BookmarkFilter.bookmarkedOnly;

  bool get showReadOnly => _readFilter == ReadFilter.readOnly;
  bool get showUnreadOnly => _readFilter == ReadFilter.unreadOnly;

  Future<void> loadInitial() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final merged = await repo.loadAll(_sources);
      _items
        ..clear()
        ..addAll(merged);
    } catch (e) {
      _error = e.toString();
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> refresh() => loadInitial();

  void addSource(FeedSource source) {
    _sources.add(source);
    notifyListeners();
    loadInitial();
  }

  void deleteSource(FeedSource source) {
    _sources.removeWhere((s) => s.url == source.url);
    notifyListeners();
    loadInitial();
  }

  void markRead(FeedItem item) {
    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx == -1) return;

    _items[idx] = _items[idx].copyWith(isRead: true);
    repo.setRead(item.id, true);

    notifyListeners();
  }

  void toggleBookmark(FeedItem item) {
    final idx = _items.indexWhere((e) => e.id == item.id);
    if (idx == -1) return;

    final nowBookmarked = !_items[idx].isBookmarked;
    _items[idx] =
        _items[idx].copyWith(isBookmarked: nowBookmarked);

    repo.setBookmark(item.id, nowBookmarked);
    notifyListeners();
  }

  String niceTimeAgo(DateTime? when) {
    if (when == null) return '';
    return timeago.format(when, locale: 'en');
  }

  void setSortOrder(SortOrder order) {
    _sortOrder = order;
    notifyListeners();
  }

  void setBookmarkFilter(BookmarkFilter f) {
    _bookmarkFilter = f;
    notifyListeners();
  }

  void setReadFilter(ReadFilter f) {
    _readFilter = f;
    notifyListeners();
  }

  void setSearchQuery(String q) {
    _searchQuery = q;
    notifyListeners();
  }
}
