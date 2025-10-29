class FeedSource {
  final String title; // e.g. "BBC News"
  final String url;   // RSS/Atom URL

  const FeedSource({
    required this.title,
    required this.url,
  });
}

// Default feeds for first launch.
// You can edit these.
const List<FeedSource> defaultSources = [
  FeedSource(
    title: 'BBC News',
    url: 'https://feeds.bbci.co.uk/news/world/rss.xml',
  ),
  FeedSource(
    title: 'Yahoo News',
    url: 'https://www.yahoo.com/news/rss',
  ),
];
