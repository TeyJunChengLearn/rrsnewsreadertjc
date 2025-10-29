import 'package:flutter/material.dart';
import '../models/feed_item.dart';

class ArticleDetailPage extends StatelessWidget {
  final FeedItem item;
  const ArticleDetailPage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          item.sourceTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            item.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          if (item.pubDate != null)
            Text(
              item.pubDate.toString(),
              style: const TextStyle(color: Colors.grey),
            ),
          const SizedBox(height: 16),
          if (item.description != null)
            Text(
              item.description!,
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
          const SizedBox(height: 16),
          Text(
            'Link:\n${item.link}',
            style: const TextStyle(
              fontStyle: FontStyle.italic,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
