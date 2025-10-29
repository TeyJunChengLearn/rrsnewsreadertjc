class FeedItem {
  final String id;           // unique stable id for this article
  final String sourceTitle;  // e.g. "BBC News"
  final String title;
  final String link;
  final String? description;
  final String? imageUrl;
  final DateTime? pubDate;

  final bool isRead;
  final bool isBookmarked;

  FeedItem({
    required this.id,
    required this.sourceTitle,
    required this.title,
    required this.link,
    this.description,
    this.imageUrl,
    this.pubDate,
    this.isRead = false,
    this.isBookmarked = false,
  });

  FeedItem copyWith({
    String? id,
    String? sourceTitle,
    String? title,
    String? link,
    String? description,
    String? imageUrl,
    DateTime? pubDate,
    bool? isRead,
    bool? isBookmarked,
  }) {
    return FeedItem(
      id: id ?? this.id,
      sourceTitle: sourceTitle ?? this.sourceTitle,
      title: title ?? this.title,
      link: link ?? this.link,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      pubDate: pubDate ?? this.pubDate,
      isRead: isRead ?? this.isRead,
      isBookmarked: isBookmarked ?? this.isBookmarked,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sourceTitle': sourceTitle,
      'title': title,
      'link': link,
      'description': description,
      'imageUrl': imageUrl,
      'pubDateMillis': pubDate?.millisecondsSinceEpoch,
      'isRead': isRead ? 1 : 0,
      'isBookmarked': isBookmarked ? 1 : 0,
    };
  }

  static FeedItem fromMap(Map<String, dynamic> map) {
    return FeedItem(
      id: map['id'] as String,
      sourceTitle: map['sourceTitle'] as String? ?? '',
      title: map['title'] as String? ?? '',
      link: map['link'] as String? ?? '',
      description: map['description'] as String?,
      imageUrl: map['imageUrl'] as String?,
      pubDate: map['pubDateMillis'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              map['pubDateMillis'] as int,
            ),
      isRead: (map['isRead'] ?? 0) == 1,
      isBookmarked: (map['isBookmarked'] ?? 0) == 1,
    );
  }
}
