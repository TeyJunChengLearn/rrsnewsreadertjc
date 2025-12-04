import 'dart:async';
import 'package:http/http.dart' as http;
import 'feed_fetcher.dart';

class HttpFeedFetcher implements FeedFetcher {
  static const _userAgent = 'FlutterRSSReader/1.0 (+https://example.com)';


HttpFeedFetcher({
    this.cookieHeaderBuilder,
    this.customHeaders,
  });

  /// Build a Cookie header for the target URL (e.g., session cookies).
  final Future<String?> Function(String url)? cookieHeaderBuilder;

  /// Additional headers to attach to every request.
  final Map<String, String>? customHeaders;
  @override
  Future<String> fetch(String url) async {
    final uri = Uri.parse(url);
       final headers = {
      'User-Agent': _userAgent,
      ...?customHeaders,
    };

    final cookies =
        cookieHeaderBuilder != null ? await cookieHeaderBuilder!(url) : null;
    if (cookies != null && cookies.isNotEmpty) {
      headers['Cookie'] = cookies;
    }
    Exception? lastError;

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final resp = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 10));

        if (resp.statusCode == 200) {
          return resp.body;
        }

        throw Exception(
          'HTTP ${resp.statusCode} (${resp.reasonPhrase ?? 'Unknown'})',
        );
      } on TimeoutException {
        lastError = Exception(
          'Timed out fetching feed after 10s (attempt ${attempt + 1})',
        );
      } on Exception catch (e) {
        lastError = Exception(
          'Network request failed on attempt ${attempt + 1}: $e',
        );
      }

      if (attempt == 0) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }

   throw Exception('Failed to fetch feed ($url): ${lastError?.toString()}');
  }
}
