import '../models/feed_item.dart';
import '../models/feed_source.dart';

import '../data/feed_fetcher.dart';
import '../data/feed_parser.dart';

class RssService {
  final FeedFetcher fetcher;
  final FeedParser parser;

  RssService({
    required this.fetcher,
    required this.parser,
  });

  Future<List<FeedItem>> fetchFeedItems(FeedSource source) async {
    // download raw XML text
    final rawText = await fetcher.fetch(source.url);

    // parse to FeedItem objects
    final items = parser.parse(rawText, source.title);

    // items MUST have id set (rss_atom_parser does that)
    return items;
  }
}
