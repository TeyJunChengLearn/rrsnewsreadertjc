abstract class FeedFetcher {
  /// Download the raw RSS/Atom feed body (XML) as text.
  Future<String> fetch(String url);
}
