import 'package:flutter_rss_reader/models/feed_source.dart';

class BackupData {
  final String version;
  final String timestamp;
  final String appVersion;
  final BackupContent data;

  BackupData({
    required this.version,
    required this.timestamp,
    required this.appVersion,
    required this.data,
  });

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'timestamp': timestamp,
      'appVersion': appVersion,
      'data': data.toJson(),
    };
  }

  factory BackupData.fromJson(Map<String, dynamic> json) {
    return BackupData(
      version: json['version'] as String,
      timestamp: json['timestamp'] as String,
      appVersion: json['appVersion'] as String,
      data: BackupContent.fromJson(json['data'] as Map<String, dynamic>),
    );
  }
}

class BackupContent {
  final List<FeedSource> feedSources;
  final List<ArticleMetadata> articles;
  final Map<String, dynamic> settings;
  final Map<String, Map<String, String>> cookies;

  BackupContent({
    required this.feedSources,
    required this.articles,
    required this.settings,
    required this.cookies,
  });

  Map<String, dynamic> toJson() {
    return {
      'feedSources': feedSources.map((fs) => fs.toMap()).toList(),
      'articles': articles.map((a) => a.toJson()).toList(),
      'settings': settings,
      'cookies': cookies,
    };
  }

  factory BackupContent.fromJson(Map<String, dynamic> json) {
    return BackupContent(
      feedSources: (json['feedSources'] as List)
          .map((item) => FeedSource.fromMap(item as Map<String, dynamic>))
          .toList(),
      articles: (json['articles'] as List)
          .map((item) => ArticleMetadata.fromJson(item as Map<String, dynamic>))
          .toList(),
      settings: json['settings'] as Map<String, dynamic>,
      cookies: (json['cookies'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(
          key,
          (value as Map<String, dynamic>).map(
            (k, v) => MapEntry(k, v.toString()),
          ),
        ),
      ),
    );
  }
}

class ArticleMetadata {
  final String id;
  final String sourceTitle;
  final String title;
  final String link;
  final String? imageUrl;
  final int? pubDateMillis;
  final int isRead;
  final bool isBookmarked;
  final int? readingPosition;

  ArticleMetadata({
    required this.id,
    required this.sourceTitle,
    required this.title,
    required this.link,
    this.imageUrl,
    this.pubDateMillis,
    required this.isRead,
    required this.isBookmarked,
    this.readingPosition,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceTitle': sourceTitle,
      'title': title,
      'link': link,
      'imageUrl': imageUrl,
      'pubDateMillis': pubDateMillis,
      'isRead': isRead,
      'isBookmarked': isBookmarked ? 1 : 0,
      'readingPosition': readingPosition,
    };
  }

  factory ArticleMetadata.fromJson(Map<String, dynamic> json) {
    return ArticleMetadata(
      id: json['id'] as String,
      sourceTitle: json['sourceTitle'] as String,
      title: json['title'] as String,
      link: json['link'] as String,
      imageUrl: json['imageUrl'] as String?,
      pubDateMillis: json['pubDateMillis'] as int?,
      isRead: json['isRead'] as int,
      isBookmarked: (json['isBookmarked'] as int?) == 1,
      readingPosition: json['readingPosition'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sourceTitle': sourceTitle,
      'title': title,
      'link': link,
      'imageUrl': imageUrl,
      'pubDateMillis': pubDateMillis,
      'isRead': isRead,
      'isBookmarked': isBookmarked ? 1 : 0,
      'readingPosition': readingPosition,
    };
  }
}

class BackupFile {
  final String id;
  final String name;
  final String? modifiedTime;
  final int? size;

  BackupFile({
    required this.id,
    required this.name,
    this.modifiedTime,
    this.size,
  });
}
