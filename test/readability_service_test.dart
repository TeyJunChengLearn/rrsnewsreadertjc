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
      final readability = Readability4JExtended(
        client: client,
        cookieHeaderBuilder: (_) async => null,
      );
      final result = await readability.extractMainContent('https://example.com/story');

      expect(result, isNotNull);
      expect(result!.mainText, 'Example text in the article body.');
      expect(result.imageUrl, 'https://example.com/images/lead.jpg');
      expect(result.pageTitle, 'OG Headline');
    });
  });
}