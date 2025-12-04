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
    } on Exception catch (_) {
      return null;
    }
  }
  /// Flushes cookies on the platform side and returns the current cookie
  /// header string for [url], if any. Intended for ensuring a WebView login
  /// session is persisted before making HTTP requests.
  Future<String?> submitCookies(String url) async {
    try {
      return await _channel.invokeMethod<String>(
        'submitCookies',
        {
          'url': url,
        },
      );
    } on Exception catch (_) {
      return null;
    }
  }

  /// Sets a cookie string for the given [url]. Returns whether the operation
  /// was submitted successfully to the platform.
  Future<bool> setCookie(String url, String cookie) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        'setCookie',
        {
          'url': url,
          'cookie': cookie,
        },
      );
      return success ?? false;
    } on Exception catch (_) {
      return false;
    }
  }

  /// Clears all cookies managed by the platform WebView.
  Future<bool> clearCookies() async {
    try {
      final cleared = await _channel.invokeMethod<bool>('clearCookies');
      return cleared ?? false;
    } on Exception catch (_) {
      return false;
    }
  }
}
