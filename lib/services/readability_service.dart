import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

/// Minimal wrapper that mimics Readability4JExtended style extraction.
/// Fetches the HTML for a URL and returns the normalized main article text.
class ArticleReadabilityResult {
  final String? mainText;
  final String? imageUrl;

  const ArticleReadabilityResult({this.mainText, this.imageUrl});

  bool get hasContent => (mainText?.isNotEmpty ?? false) || (imageUrl?.isNotEmpty ?? false);
}
class Readability4JExtended {
  final http.Client _client;

  Readability4JExtended({http.Client? client}) : _client = client ?? http.Client();

  Future<ArticleReadabilityResult?> extractMainContent(String url) async {
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
      final leadImage = _extractLeadImage(doc, articleRoot, url);

      final mainText = normalized.isEmpty ? null : normalized;
      final result = ArticleReadabilityResult(
        mainText: mainText,
        imageUrl: leadImage,
      );

      return result.hasContent ? result : null;
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
String? _extractLeadImage(
    dom.Document doc,
    dom.Element articleRoot,
    String baseUrl,
  ) {
    String? resolve(String? src) {
      if (src == null || src.trim().isEmpty) return null;

      final srcUri = Uri.tryParse(src.trim());
      if (srcUri == null) return null;
      if (srcUri.hasScheme) return srcUri.toString();

      final base = Uri.tryParse(baseUrl);
      if (base == null) return null;

      return base.resolveUri(srcUri).toString();
    }

    bool _looksLikeJunk(String url) {
      final lower = url.toLowerCase();
      if (lower.startsWith('data:')) return true;
      if (lower.endsWith('.svg') || lower.endsWith('.gif')) return true;

      const junkHints = [
        'logo',
        'icon',
        'avatar',
        'sprite',
        'pixel',
        'spacer',
        'placeholder',
        'badge',
        'ads',
        'ad-',
        'banner',
        'tracking',
      ];

      return junkHints.any((hint) => lower.contains(hint));
    }

    bool _hasAcceptableSize(dom.Element img) {
      int? parseDim(String? raw) => int.tryParse(raw ?? '');

      final width = parseDim(img.attributes['width']);
      final height = parseDim(img.attributes['height']);

      const minSize = 200;
      if (width == null && height == null) return true;
      if (width != null && width < minSize) return false;
      if (height != null && height < minSize) return false;
      return true;
    }

    String? pickCandidate(Iterable<dom.Element> candidates) {
      for (final element in candidates) {
        final resolved = resolve(element.attributes['src']);
        if (resolved == null) continue;
        if (_looksLikeJunk(resolved)) continue;
        if (!_hasAcceptableSize(element)) continue;
        return resolved;
      }
      return null;
    }

    // Prefer OpenGraph image if present and not obviously decorative/tracking.
    final ogImage = doc.querySelector('meta[property="og:image"]')?.attributes['content'];
    final resolvedOg = resolve(ogImage);
    if (resolvedOg != null && !_looksLikeJunk(resolvedOg)) return resolvedOg;

    // Try figure/lead images next.
    final figureCandidates = articleRoot.querySelectorAll('figure img');
    final resolvedFigure = pickCandidate(figureCandidates);
    if (resolvedFigure != null) return resolvedFigure;

    // Fall back to the first reasonable inline image; otherwise, return null.
    final inlineCandidates = articleRoot.querySelectorAll('img');
    return pickCandidate(inlineCandidates);
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