import 'package:flutter/services.dart';

/// Provides access to platform WebView cookies to reuse them in network calls.
class CookieBridge {
  CookieBridge();

  static const _channel = MethodChannel('com.flutter_rss_reader/cookies');

  /// Returns the Cookie header value for the given [url], if available.
  Future<String?> buildHeader(String url) async {
    try {
      final cookie = await _channel.invokeMethod<String>(
        'getCookies',
        {'url': url},
      );
      if (cookie == null || cookie.isEmpty) return null;
      return cookie;
    } on PlatformException {
      return null;
    }
  }
}