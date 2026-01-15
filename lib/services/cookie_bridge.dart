import 'package:flutter/services.dart';

/// Provides access to platform WebView cookies to reuse them in network calls.
class CookieBridge {
  CookieBridge();

  static const _channel = MethodChannel('com.flutter_rss_reader/cookies');

  /// Returns the Cookie header value for the given [url], if available.
  Future<String?> buildHeader(String url) async {
    try {
      print('CookieBridge: Fetching cookies for $url');
      final candidates = _candidateUrls(url);
      final mergedCookies = <String, String>{};

      for (final candidate in candidates) {
        final cookie = await _channel.invokeMethod<String>(
          'getCookies',
          {'url': candidate},
        );

        if (cookie == null || cookie.isEmpty) {
          print('CookieBridge: ⚠️ No cookies found for $candidate');
          continue;
        }

        final cookieMap = _parseCookieHeader(cookie);
        if (cookieMap.isNotEmpty) {
          mergedCookies.addAll(cookieMap);
          print('CookieBridge: ✓ Found ${cookieMap.length} cookies for $candidate');
        }
      }

      if (mergedCookies.isEmpty) {
        print('CookieBridge: ⚠️ No cookies found for $url');
        return null;
      }

      final header = mergedCookies.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('; ');
      print('CookieBridge: ✓ Returning ${mergedCookies.length} cookies for $url');
      return header;
    } on Exception catch (e) {
      print('CookieBridge: ❌ Error fetching cookies: $e');
      return null;
    }
  }

  List<String> _candidateUrls(String url) {
    final candidates = <String>{url};
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return candidates.toList();

    final scheme = uri.scheme.isNotEmpty ? uri.scheme : 'https';
    final baseHost = uri.host.startsWith('www.')
        ? uri.host.substring(4)
        : uri.host;
    final schemes = {scheme, 'https', 'http'};

    for (final candidateScheme in schemes) {
      candidates.add('$candidateScheme://$baseHost');
      candidates.add('$candidateScheme://www.$baseHost');
    }

    return candidates.toList();
  }

  Map<String, String> _parseCookieHeader(String cookieHeader) {
    final result = <String, String>{};
    for (final part in cookieHeader.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split('=');
      if (parts.isEmpty) continue;
      final key = parts.first.trim();
      if (key.isEmpty) continue;
      final value = parts.length > 1
          ? trimmed.substring(trimmed.indexOf('=') + 1).trim()
          : '';
      result[key] = value;
    }
    return result;
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

  Future<Map<String, String>> getAllCookiesForDomain(String url) async {
    try {
      final cookies = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getAllCookiesForDomain',
        {'url': url},
      );
      
      if (cookies == null) return {};
      
      // Convert to Map<String, String>
      final result = <String, String>{};
      cookies.forEach((key, value) {
        if (key is String && value is String) {
          result[key] = value;
        }
      });
      
      return result;
    } on Exception catch (_) {
      return {};
    }
  }

  /// NEW: Check if we have subscription cookies for a domain
  Future<bool> hasSubscriptionCookies(String url) async {
    try {
      final cookies = await getAllCookiesForDomain(url);

      const subscriptionCookieNames = [
        'subscription',
        'premium',
        'member',
        'subscriber',
        'logged_in',
        'session',
        'auth',
        'token',
        'mkini',  // Malaysiakini-specific
      ];

      return cookies.keys.any((key) {
        final lowerKey = key.toLowerCase();
        return subscriptionCookieNames.any((name) => lowerKey.contains(name));
      });
    } on Exception catch (_) {
      return false;
    }
  }

  /// NEW: Manually inject cookies for known paywall sites
  /// NOTE: These are placeholder patterns for testing only.
  /// For Malaysiakini and other subscription sites, users should log in
  /// through the proper login flow to get legitimate session cookies.
  Future<bool> injectPaywallCookies(String url) async {
    final uri = Uri.parse(url);
    final host = uri.host;

    // Known cookie patterns for bypassing paywalls
    // WARNING: These are test patterns and may not work for actual paywall bypass
    final cookiePatterns = {
      'medium.com': '_uid=1; lightstep_guid/medium=1;',
      'nytimes.com': 'nyt-a=1; nyt-gdpr=0;',
      'bloomberg.com': 'session=test;',
      'wsj.com': 'wsjregion=na;',
      'malaysiakini.com': 'mkini_session=test; subscriber=1;',  // Placeholder - users should login properly
    };

    for (final domain in cookiePatterns.keys) {
      if (host.contains(domain)) {
        return await setCookie(url, cookiePatterns[domain]!);
      }
    }

    return false;
  }

  /// Export all cookies for a list of domains.
  /// Returns a Map of domain -> Map of cookie name/value pairs.
  /// Used for backing up authentication state to Google Drive.
  Future<Map<String, Map<String, String>>> exportAllCookies(List<String> domains) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'exportAllCookies',
        {'domains': domains},
      );

      if (result == null) return {};

      final cookies = <String, Map<String, String>>{};
      result.forEach((domain, domainCookies) {
        if (domain is String && domainCookies is Map) {
          final cookieMap = <String, String>{};
          domainCookies.forEach((key, value) {
            if (key is String && value is String) {
              cookieMap[key] = value;
            }
          });
          if (cookieMap.isNotEmpty) {
            cookies[domain] = cookieMap;
          }
        }
      });

      return cookies;
    } on Exception catch (_) {
      return {};
    }
  }

  /// Import cookies from a backup.
  /// Takes a Map of domain -> Map of cookie name/value pairs.
  /// Returns true if successful.
  Future<bool> importCookies(Map<String, Map<String, String>> cookies) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        'importCookies',
        {'cookies': cookies},
      );
      return success ?? false;
    } on Exception catch (_) {
      return false;
    }
  }
}
