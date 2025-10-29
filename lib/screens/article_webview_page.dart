import 'package:flutter/material.dart';
import '../models/feed_item.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ArticleWebViewPage extends StatefulWidget {
  final FeedItem item;
  const ArticleWebViewPage({super.key, required this.item});

  @override
  State<ArticleWebViewPage> createState() => _ArticleWebViewPageState();
}

class _ArticleWebViewPageState extends State<ArticleWebViewPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(
        Uri.parse(widget.item.link),
      );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.text_fields),
            onPressed: () {
              // text size options (not implemented)
            },
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // search in page (not implemented)
            },
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // share intent (not implemented)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Share not implemented')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Article header info (source, title, pub date)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.sourceTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                    )),
                const SizedBox(height: 8),
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
                    style: const TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          // expanded web content
          Expanded(
            child: WebViewWidget(
              controller: _controller,
            ),
          ),

          // Bottom mini player-style bar with buttons (like screenshot)
          Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: const [
                Icon(Icons.skip_previous),
                Icon(Icons.fast_rewind),
                Icon(Icons.play_arrow),
                Icon(Icons.fast_forward),
                Icon(Icons.skip_next),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
