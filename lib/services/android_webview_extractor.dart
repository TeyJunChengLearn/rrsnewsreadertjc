import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// Android-only helper that renders pages in an off-screen WebView and returns
/// the full outer HTML so it can be parsed by Readability4JExtended.
class AndroidWebViewExtractor {
  static const _channel = MethodChannel('com.flutter_rss_reader/cookies');

  /// Renders [url] in a headless WebView with JavaScript and DOM storage
  /// enabled, then returns the page's `document.documentElement.outerHTML`.
  /// If rendering fails or times out, `null` is returned.
  Future<String?> renderPage(
    String url, {
    Duration timeout = const Duration(seconds: 15),
    Duration postLoadDelay = Duration.zero,
    String? userAgent,
    String? cookieHeader,
  }) async {
    try {
      final html = await _channel.invokeMethod<String>('renderPage', {
        'url': url,
        'timeoutMs': timeout.inMilliseconds,
        'postLoadDelayMs': postLoadDelay.inMilliseconds,
        'userAgent': userAgent,
        'cookieHeader': cookieHeader,
      });

      if (html == null || html.isEmpty) return null;

      try {
        final decoded = jsonDecode(html);
        if (decoded is String) return decoded;
      } catch (_) {
        // If the platform already returns a raw string, fall back to it as-is.
      }

      return html;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}