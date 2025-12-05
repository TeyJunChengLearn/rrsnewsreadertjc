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
  Future<String?> renderPageEnhanced(
    String url, {
    Duration timeout = const Duration(seconds: 20),
    Duration postLoadDelay = const Duration(seconds: 3),
    String? userAgent,
    String? cookieHeader,
    List<String>? javascriptToExecute,
    bool removePaywalls = true,
  }) async {
    try {
      final html = await _channel.invokeMethod<String>('renderPageEnhanced', {
        'url': url,
        'timeoutMs': timeout.inMilliseconds,
        'postLoadDelayMs': postLoadDelay.inMilliseconds,
        'userAgent': userAgent,
        'cookieHeader': cookieHeader,
        'javascriptToExecute': javascriptToExecute ?? _getDefaultJavascript(),
        'removePaywalls': removePaywalls,
      });

      return html;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  List<String> _getDefaultJavascript() {
    return [
      // Remove common paywall elements
      '''
      document.querySelectorAll('[class*="paywall"], [id*="paywall"], [class*="premium"], [class*="subscribe"]').forEach(el => el.remove());
      ''',
      // Remove overlays
      '''
      document.querySelectorAll('.overlay, .modal, .dialog, [class*="gate"]').forEach(el => el.remove());
      ''',
      // Remove blur effects
      '''
      document.querySelectorAll('*').forEach(el => {
        const style = window.getComputedStyle(el);
        if (style.filter.includes('blur') || style.webkitFilter.includes('blur')) {
          el.style.filter = 'none';
          el.style.webkitFilter = 'none';
        }
      });
      ''',
      // Remove display:none on content
      '''
      document.querySelectorAll('[style*="display:none"], [style*="visibility:hidden"]').forEach(el => {
        el.style.display = 'block';
        el.style.visibility = 'visible';
      });
      ''',
      // Click any "continue reading" buttons
      '''
      document.querySelectorAll('button, a').forEach(btn => {
        const text = btn.textContent.toLowerCase();
        if (text.includes('continue reading') || text.includes('read more')) {
          btn.click();
        }
      });
      ''',
    ];
  }
}