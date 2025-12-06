// lib/screens/site_login_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/cookie_bridge.dart';

class SiteLoginPage extends StatefulWidget {
  final String initialUrl;
  final String siteName;

  const SiteLoginPage({
    super.key,
    required this.initialUrl,
    required this.siteName,
  });

  @override
  State<SiteLoginPage> createState() => _SiteLoginPageState();
}

class _SiteLoginPageState extends State<SiteLoginPage> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<void> _submitCookies() async {
    final bridge = context.read<CookieBridge>();
    final currentUrl = await _controller.currentUrl();

    if (currentUrl == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to determine current page for cookies')),
      );
      return;
    }

    // Submit (flush) cookies from WebView
    final cookies = await bridge.submitCookies(currentUrl);

    if (!mounted) return;
    if (cookies == null || cookies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ No cookies detected yet. Make sure you\'ve logged in first.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Check if we have subscription/authentication cookies
    final hasAuthCookies = await bridge.hasSubscriptionCookies(currentUrl);

    if (!mounted) return;

    // Count cookies for user feedback
    final cookieCount = cookies.split(';').length;

    if (hasAuthCookies) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✓ Login successful! Saved $cookieCount authentication cookies'),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ℹ️ Saved $cookieCount cookies (no login cookies detected)'),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    // Close the login page after a short delay
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(widget.initialUrl);
    try {
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No browser available to open link')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open browser')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sign in to ${widget.siteName}'),
        actions: [
          IconButton(
            tooltip: 'Save cookies & finish',
            icon: const Icon(Icons.check_circle_outline),
            onPressed: _submitCookies,
          ),
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(Icons.open_in_browser),
            onPressed: _openInBrowser,
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}