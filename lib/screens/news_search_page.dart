import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/rss_provider.dart';
import '../models/feed_item.dart';
import 'article_webview_page.dart';

class NewsSearchPage extends StatefulWidget {
  const NewsSearchPage({super.key});

  @override
  State<NewsSearchPage> createState() => _NewsSearchPageState();
}

class _NewsSearchPageState extends State<NewsSearchPage> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    final rss = context.read<RssProvider>();
    _controller.text = rss.searchQuery;
  }

  @override
  Widget build(BuildContext context) {
    final rss = context.watch<RssProvider>();
    final results = rss.searchResults;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search news...',
            border: InputBorder.none,
          ),
          onChanged: (val) {
            context.read<RssProvider>().setSearchQuery(val);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _controller.clear();
              context.read<RssProvider>().setSearchQuery('');
            },
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: results.length,
        itemBuilder: (context, index) {
          final item = results[index];
          return _SearchRow(item: item);
        },
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  final FeedItem item;
  const _SearchRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final rss = context.read<RssProvider>();
    return ListTile(
      title: Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: item.isRead==1 ? FontWeight.w400 : FontWeight.w600,
          color: item.isRead==1 ? Colors.grey.shade600 : null,
        ),
      ),
      subtitle: Text(
        item.sourceTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        // optional: mark read
        rss.markRead(item);
        if (item.link.isEmpty) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ArticleWebviewPage(
              articleId: item.id,
              url: item.link,
              title: item.title,
              initialMainText: item.mainText,
              initialImageUrl: item.imageUrl,
            ),
          ),
        );
      },

    );
  }
}
