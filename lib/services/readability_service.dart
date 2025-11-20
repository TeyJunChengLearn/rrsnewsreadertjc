import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

/// Minimal wrapper that mimics Readability4JExtended style extraction.
/// Fetches the HTML for a URL and returns the normalized main article text.
class Readability4JExtended {
  final http.Client _client;

  Readability4JExtended({http.Client? client}) : _client = client ?? http.Client();

  Future<String?> extractMainText(String url) async {
    try {
      final resp = await _client.get(Uri.parse(url), headers: {
        'User-Agent': 'Readability4JExtended/1.0 (+https://example.com)',
        'Accept': 'text/html,application/xhtml+xml',
      });

      if (resp.statusCode != 200) return null;

      final doc = html_parser.parse(resp.body);
      _stripNoise(doc);
      final dom.Element? articleRoot = doc.querySelector('article') ??
          doc.querySelector('main') ??
          doc.querySelector('[role="main"]') ??
          doc.querySelector('#content') ??
          doc.body;

      if (articleRoot == null) return null;

      final normalized = _normalizeWhitespace(articleRoot.text);
      return normalized.isEmpty ? null : normalized;
    } catch (_) {
      return null;
    }
  }

  void _stripNoise(dom.Document doc) {
    final garbage = doc.querySelectorAll('script,style,noscript,header,footer,nav');
    for (final node in garbage) {
      node.remove();
    }
  }

  String _normalizeWhitespace(String raw) {
    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.join('\n\n');
  }
}