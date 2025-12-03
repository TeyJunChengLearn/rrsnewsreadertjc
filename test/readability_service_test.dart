import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_rss_reader/services/readability_service.dart';

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

      final result = await readability.extractMainContent('https://example.com/story');

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

    test('falls back to metadata image when article root is missing', () async {
      const html = '''
       <html>
          <head>
            <meta property="og:image" content="/images/meta.jpg" />
          </head>
          <body>
            <div class="teaser">
              This is a teaser without semantic article tags but it still has
              enough repeated text so that the fallback logic treats it as
              content when extracting the page. This should be over one hundred
              and twenty characters once whitespace is normalized.
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
  });
}