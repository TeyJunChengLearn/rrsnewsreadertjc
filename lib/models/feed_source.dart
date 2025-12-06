// lib/models/feed_source.dart

class FeedSource {
  /// null when not yet saved in DB
  final int? id;
  final String title; // e.g. "BBC News"
  final String url;   // RSS/Atom URL

  /// Delay in milliseconds before extracting content from WebView
  /// Used for paywalled sites that need time to render JavaScript
  final int delayTime;

  /// Whether this feed requires login/authentication
  /// If true, will use WebView-based extraction with cookies
  final bool requiresLogin;

  const FeedSource({
    this.id,
    required this.title,
    required this.url,
    this.delayTime = 2000, // Default 2 seconds
    this.requiresLogin = false,
  });

  FeedSource copyWith({
    int? id,
    String? title,
    String? url,
    int? delayTime,
    bool? requiresLogin,
  }) {
    return FeedSource(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      delayTime: delayTime ?? this.delayTime,
      requiresLogin: requiresLogin ?? this.requiresLogin,
    );
  }

  factory FeedSource.fromMap(Map<String, dynamic> map) {
    return FeedSource(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      url: map['url'] as String? ?? '',
      delayTime: map['delayTime'] as int? ?? 2000,
      requiresLogin: (map['requiresLogin'] as int? ?? 0) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'url': url,
      'delayTime': delayTime,
      'requiresLogin': requiresLogin ? 1 : 0,
    };
  }
}
