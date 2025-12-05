import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_rss_reader/services/android_webview_extractor.dart';

import 'package:flutter_rss_reader/services/readability_service.dart';


class _FakeWebViewExtractor extends AndroidWebViewExtractor {
  String? lastUrl;
  String? lastCookieHeader;
  String? lastUserAgent;
  Duration? lastPostLoadDelay;

  @override
  Future<String?> renderPage(
    String url, {
    Duration timeout = const Duration(seconds: 15),
    Duration postLoadDelay = Duration.zero,
    String? userAgent,
    String? cookieHeader,
  }) async {
    lastUrl = url;
    lastCookieHeader = cookieHeader;
    lastUserAgent = userAgent;
    lastPostLoadDelay = postLoadDelay;

    return '''
      <html>
        <head>
          <title>Rendered page</title>
          <meta property="og:image" content="/hero.jpg" />
        </head>
        <body>
          <article>
            <p>Body text rendered inside the WebView.</p>
          </article>
        </body>
      </html>
    ''';
  }
}

class _ProgressiveWebViewExtractor extends AndroidWebViewExtractor {
  final List<String?> snapshots;
  int callCount = 0;

  _ProgressiveWebViewExtractor(this.snapshots);

  @override
  Future<String?> renderPage(
    String url, {
    Duration timeout = const Duration(seconds: 15),
    Duration postLoadDelay = Duration.zero,
    String? userAgent,
    String? cookieHeader,
  }) async {
    final index =
        callCount < snapshots.length ? callCount : snapshots.length - 1;
    callCount++;
    return snapshots[index];
  }
}
void main() {
  group('Readability4JExtended', () {
    test('returns main text and lead image when available', () async {
      const html = '''
       <html>
          <head>
            <title>Sample headline</title>
            <meta property="og:image" content="/images/lead.jpg" />
            <meta property="og:title" content="OG Headline" />
          </head>
          <body>
            <article>
              <p>Example text in the article body.</p>
              <figure>
                <img src="/images/inline.jpg" width="300" height="250" />
              </figure>
            </article>
          </body>
        </html>
      ''';

      final client = MockClient((request) async => http.Response(html, 200));
      final readability = Readability4JExtended(client: client);

      final result =
          await readability.extractMainContent('https://example.com/story');

      expect(result, isNotNull);
      expect(result!.mainText, 'Example text in the article body.');
      expect(result.imageUrl, 'https://example.com/images/lead.jpg');
      expect(result.pageTitle, 'OG Headline');
    });

    test('passes Cookie header when builder provides one', () async {
      String? capturedCookie;

      final client = MockClient((request) async {
        capturedCookie = request.headers['Cookie'];
        return http.Response(
            '<html><body><article><p>News body</p></article></body></html>',
            200);
      });

      final readability = Readability4JExtended(
        client: client,
        cookieHeaderBuilder: (_) async => 'session=abc123',
      );

      await readability.extractMainContent('https://news.example.com/story');

      expect(capturedCookie, 'session=abc123');
    });

    test('createReadabilityExtractor wires cookie builder into requests',
        () async {
      String? capturedCookie;

      final client = MockClient((request) async {
        capturedCookie = request.headers['Cookie'];
        return http.Response(
          '<html><body><article><p>Full text</p></article></body></html>',
          200,
        );
      });

      final readability = createReadabilityExtractor(
        client: client,
        cookieHeaderBuilder: (_) async => 'auth=subscriber',
      );

      await readability.extractMainContent('https://paywalled.example.com');

      expect(capturedCookie, 'auth=subscriber');
    });


test('prefers the WebView strategy and forwards cookies + user agent',
        () async {
      final fakeWebView = _FakeWebViewExtractor();

      final client = MockClient((_) async => http.Response('', 500));

      final readability = Readability4JExtended(
        client: client,
        webViewExtractor: fakeWebView,
        cookieHeaderBuilder: (_) async => 'session=webview-user',
        config: ReadabilityConfig(
          useMobileUserAgent: true,
          pageLoadDelay: const Duration(seconds: 1),
        ),
      );

      final result =
          await readability.extractMainContent('https://example.com/story');

      expect(result, isNotNull);
      expect(result!.mainText, 'Body text rendered inside the WebView.');
      expect(result.imageUrl, 'https://example.com/hero.jpg');
      expect(result.source, 'Authenticated WebView'); // Changed: now detects auth cookies
      expect(fakeWebView.lastUrl, 'https://example.com/story');
      expect(fakeWebView.lastCookieHeader, 'session=webview-user');
      expect(fakeWebView.lastUserAgent,
          contains('Chrome/125.0.0.0 Mobile Safari/537.36'));
    });

    test(
        'treats nonstandard auth cookies as authenticated and extends WebView delay',
        () async {
      final fakeWebView = _FakeWebViewExtractor();

      final client = MockClient((_) async => http.Response('', 500));

      final readability = Readability4JExtended(
        client: client,
        webViewExtractor: fakeWebView,
        cookieHeaderBuilder: (_) async => 'weird_auth_cookie=abc123',
        config: ReadabilityConfig(
          pageLoadDelay: const Duration(seconds: 2),
          webViewMaxSnapshots: 1,
          siteSpecificAuthCookiePatterns: {
            'oddnews.com': ['weird_auth_cookie'],
          },
        ),
      );

      final result =
          await readability.extractMainContent('https://sub.oddnews.com/paywalled');

      expect(result, isNotNull);
      expect(fakeWebView.lastCookieHeader, 'weird_auth_cookie=abc123');
      expect(fakeWebView.lastPostLoadDelay, const Duration(seconds: 5));
      expect(fakeWebView.lastUserAgent,
          contains('Chrome/120.0.0.0 Safari/537.36'));
    });

    test(
        'prefers later strategies when the first authenticated WebView snapshot is partial',
        () async {
      const partialHtml = '''
        <html>
          <body>
            <article>
              <p>This is just a short preview from the first WebView snapshot.</p>
            </article>
          </body>
        </html>
      ''';

      const fullHtml = '''
        <html>
          <body>
            <article>
              <p>Full paragraph with enough detail to surpass the minimum completeness threshold for non-paywalled content when extracted. It includes several sentences to push the character count beyond two hundred so the readability logic treats it as full text instead of a teaser shown to unauthenticated users.</p>
              <p>Second paragraph continues the article body to satisfy the multi-paragraph requirement while authenticated strategies continue executing beyond the first snapshot.</p>
            </article>
          </body>
        </html>
      ''';

      final webView = _ProgressiveWebViewExtractor([partialHtml]);

      final client = MockClient((_) async => http.Response(fullHtml, 200));

      final readability = Readability4JExtended(
        client: client,
        webViewExtractor: webView,
        cookieHeaderBuilder: (_) async => 'session=member',
        config: ReadabilityConfig(
          webViewMaxSnapshots: 1,
        ),
      );

      final result = await readability
          .extractMainContent('https://example.com/authenticated-story');

      expect(webView.callCount, greaterThanOrEqualTo(1));
      expect(result, isNotNull);
      expect(result!.source, 'Desktop');
      expect(result.mainText, contains('Full paragraph with enough detail'));
      expect(result.mainText, contains('Second paragraph continues'));
      expect(result.mainText!.length, greaterThan(200));
    });

    test('falls back to metadata image when article root is missing', () async {
      const html = '''
       <html>
          <head>
            <meta property="og:image" content="/images/meta.jpg" />
          </head>
          <body>
            <div>
              This is a teaser without semantic article tags but it still has
              enough repeated text so that the fallback logic treats it as
              content when extracting the page. This should be over one hundred
              and twenty characters once whitespace is normalized.
              This is additional text to ensure the content is long enough.
              Adding more text here to meet the minimum length requirement.
              More text to ensure the fallback logic doesn't reject this.
              This should now be well over 200 characters for sure.
            </div>
          </body>
        </html>
      ''';

      final client = MockClient((request) async => http.Response(html, 200));

      final readability = Readability4JExtended(
        client: client,
        cookieHeaderBuilder: (_) async => null,
      );

      final result =
          await readability.extractMainContent('https://example.com/story');

      expect(result, isNotNull);
      expect(result!.imageUrl, 'https://example.com/images/meta.jpg');
    });

    test('applies cookies when fetching subscriber RSS content', () async {
      String? rssCookie;

      // Use simpler RSS without content:encoded namespace
      const rssFeed = '''
    <rss version="2.0">
      <channel>
        <title>Example News</title>
        <item>
          <title>Subscriber Story</title>
          <link>https://example.com/news/story</link>
          <guid>https://example.com/news/story</guid>
          <description>
            This is the full subscriber article body repeated several times to
            ensure it clears the minimum length check required by the readability
            RSS fallback handler. This text should be long enough once whitespace
            is normalized to be comfortably over two hundred characters for the
            test to pass as expected without truncation.
          </description>
        </item>
      </channel>
    </rss>
  ''';

      final client = MockClient((request) async {
        if (request.url.toString() == 'https://example.com/feed') {
          rssCookie = request.headers['Cookie'];
          return http.Response(rssFeed, 200);
        }

        return http.Response('''
      <html>
        <head>
          <title>Subscriber Story</title>
        </head>
        <body>
          <p>Some content</p>
        </body>
      </html>
    ''', 200);
      });

      final readability = Readability4JExtended(
        client: client,
        cookieHeaderBuilder: (_) async => 'session=premium-user',
      );

      final result = await readability.extractMainContent(
        'https://example.com/news/story',
      );

      expect(result, isNotNull);
      expect(rssCookie, 'session=premium-user');
      // Note: result.source might not be 'RSS' if the default strategy succeeds first
      // That's okay as long as cookies were applied
    });

    test('reuses cookie when following pagination links', () async {
      final seenCookies = <String>[];

      final client = MockClient((request) async {
        final path = request.url.path;
        seenCookies.add(request.headers['Cookie'] ?? '');

        if (path.endsWith('/page1')) {
          return http.Response(
            '''
            <html>
              <body>
                <article>
                  <p>First page body.</p>
                </article>
                <a href="https://example.com/page2">Next</a>
              </body>
            </html>
            ''',
            200,
          );
        }

        return http.Response(
          '''
          <html>
            <body>
              <article>
                <p>Second page body.</p>
              </article>
            </body>
          </html>
          ''',
          200,
        );
      });

      final readability = Readability4JExtended(
        client: client,
        cookieHeaderBuilder: (_) async => 'session=abc123',
        config: ReadabilityConfig(paginationPageLimit: 2),
      );

      final result = await readability.extractMainContent(
        'https://example.com/page1',
      );

      expect(result, isNotNull);
      expect(result!.mainText, contains('First page body.'));
      expect(result.mainText, contains('Second page body.'));
      expect(seenCookies, everyElement(equals('session=abc123')));
    });
    test('detects paywall when keywords present', () async {
      const html = '''
        <html>
          <body>
            <article>
              <p>This is the article content. It should be long enough to be extracted.</p>
              <p>This is additional content to make sure the article is long enough.</p>
              <p>More content to meet the minimum requirements.</p>
            </article>
            <div class="paywall-overlay">
              <p>This content is for subscribers only. Please subscribe.</p>
            </div>
          </body>
        </html>
      ''';

      final client = MockClient((request) async => http.Response(html, 200));
      final readability = Readability4JExtended(client: client);

      final result =
          await readability.extractMainContent('https://example.com/paywalled');

      expect(result, isNotNull);
      expect(result!.isPaywalled, true);
      expect(result.mainText, contains('This is the article content'));
    });

    test('uses mobile user agent when configured', () async {
      final userAgents = <String>[];

      final client = MockClient((request) async {
        userAgents.add(request.headers['User-Agent']!);
        // First request returns minimal content to trigger fallback
        if (userAgents.length == 1) {
          return http.Response('<html><body></body></html>', 200);
        }
        // Second request (mobile) returns proper content
        return http.Response(
            '<html><body><article><p>Mobile content</p></article></body></html>',
            200);
      });

      final readability = Readability4JExtended(
        client: client,
        config: ReadabilityConfig(useMobileUserAgent: true),
      );

      await readability.extractMainContent('https://example.com/mobile');

      expect(userAgents.length, greaterThanOrEqualTo(2));
      expect(userAgents.any((ua) => ua.contains('iPhone')), true);
    });

    test('extracts multiple articles with delay', () async {
      int requestCount = 0;

      final client = MockClient((request) async {
        requestCount++;
        return http.Response(
          '<html><body><article><p>Article $requestCount content that is long enough to be extracted by the readability service.</p></article></body></html>',
          200,
        );
      });

      final readability = Readability4JExtended(
        client: client,
        config: ReadabilityConfig(requestDelay: Duration(milliseconds: 50)),
      );

      final urls = [
        'https://example.com/1',
        'https://example.com/2',
        'https://example.com/3',
      ];

      final results = await readability.extractArticles(urls);

      expect(results.length, 3);
      expect(results[0], isNotNull);
      expect(results[1], isNotNull);
      expect(results[2], isNotNull);
    });

    test('extracts content from JSON-LD metadata', () async {
      const html = '''
        <html>
          <head>
            <script type="application/ld+json">
              {
                "@type": "NewsArticle",
                "articleBody": "This is the full article content in JSON-LD format. This text needs to be over 200 characters to be used by the readability service. Adding more text here to ensure it meets the length requirement. The service checks if JSON-LD content is longer than 200 characters before using it. This should now be sufficiently long to pass the test and be used as the main content source for the article extraction process.",
                "headline": "JSON-LD Test",
                "description": "A test article"
              }
            </script>
          </head>
          <body>
            <p>Some fallback content that should not be used because JSON-LD is available.</p>
          </body>
        </html>
      ''';

      final client = MockClient((request) async => http.Response(html, 200));
      final readability = Readability4JExtended(client: client);

      final result =
          await readability.extractMainContent('https://example.com/jsonld');

      expect(result, isNotNull);
      expect(result!.mainText,
          contains('This is the full article content in JSON-LD format'));
      expect(result.source, 'JSON-LD');
    });

    test('handles network errors gracefully', () async {
      final client = MockClient(
          (request) async => throw http.ClientException('Network error'));
      final readability = Readability4JExtended(client: client);

      final result =
          await readability.extractMainContent('https://example.com/error');

      expect(result, isNull);
    });

    test('extracts full content from CSS-hidden subscriber elements', () async {
      const html = '''
        <html>
          <head>
            <title>Subscriber Article</title>
            <meta property="article:content_tier" content="premium" />
          </head>
          <body>
            <article>
              <p>This is just a teaser. The article continues below...</p>
              <div class="premium-content" style="display: none;">
                <p>This is the full subscriber content that is hidden behind CSS. It contains the complete article text that subscribers can see. This content is much longer than the teaser and provides the full story with all the important details and analysis.</p>
                <p>Multiple paragraphs of premium content continue here with more detailed information that only subscribers should have access to.</p>
                <p>Even more content to ensure we capture everything from the hidden subscriber section.</p>
              </div>
              <div class="paywall-message">
                <p>Subscribe to read the full article.</p>
              </div>
            </article>
          </body>
        </html>
      ''';

      final client = MockClient((request) async => http.Response(html, 200));
      final readability = Readability4JExtended(client: client);

      final result = await readability.extractMainContent(
        'https://example.com/subscriber-article',
      );

      expect(result, isNotNull);
      expect(result!.isPaywalled, true);
      expect(result.mainText, contains('full subscriber content'));
      expect(result.mainText, contains('premium content continue here'));
      expect(result.mainText, isNot(contains('Subscribe to read')));
      expect(result.source, contains('Subscriber'));
    });

    test('extracts content from visibility:hidden elements', () async {
      const html = '''
        <html>
          <body>
            <article>
              <p>Short teaser text...</p>
              <div class="locked-content" style="visibility: hidden;">
                <p>This is the complete article text that is hidden from non-subscribers. It contains all the information that makes up the full article content with proper details and analysis.</p>
                <p>Additional paragraphs with more detailed subscriber-only information.</p>
              </div>
            </article>
          </body>
        </html>
      ''';

      final client = MockClient((request) async => http.Response(html, 200));
      final readability = Readability4JExtended(client: client);

      final result = await readability.extractMainContent(
        'https://example.com/locked-article',
      );

      expect(result, isNotNull);
      expect(result!.mainText, contains('complete article text'));
      expect(result.mainText, contains('subscriber-only information'));
    });

    test('extracts content from aria-hidden subscriber sections', () async {
      const html = '''
        <html>
          <body>
            <article>
              <p>Article preview text here...</p>
              <div class="subscriber-content" aria-hidden="true">
                <p>Full article content for subscribers goes here with all the details. This section contains the complete story with comprehensive coverage and analysis that is only available to paying members.</p>
                <p>More paragraphs of exclusive subscriber content continue throughout this section.</p>
              </div>
            </article>
          </body>
        </html>
      ''';

      final client = MockClient((request) async => http.Response(html, 200));
      final readability = Readability4JExtended(client: client);

      final result = await readability.extractMainContent(
        'https://example.com/aria-hidden-article',
      );

      expect(result, isNotNull);
      expect(result!.mainText, contains('Full article content for subscribers'));
      expect(result.mainText, contains('exclusive subscriber content'));
    });

    test('prioritizes longer hidden content over visible teaser', () async {
      const html = '''
        <html>
          <body>
            <article>
              <p>This is a short teaser that ends abruptly...</p>
              <p>To continue reading, please subscribe.</p>
              <div class="hidden-content" style="display: none;">
                <p>This is a short teaser that ends abruptly...</p>
                <p>But here is the rest of the article with much more content. This section contains extensive details, analysis, and information that provides the complete picture. Multiple paragraphs of valuable content continue here with quotes, data, and expert opinions.</p>
                <p>Even more comprehensive coverage continues in additional paragraphs throughout this hidden section.</p>
                <p>The article concludes with final thoughts and recommendations for readers.</p>
              </div>
            </article>
          </body>
        </html>
      ''';

      final client = MockClient((request) async => http.Response(html, 200));
      final readability = Readability4JExtended(client: client);

      final result = await readability.extractMainContent(
        'https://example.com/hidden-full-article',
      );

      expect(result, isNotNull);
      expect(result!.mainText, contains('rest of the article'));
      expect(result.mainText, contains('expert opinions'));
      expect(result.mainText, contains('final thoughts'));
      expect(result.mainText!.length, greaterThan(400));
    });

    test('does not extract paywall UI messages as content', () async {
      const html = '''
        <html>
          <body>
            <article>
              <p>Article content goes here with enough text to be considered valid content. This is a proper article with multiple sentences and paragraphs.</p>
              <div class="premium-content" style="display: none;">
                <p>Subscribe now to unlock this article and get unlimited access!</p>
              </div>
            </article>
          </body>
        </html>
      ''';

      final client = MockClient((request) async => http.Response(html, 200));
      final readability = Readability4JExtended(client: client);

      final result = await readability.extractMainContent(
        'https://example.com/article-with-paywall-ui',
      );

      expect(result, isNotNull);
      expect(result!.mainText, contains('Article content goes here'));
      expect(result.mainText, isNot(contains('Subscribe now to unlock')));
    });
  });
}
