# flutter_rss_reader_v2

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## How the app reaches and processes articles

The extractor mirrors the flow shown in the screenshot:

1. A background task spins up an off-screen **WebView** with JavaScript and DOM
   storage enabled, then loads each article URL gathered from refreshed feeds.
2. After the page finishes loading, the WebView dumps the full rendered HTML.
   That HTML is piped through **Readability4JExtended** to strip layout noise,
   media, ads, and non-article segments so only the clean main text remains.
3. The cleaned HTML plus extracted text are written to SQLite by the
   `EntryRepository`, making later offline reading or TTS playback instant and
   avoiding repeated fetches.【F:lib/providers/rss_provider.dart†L117-L157】【F:lib/services/article_content_service.dart†L8-L53】【F:lib/screens/article_webview_page.dart†L340-L421】

## What happens with subscription/paid content

Subscriber pages follow the exact same pipeline—no hidden bypasses:

- The WebView loads the public article URL and carries the same cookies and
  local storage you have in a normal browser session. If the site shows you a
  paywall, the extractor only sees that HTML. If you are logged in, the
  rendered subscriber version is what gets captured and fed into
  Readability4JExtended for main text extraction.
- On Android, an off-screen WebView now renders each article (with JavaScript,
  DOM storage, and your session cookies enabled) and returns the full HTML to
  Readability4JExtended. That same cookie jar is reused for network fetches, so
  authenticated paid articles are captured with their complete main text.
- All requests for protected pages automatically include the WebView’s cookies
  so the extractor can fetch the paid content you already have access to. The
  captured text and HTML are persisted through the repository for offline
  reading or TTS just like free articles.【F:lib/screens/article_webview_page.dart†L340-L381】【F:lib/screens/article_webview_page.dart†L771-L906】【F:lib/services/readability_service.dart†L474-L535】
# rrsnewsreadertjc

## Accessing paywalled articles

The readability service can fetch subscriber-only pages as long as you provide
valid session cookies for the site you already have access to. Configure a
`cookieHeaderBuilder` (or static `cookies` map) when constructing
`Readability4JExtended` so each request includes the correct authentication
cookie for that domain.

**Is full paid-article capture possible? Yes—provided you sign in and let the
WebView hand those cookies to Readability4JExtended.** The extractor does not
evade paywalls; it simply reuses your authenticated session so the main text of
subscriber pages can be parsed and stored just like free articles.

### Quick steps (works for any paywalled news site)
1. Add the feed as usual.
2. When prompted **"Does this news feed require a login account?"** tap **Yes**.
   The in-app webview opens the site so you can sign in with your own
   subscription account.
3. After signing in, go back to the feed and reload/extract again. The
   readability service will automatically reuse the cookies collected by the
   webview for every article URL from that domain.

If you prefer to wire cookies manually (e.g., for testing), you can also supply
them per host:

Example (per-URL cookies):

```dart
final readability = Readability4JExtended(
  cookieHeaderBuilder: (url) async {
    final host = Uri.parse(url).host;
    if (host.contains('malaysiakini')) {
      return 'mk-ssid=<your-signed-in-cookie>'; // replace with your own value
    }
    if (host.contains('example-paywall.com')) {
      return 'sessionid=<your-session-cookie>';
    }
    return null; // fall back to public access
  },
);
```

This mechanism is global—any supported site can be fetched if the cookie is
valid. The service does **not** bypass paywalls; you must supply your own
subscriber cookies in accordance with the site’s terms.

## Troubleshooting

If you see build failures mentioning `webview_cookie_manager` (for example,
errors about `PluginRegistry.Registrar`), the project no longer uses that
plugin. Clear stale artifacts and refresh dependencies:

```sh
flutter clean
flutter pub cache repair
flutter pub get
```

These commands remove cached plugin code so the app builds with the in-app
cookie bridge instead.

### Cookies don’t seem to stick
- **Confirm the article is being fetched over HTTP.** If you tap “Open in
  WebView” and extraction still fails, the app may be pulling HTML from the
  WebView DOM (no extra fetch), so the bridge is not involved. Try the normal
  extraction first so the network path runs with cookies.
- **Check that the site’s host appears in the captured header.** After signing
  in via the in-app WebView, reload the feed; the readability service will call
  `cookieHeaderBuilder` with the article URL. Log the returned header to verify
  the session cookie is present for that host.
- **Force a manual cookie header if needed.** During debugging you can hardcode
  a header in `Readability4JExtended(cookieHeaderBuilder: ...)` to confirm the
  server accepts it. Once verified, remove the hardcoded value so the bridge
  can supply fresh cookies from the WebView session.