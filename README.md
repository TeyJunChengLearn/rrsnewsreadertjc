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
# rrsnewsreadertjc

## Accessing paywalled articles

The readability service can fetch subscriber-only pages as long as you provide
valid session cookies for the site you already have access to. Configure a
`cookieHeaderBuilder` (or static `cookies` map) when constructing
`Readability4JExtended` so each request includes the correct authentication
cookie for that domain.

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