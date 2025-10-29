import 'package:flutter/material.dart';

import 'news_page.dart';
import 'feed_page.dart';
import 'settings_page.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 1; // default to News tab like your screenshot

  @override
  Widget build(BuildContext context) {
    Widget page;
    switch (_index) {
      case 0:
        page = const SettingsPage();
        break;
      case 1:
        page = const NewsPage();
        break;
      case 2:
        page = const FeedPage();
        break;
      default:
        page = const NewsPage();
    }

    return Scaffold(
      body: page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() {
            _index = i;
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
