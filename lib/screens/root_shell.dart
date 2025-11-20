// lib/screens/root_shell.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/rss_provider.dart';
import '../providers/settings_provider.dart';

import 'news_page.dart';
import 'feed_page.dart';
import 'settings_page.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 1; // default to News tab

  SettingsProvider? _settings;
  Timer? _autoTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Attach listener to SettingsProvider so when interval changes,
    // we reconfigure the timer.
    final newSettings = Provider.of<SettingsProvider>(context);
    if (!identical(_settings, newSettings)) {
      _settings?.removeListener(_onSettingsChanged);
      _settings = newSettings;
      _settings!.addListener(_onSettingsChanged);
      _configureTimer();
    }
  }

  void _onSettingsChanged() {
    _configureTimer();
  }

  void _configureTimer() {
    _autoTimer?.cancel();

    final minutes = _settings?.updateIntervalMinutes ?? 0;
    if (minutes <= 0) {
      // 0 or negative => auto refresh OFF
      return;
    }

    _autoTimer = Timer.periodic(Duration(minutes: minutes), (_) {
      // Only auto-refresh when on News tab (index 1)
      if (!mounted || _index != 1) return;
      final rss = context.read<RssProvider>();
      rss.refresh();
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _settings?.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = const [
      SettingsPage(),
      NewsPage(),
      FeedPage(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() {
            _index = value;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
          NavigationDestination(
            icon: Icon(Icons.newspaper_outlined),
            selectedIcon: Icon(Icons.newspaper),
            label: 'News',
          ),
          NavigationDestination(
            icon: Icon(Icons.rss_feed_outlined),
            selectedIcon: Icon(Icons.rss_feed),
            label: 'Feeds',
          ),
        ],
      ),
    );
  }
}
