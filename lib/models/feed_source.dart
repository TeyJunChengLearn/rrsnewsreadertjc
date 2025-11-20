// lib/models/feed_source.dart

class FeedSource {
  /// null when not yet saved in DB
  final int? id;
  final String title; // e.g. "BBC News"
  final String url;   // RSS/Atom URL

  const FeedSource({
    this.id,
    required this.title,
    required this.url,
  });

  FeedSource copyWith({
    int? id,
    String? title,
    String? url,
  }) {
    return FeedSource(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
    );
  }

  factory FeedSource.fromMap(Map<String, dynamic> map) {
    return FeedSource(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      url: map['url'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'url': url,
    };
  }
}
