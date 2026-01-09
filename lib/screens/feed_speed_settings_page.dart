// lib/screens/feed_speed_settings_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/rss_provider.dart';
import 'article_webview_page.dart';

class FeedSpeedSettingsPage extends StatefulWidget {
  const FeedSpeedSettingsPage({super.key});

  @override
  State<FeedSpeedSettingsPage> createState() => _FeedSpeedSettingsPageState();
}

class _FeedSpeedSettingsPageState extends State<FeedSpeedSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final rss = context.watch<RssProvider>();
    final feeds = rss.sources;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed Speed Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Enable/disable toggle
          SwitchListTile(
            title: const Text('Custom speed per feed'),
            subtitle: Text(
              settings.customSpeedPerFeed
                  ? 'Different feeds can have different TTS speeds'
                  : 'All feeds use the same global TTS speed',
            ),
            value: settings.customSpeedPerFeed,
            onChanged: (v) async {
              await settings.setCustomSpeedPerFeed(v);
              await applyGlobalTtsSpeechRateFromSettings(settings);
            },
          ),

          if (settings.customSpeedPerFeed) ...[
            const Divider(height: 32),

            // Default speeds section
            _sectionHeader(context, 'Default Speeds'),
            const SizedBox(height: 8),
            const Text(
              'These speeds apply to feeds without custom settings.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),

            // Default original speed
            _SpeedSlider(
              label: 'Original language',
              value: settings.defaultOriginalSpeed,
              onChanged: (v) {
                settings.setDefaultOriginalSpeed(v);
                applyGlobalTtsSpeechRateFromSettings(settings);
              },
            ),
            const SizedBox(height: 16),

            // Default translated speed
            _SpeedSlider(
              label: 'Translated content',
              value: settings.defaultTranslatedSpeed,
              onChanged: (v) {
                settings.setDefaultTranslatedSpeed(v);
                applyGlobalTtsSpeechRateFromSettings(settings);
              },
            ),

            const Divider(height: 32),

            // Per-feed settings section
            _sectionHeader(context, 'Per-Feed Settings'),
            const SizedBox(height: 8),
            const Text(
              'Tap a feed to customize its TTS speed.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 16),

            // List of feeds
            ...feeds.map((feed) {
              final feedSettings = settings.feedSpeedSettings[feed.title];
              final hasCustom = feedSettings != null;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    Icons.rss_feed,
                    color: hasCustom ? Theme.of(context).colorScheme.primary : null,
                  ),
                  title: Text(
                    feed.title,
                    style: TextStyle(
                      fontWeight: hasCustom ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  subtitle: hasCustom
                      ? Text(
                          'Original: ${feedSettings['original']?.toStringAsFixed(2)}x, '
                          'Translated: ${feedSettings['translated']?.toStringAsFixed(2)}x',
                        )
                      : const Text('Using default speeds'),
                  trailing: hasCustom
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await settings.removeFeedSpeed(feed.title);
                            await applyGlobalTtsSpeechRateFromSettings(settings);
                          },
                          tooltip: 'Remove custom speed',
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () => _editFeedSpeed(context, feed.title, feedSettings),
                ),
              );
            }),

            if (feeds.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No feeds configured. Add feeds first to customize their speeds.',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Colors.red,
            fontWeight: FontWeight.w600,
            letterSpacing: .2,
          ),
    );
  }

  Future<void> _editFeedSpeed(
    BuildContext context,
    String feedTitle,
    Map<String, double>? currentSettings,
  ) async {
    final settings = context.read<SettingsProvider>();
    double originalSpeed = currentSettings?['original'] ?? settings.defaultOriginalSpeed;
    double translatedSpeed = currentSettings?['translated'] ?? settings.defaultTranslatedSpeed;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 16,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        feedTitle,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Original speed
                      const Text(
                        'Original language speed',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('0.3x'),
                          Expanded(
                            child: Slider(
                              min: 0.3,
                              max: 1.2,
                              divisions: 9,
                              value: originalSpeed,
                              label: '${originalSpeed.toStringAsFixed(2)}x',
                              onChanged: (v) {
                                setSheetState(() => originalSpeed = v);
                              },
                            ),
                          ),
                          const Text('1.2x'),
                        ],
                      ),
                      Center(
                        child: Text(
                          '${originalSpeed.toStringAsFixed(2)}x',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Translated speed
                      const Text(
                        'Translated content speed',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('0.3x'),
                          Expanded(
                            child: Slider(
                              min: 0.3,
                              max: 1.2,
                              divisions: 9,
                              value: translatedSpeed,
                              label: '${translatedSpeed.toStringAsFixed(2)}x',
                              onChanged: (v) {
                                setSheetState(() => translatedSpeed = v);
                              },
                            ),
                          ),
                          const Text('1.2x'),
                        ],
                      ),
                      Center(
                        child: Text(
                          '${translatedSpeed.toStringAsFixed(2)}x',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () async {
                              await settings.setFeedSpeed(
                                feedTitle,
                                originalSpeed,
                                translatedSpeed,
                              );
                              await applyGlobalTtsSpeechRateFromSettings(settings);
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            },
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SpeedSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _SpeedSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('0.3x'),
            Expanded(
              child: Slider(
                min: 0.3,
                max: 1.2,
                divisions: 9,
                value: value,
                label: '${value.toStringAsFixed(2)}x',
                onChanged: onChanged,
              ),
            ),
            const Text('1.2x'),
          ],
        ),
        Center(
          child: Text(
            '${value.toStringAsFixed(2)}x',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
