import 'package:http/http.dart' as http;
import 'feed_fetcher.dart';

class HttpFeedFetcher implements FeedFetcher {
  @override
  Future<String> fetch(String url) async {
    final uri = Uri.parse(url);
    final resp = await http.get(uri, headers: {
      'User-Agent': 'FlutterRSSReader/1.0 (+https://example.com)'
    });

    if (resp.statusCode != 200) {
      throw Exception(
        'Failed to fetch feed ($url): HTTP ${resp.statusCode}',
      );
    }

    return resp.body;
  }
}
