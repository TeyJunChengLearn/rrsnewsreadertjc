// lib/data/rss_atom_parser.dart
import 'package:webfeed_plus/webfeed_plus.dart';

import '../models/feed_item.dart';
import 'feed_parser.dart';

class RssAtomParser implements FeedParser {
  @override
  List<FeedItem> parse(String rawXml, String sourceTitle) {
    // Try RSS first
    try {
      final rss = RssFeed.parse(rawXml);
      return _fromRssFeed(rss, sourceTitle);
    } catch (_) {
      // not RSS, try Atom
    }

    try {
      final atom = AtomFeed.parse(rawXml);
      return _fromAtomFeed(atom, sourceTitle);
    } catch (_) {
      // not Atom either
    }

    // If neither worked, return empty list instead of crashing.
    return [];
  }

  // -----------------------
  // RSS -> FeedItem
  // -----------------------
  List<FeedItem> _fromRssFeed(RssFeed feed, String sourceTitle) {
    final out = <FeedItem>[];
    for (final i in feed.items ?? const <RssItem>[]) {
      final stableId = i.guid ?? i.link ?? i.title ?? '';

      out.add(
        FeedItem(
          id: stableId,
          sourceTitle: sourceTitle,
          title: i.title ?? '(no title)',
          link: i.link ?? '',
          description: i.description ?? i.content?.value,
          pubDate: i.pubDate,
          imageUrl: _extractRssImage(i),
        ),
      );
    }
    return out;
  }

  String? _extractRssImage(RssItem i) {
    // 1. enclosure with url (common for podcasts/news)
    if (i.enclosure?.url != null && i.enclosure!.url!.isNotEmpty) {
      return i.enclosure!.url;
    }

    // 2. media:content url
    if (i.media?.thumbnails != null && i.media!.thumbnails!.isNotEmpty) {
      // some feeds have <media:thumbnail url="..."/>
      final thumb = i.media!.thumbnails!.first;
      if (thumb.url != null && thumb.url!.isNotEmpty) {
        return thumb.url!;
      }
    }

    // 3. fallback: look for <img src="..."> in description or content
    final html = i.description ?? i.content?.value ?? '';
    return _extractImgFromHtml(html);
    // if still null, return null -> UI will show placeholder
  }

  // -----------------------
  // Atom -> FeedItem
  // -----------------------
  List<FeedItem> _fromAtomFeed(AtomFeed feed, String sourceTitle) {
    final out = <FeedItem>[];
    for (final i in feed.items ?? const <AtomItem>[]) {
      final linkUrl = _chooseAtomLink(i);
      final publishedDt = _chooseAtomDate(i);

      final stableId = i.id ?? linkUrl ?? i.title ?? '';

      out.add(
        FeedItem(
          id: stableId,
          sourceTitle: sourceTitle,
          title: i.title ?? '(no title)',
          link: linkUrl ?? '',
          description: i.summary ?? i.content,
          pubDate: publishedDt,
          imageUrl: _extractAtomImage(i),
        ),
      );
    }
    return out;
  }

  String? _chooseAtomLink(AtomItem i) {
    // Usually links is a list of AtomLink with .href
    if (i.links != null && i.links!.isNotEmpty) {
      final first = i.links!.first;
      if (first.href != null && first.href!.isNotEmpty) {
        return first.href;
      }
    }
    // Fallbacks
    if (i.id != null && i.id!.startsWith('http')) {
      return i.id;
    }
    return null;
  }

  DateTime? _chooseAtomDate(AtomItem i) {
    // updated is normally DateTime? in webfeed_plus
    if (i.updated is DateTime) return i.updated as DateTime;
    if (i.published is DateTime) return i.published as DateTime;
    return null;
  }

  String? _extractAtomImage(AtomItem i) {
    // Atom sometimes has media:thumbnail or <img> in summary/content
    // 1. media via i.media if available
    if (i.media != null) {
      // webfeed_plus `media` model is flexible, so we try common patterns

      // media.thumbnails?.first.url
      final thumbs = i.media!.thumbnails;
      if (thumbs != null && thumbs.isNotEmpty) {
        final t = thumbs.first;
        if (t.url != null && t.url!.isNotEmpty) {
          return t.url!;
        }
      }
    }

    // 2. extract <img ...> from summary/content
    final html = i.summary ?? i.content ?? '';
    return _extractImgFromHtml(html);
  }

  String? _extractImgFromHtml(String html) {
  final regex = RegExp(
    "<img[^>]+src=[\"']([^\"']+)[\"']",
    caseSensitive: false,
  );

  final match = regex.firstMatch(html);
  if (match != null && match.groupCount >= 1) {
    return match.group(1);
  }
  return null;
}


}
