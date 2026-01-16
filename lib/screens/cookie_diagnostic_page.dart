// lib/screens/cookie_diagnostic_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/cookie_bridge.dart';

class CookieDiagnosticPage extends StatefulWidget {
  const CookieDiagnosticPage({super.key});

  @override
  State<CookieDiagnosticPage> createState() => _CookieDiagnosticPageState();
}

class _CookieDiagnosticPageState extends State<CookieDiagnosticPage> {
  final _urlController = TextEditingController(
    text: 'https://www.malaysiakini.com/',
  );

  bool _isChecking = false;
  Map<String, String> _cookies = {};
  bool _hasAuthCookies = false;
  String _diagnosticLog = '';

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _runDiagnostics() async {
    setState(() {
      _isChecking = true;
      _diagnosticLog = 'Starting diagnostics...\n';
      _cookies.clear();
      _hasAuthCookies = false;
    });

    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _isChecking = false;
        _diagnosticLog += 'ERROR: URL is empty\n';
      });
      return;
    }

    try {
      final cookieBridge = context.read<CookieBridge>();

      _log('Testing URL: $url\n');

      // Step 1: Get all cookies
      _log('Step 1: Fetching all cookies...');
      final cookies = await cookieBridge.getAllCookiesForDomain(url);
      _log('Found ${cookies.length} cookies\n');

      if (cookies.isNotEmpty) {
        cookies.forEach((key, value) {
          _log('  • $key = ${value.length > 50 ? "${value.substring(0, 50)}..." : value}');
        });
      } else {
        _log('  ⚠ WARNING: No cookies found!');
        _log('  This means you are NOT logged in for this site.\n');
      }

      // Step 2: Get cookie header
      _log('\nStep 2: Building cookie header...');
      final header = await cookieBridge.buildHeader(url);
      _log(header != null && header.isNotEmpty
        ? 'Cookie header built (${header.length} chars)'
        : '⚠ WARNING: Cookie header is empty!\n');

      if (header != null && header.isNotEmpty) {
        _log('  Preview: ${header.length > 100 ? "${header.substring(0, 100)}..." : header}\n');
      }

      // Step 3: Check for auth patterns
      _log('\nStep 3: Checking for authentication cookies...');
      final authPatterns = ['mkini', 'session', 'auth', 'subscriber', 'logged', 'member', 'premium', 'token'];
      final foundPatterns = <String>[];

      if (header != null && header.isNotEmpty) {
        final lowerHeader = header.toLowerCase();
        for (final pattern in authPatterns) {
          if (lowerHeader.contains(pattern)) {
            foundPatterns.add(pattern);
          }
        }
      }

      if (foundPatterns.isNotEmpty) {
        _log('✓ Found auth-like cookie patterns: ${foundPatterns.join(", ")}');
        _log('  This suggests you ARE authenticated!\n');
      } else {
        _log('⚠ WARNING: No auth-like cookie patterns found!');
        _log('  You may not be properly logged in.\n');
      }

      // Step 4: Test readability authentication detection
      _log('\nStep 4: Testing Readability authentication detection...');
      _log('This requires accessing private method, so we\'ll infer from cookie header...');

      final hasAuth = header != null && header.isNotEmpty && foundPatterns.isNotEmpty;
      _log(hasAuth
        ? '✓ Readability SHOULD detect you as authenticated'
        : '✗ Readability will NOT detect you as authenticated\n');

      // Step 5: Recommendations
      _log('\n' + '=' * 50);
      _log('DIAGNOSIS SUMMARY');
      _log('=' * 50);

      if (cookies.isEmpty) {
        _log('❌ PROBLEM: No cookies found');
        _log('   SOLUTION: You need to log in to $url');
        _log('   1. Go to "Add feed" → Add Malaysiakini feed');
        _log('   2. Check "Requires login"');
        _log('   3. Log in through the WebView');
        _log('   4. Save the feed');
      } else if (!hasAuth) {
        _log('⚠ POSSIBLE PROBLEM: Cookies exist but no auth patterns');
        _log('   Your cookies may be:');
        _log('   - Non-authentication cookies (tracking, preferences)');
        _log('   - Expired session cookies');
        _log('   - Cookies for a different subdomain');
        _log('   SOLUTION: Try logging in again');
      } else {
        _log('✓ LOOKS GOOD: You have authentication cookies!');
        _log('   If you\'re still seeing preview text only:');
        _log('   1. Try refreshing the article');
        _log('   2. Check if your subscription is active');
        _log('   3. Verify you\'re logged into the correct account');
        _log('\n   Cookie details will be used for:');
        _log('   • WebView rendering (to load full subscriber content)');
        _log('   • HTTP requests (to fetch authenticated RSS feeds)');
        _log('   • Hidden content extraction (to find unlocked paywalled text)');
      }

      setState(() {
        _cookies = cookies;
        _hasAuthCookies = hasAuth;
        _isChecking = false;
      });
    } catch (e, stack) {
      _log('\n❌ ERROR: $e');
      _log('Stack trace: $stack');
      setState(() => _isChecking = false);
    }
  }

  void _log(String message) {
    setState(() {
      _diagnosticLog += '$message\n';
    });
  }

  Future<void> _copyLog() async {
    await Clipboard.setData(ClipboardData(text: _diagnosticLog));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostic log copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cookie Diagnostics'),
        actions: [
          if (_diagnosticLog.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _copyLog,
              tooltip: 'Copy log',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Cookie Authentication Checker',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'This tool helps diagnose why you might be getting only preview text instead of full subscriber content.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),

          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'URL to check',
              border: OutlineInputBorder(),
              helperText: 'Enter the news site URL (e.g., Malaysiakini)',
            ),
          ),
          const SizedBox(height: 16),

          ElevatedButton.icon(
            onPressed: _isChecking ? null : _runDiagnostics,
            icon: _isChecking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
            label: Text(_isChecking ? 'Checking...' : 'Run Diagnostics'),
          ),

          if (_diagnosticLog.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  _diagnosticLog,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],

          if (_cookies.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            Row(
              children: [
                const Text(
                  'Cookies Found',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _hasAuthCookies ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _hasAuthCookies ? 'Authenticated' : 'No Auth',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            ..._cookies.entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.value.length > 100
                        ? '${entry.value.substring(0, 100)}...'
                        : entry.value,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            )),
          ],
        ],
      ),
    );
  }
}
