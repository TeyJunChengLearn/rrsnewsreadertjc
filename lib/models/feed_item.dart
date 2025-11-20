class FeedItem {
  final String id;           // unique stable id for this article
  final String sourceTitle;  // e.g. "BBC News"
  final String title;
  final String link;
  final String? description;
  final String? imageUrl;
  final DateTime? pubDate;
  final String? mainText;

  final int isRead;
  final bool isBookmarked;

  FeedItem({
    required this.id,
    required this.sourceTitle,
    required this.title,
    required this.link,
    this.description,
    this.imageUrl,
    this.pubDate,
    this.mainText,
    this.isRead = 0,
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
    String? mainText,
    int? isRead,
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
      mainText: mainText ?? this.mainText,
      isRead: isRead ?? this.isRead,
      isBookmarked: isBookmarked ?? this.isBookmarked,
    );
  }

  Map<String, dynamic> toMap() {
     final int normalizedRead;
    if (isRead == 0 || isRead == 1 || isRead == 2) {
      normalizedRead = isRead;
    } else {
      normalizedRead = isRead == 1 ? 1 : 0;
    }

    return {
      'id': id,
      'sourceTitle': sourceTitle,
      'title': title,
      'link': link,
      'description': description,
      'imageUrl': imageUrl,
      'pubDateMillis': pubDate?.millisecondsSinceEpoch,
      'mainText': mainText,
      'isRead': normalizedRead,
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
      mainText: map['mainText'] as String?,
      isRead: (map['isRead'] as int?) ?? 0,
      isBookmarked: (map['isBookmarked'] ?? 0) == 1,
    );
  }
}
