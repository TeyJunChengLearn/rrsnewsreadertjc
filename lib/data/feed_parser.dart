import '../models/feed_item.dart';

abstract class FeedParser {
  /// Convert a feed's XML text into a list of FeedItem.
  /// [sourceTitle] = name of the feed ("BBC News").
  List<FeedItem> parse(String rawXml, String sourceTitle);
}
