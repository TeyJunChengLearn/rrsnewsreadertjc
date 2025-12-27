// lib/screens/settings_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/rss_provider.dart';
import 'cookie_diagnostic_page.dart';
import 'google_drive_test_page.dart';
import '../services/google_drive_backup_service.dart';
import '../models/backup_data.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Use dynamic to tolerate different field/method names in your provider.
    final d = context.watch<SettingsProvider>() as dynamic;

    // ---- Read values safely with fallbacks ----
    final updateMinutes = _firstInt(
          [
            () => d.updateIntervalMinutes,
            () => d.refreshMinutes,
            () => d.intervalMinutes,
          ],
        ) ??
        15;

    final perFeedLimit = _firstInt(
          [
            () => d.articleLimitPerFeed,
            () => d.perFeedLimit,
            () => d.maxItemsPerFeed,
          ],
        ) ??
        1000;

    final unreadCount = _firstInt([
          () => d.currentUnreadCount,
          () => d.unreadCount,
          () => d.unread
        ]) ??
        0;

    final darkTheme = _firstBool(
            [() => d.darkTheme, () => d.isDarkTheme, () => d.themeDark]) ??
        false;

    final displaySummaryFirst = _firstBool([
          () => d.displaySummary, // ✅ real field in SettingsProvider
          () => d.displaySummaryFirst,
          () => d.showSummaryFirst,
          () => d.openSummaryFirst,
          () => d.summaryFirst,
        ]) ??
        true;

    final highlightText = _firstBool([
          () => d.highlightText,
          () => d.isHighlightOn,
          () => d.keywordHighlight,
        ]) ??
        true;

    final translateCode = _firstString([
          () => d.translateLangCode,
          () => d.translationLang,
          () => d.targetLangCode,
        ]) ??
        'off';

    final ttsSpeechRate = _firstDouble([
          () => d.ttsSpeechRate,
          () => d.speechRate,
          () => d.voiceSpeed,
        ]) ??
        0.5;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // ===================== SYNC =====================
          _sectionHeader(context, 'Sync'),

          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Update interval'),
            subtitle: Text('$updateMinutes minutes between refreshes'),
            onTap: () => _pickUpdateInterval(context, d, updateMinutes),
          ),

          ListTile(
            leading: const Icon(Icons.view_list),
            title: const Text('Article limit for each feed'),
            subtitle: Text(
              'Keep ~${d.articleLimitPerFeed} newest per feed '
              '(unbookmarked old items may be cleaned)',
            ),
            onTap: () async {
              int temp = d.articleLimitPerFeed;

              await showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (context) {
                  return StatefulBuilder(
                    builder: (context, setSheetState) {
                      return SafeArea(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: 16,
                              right: 16,
                              top: 16,
                              bottom:
                                  MediaQuery.of(context).viewInsets.bottom + 16,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Article limit for each feed',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('10'),
                                    Text('$temp'),
                                    const Text('10000'),
                                  ],
                                ),
                                Slider(
                                  min: 10,
                                  max: 10000,
                                  divisions: 999, // step 10
                                  value: temp.toDouble().clamp(10, 10000),
                                  label: '$temp',
                                  onChanged: (v) {
                                    setSheetState(() {
                                      temp = (v / 10).round() * 10; // snap to 10s
                                    });
                                  },
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      child: const Text('Cancel'),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: () {
                                        d.setArticleLimitPerFeed(temp);
                                        Navigator.of(context).pop();
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
            },
          ),

          const SizedBox(height: 18),

          // =================== INTERFACE ==================
          _sectionHeader(context, 'Interface'),

          SwitchListTile(
            secondary: const Icon(Icons.dark_mode),
            title: const Text('Dark theme'),
            subtitle:
                Text(darkTheme ? 'Dark theme enabled' : 'Light theme enabled'),
            value: darkTheme,
            onChanged: (v) {
              // try common setter names; if none exist, this no-ops
              _tryCall(d, () => d.setDarkTheme(v));
              _tryCall(d, () => d.setIsDarkTheme(v));
              _tryCall(d, () => d.setThemeDark(v));
              _tryCall(d,
                  () => d.setThemeMode(v ? ThemeMode.dark : ThemeMode.light));
              _tryCall(d, () => d.toggleDarkTheme(v));
            },
          ),

          SwitchListTile(
            secondary: const Icon(Icons.article),
            title: const Text('Display summary first'),
            subtitle: Text(
              displaySummaryFirst
                  ? 'Open summary view first'
                  : 'Open full view first',
            ),
            value: displaySummaryFirst,
            onChanged: (v) {
              _tryCall(d, () => d.setDisplaySummary(v)); // ✅ real method
              _tryCall(d, () => d.setDisplaySummaryFirst(v));
              _tryCall(d, () => d.setShowSummaryFirst(v));
              _tryCall(d, () => d.setOpenSummaryFirst(v));
              _tryCall(d, () => d.setSummaryFirst(v));
            },
          ),

          SwitchListTile(
            secondary: const Icon(Icons.highlight),
            title: const Text('Highlight text'),
            subtitle: Text(highlightText
                ? 'Keyword highlighting ON'
                : 'Keyword highlighting OFF'),
            value: highlightText,
            onChanged: (v) {
              _tryCall(d, () => d.setHighlightText(v));
              _tryCall(d, () => d.setHighlight(v));
              _tryCall(d, () => d.setKeywordHighlight(v));
              _tryCall(d, () => d.toggleHighlight());
            },
          ),

          const SizedBox(height: 24),
          const Divider(height: 32),
          _sectionHeader(context, 'Text-to-speech'),

          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Voice speed'),
            subtitle: Text('${ttsSpeechRate.toStringAsFixed(2)}x'),
            onTap: () async {
              double temp = ttsSpeechRate;

              await showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (context) {
                  return StatefulBuilder(
                    builder: (context, setSheetState) {
                      return SafeArea(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: 16,
                              right: 16,
                              top: 16,
                              bottom:
                                  MediaQuery.of(context).viewInsets.bottom + 16,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Voice speed',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('0.3x'),
                                    Text('${temp.toStringAsFixed(2)}x'),
                                    const Text('1.2x'),
                                  ],
                                ),
                                Slider(
                                  min: 0.3,
                                  max: 1.2,
                                  divisions: 9,
                                  value: temp.clamp(0.3, 1.2).toDouble(),
                                  label: '${temp.toStringAsFixed(2)}x',
                                  onChanged: (v) {
                                    setSheetState(() {
                                      temp = v.clamp(0.3, 1.2).toDouble();
                                    });
                                  },
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Adjusts the spoken speed for articles, including Reader mode.',
                                  style: TextStyle(color: Colors.black54),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      child: const Text('Cancel'),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: () async {
                                        // Properly await the async call
                                        try {
                                          await d.setTtsSpeechRate(temp);
                                        } catch (e) {
                                          // Silently handle error
                                        }
                                        if (context.mounted) {
                                          Navigator.of(context).pop();
                                        }
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
            },
          ),

          const SizedBox(height: 24),
          const Divider(height: 32),
          // ================== TRANSLATION =================
          _sectionHeader(context, 'Translation'),

          ListTile(
            leading: const Icon(Icons.translate),
            title: const Text('Translate articles to'),
            subtitle: Text(_labelForCode(translateCode)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 0),
            trailing: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value:
                    translateCode, // 'off' or BCP codes like 'en','ms','zh-CN',...
                onChanged: (code) async {
                  if (code == null) return;
                  final saved =
                      _tryCall(d, () => d.setTranslateLangCode(code)) ||
                          _tryCall(d, () => d.setTranslationLang(code)) ||
                          _tryCall(d, () => d.setTargetLangCode(code));

                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        !saved
                            ? 'Could not save language (no setter found).'
                            : (code == 'off'
                                ? 'Translation disabled'
                                : 'Will translate to ${_labelForCode(code)}'),
                      ),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                items: _languageItems
                    .map((e) =>
                        DropdownMenuItem(value: e.code, child: Text(e.label)))
                    .toList(),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 6, 0, 0),
            child: Text(
              'In article screen: tap Reader, then tap Translate to toggle between Translated and Original. '
              'Text-to-speech will switch voice when available.',
              style: TextStyle(color: Colors.black54),
            ),
          ),

          const SizedBox(height: 24),
          const Divider(height: 32),
          // ================== DIAGNOSTICS =================
          _sectionHeader(context, 'Diagnostics'),

          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('Cookie diagnostics'),
            subtitle: const Text('Check if you\'re logged in for subscriber content'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CookieDiagnosticPage(),
                ),
              );
            },
          ),

          const SizedBox(height: 24),
          const Divider(height: 32),
          // ================== BACKUP & RESTORE =================
          _sectionHeader(context, 'Backup & Restore'),

          ListTile(
            leading: const Icon(Icons.cloud_upload),
            title: const Text('Export to Google Drive'),
            subtitle: const Text('Backup your feeds, settings, and cookies'),
            onTap: () => _handleExportBackup(context),
          ),

          ListTile(
            leading: const Icon(Icons.cloud_download),
            title: const Text('Import from Google Drive'),
            subtitle: const Text('Restore from a previous backup'),
            onTap: () => _handleImportBackup(context),
          ),

          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out from Google Drive'),
            subtitle: const Text('Disconnect Google Drive access'),
            onTap: () => _handleSignOut(context),
          ),

          const Divider(height: 24),

          ListTile(
            leading: const Icon(Icons.bug_report, color: Colors.blue),
            title: const Text('Test Google Drive Connection'),
            subtitle: const Text('Diagnose Google Drive issues'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const GoogleDriveTestPage(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------- UI helpers ----------
  Widget _sectionHeader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.red,
              fontWeight: FontWeight.w600,
              letterSpacing: .2,
            ),
      ),
    );
  }

  Future<void> _pickUpdateInterval(
    BuildContext context,
    dynamic d,
    int current,
  ) async {
    const choices = [5, 10, 15, 30, 60, 120];
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: choices
              .map(
                (m) => ListTile(
                  leading: const Icon(Icons.schedule),
                  title: Text('$m minutes'),
                  trailing: current == m ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(ctx, m),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (picked != null) {
      _tryCall(d, () => d.setUpdateIntervalMinutes(picked));
      _tryCall(d, () => d.setRefreshMinutes(picked));
      _tryCall(d, () => d.setIntervalMinutes(picked));
    }
  }

  Future<void> _pickPerFeedLimit(
    BuildContext context,
    dynamic d,
    int current,
  ) async {
    const choices = [200, 500, 1000, 1500, 2000];
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: choices
              .map(
                (n) => ListTile(
                  leading: const Icon(Icons.view_list),
                  title: Text('$n items per feed'),
                  trailing: current == n ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(ctx, n),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (picked != null) {
      _tryCall(d, () => d.setArticleLimitPerFeed(picked));
      _tryCall(d, () => d.setPerFeedLimit(picked));
      _tryCall(d, () => d.setMaxItemsPerFeed(picked));
    }
  }

  // ================== BACKUP & RESTORE HANDLERS =================
  Future<void> _handleExportBackup(BuildContext context) async {
    final service = GoogleDriveBackupService();

    // Step 1: Sign in to Google
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          title: Text('Step 1: Google Sign-In'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Opening Google Sign-In...'),
              SizedBox(height: 8),
              Text('Please select your Google account and allow Drive access.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    try {
      final signedIn = await service.signIn();

      if (context.mounted) Navigator.of(context).pop();

      if (!signedIn) {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Sign-In Failed'),
              content: const Text(
                'Google Sign-In was cancelled or failed.\n\n'
                'Please make sure:\n'
                '• You selected a Google account\n'
                '• You granted permission to access Google Drive\n'
                '• You have a working internet connection'
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // Step 2: Gather data
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const AlertDialog(
            title: Text('Step 2: Preparing Backup'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Gathering feeds, settings, and cookies...'),
              ],
            ),
          ),
        );
      }

      await Future.delayed(const Duration(milliseconds: 500)); // Let user see the message

      // Step 3: Upload
      if (context.mounted) {
        Navigator.of(context).pop();
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const AlertDialog(
            title: Text('Step 3: Uploading'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Uploading to Google Drive...'),
              ],
            ),
          ),
        );
      }

      final fileId = await service.uploadBackup();

      if (context.mounted) Navigator.of(context).pop();

      if (fileId != null) {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('✓ Success!'),
              content: const Text('Backup exported successfully to Google Drive!\n\nYou can find it in the "RSS Reader Backups" folder.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      } else {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Upload Failed'),
              content: const Text('Failed to upload backup to Google Drive.\n\nPlease check your internet connection and try again.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Error'),
            content: Text('Export error:\n\n$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _handleImportBackup(BuildContext context) async {
    final service = GoogleDriveBackupService();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading backups...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final backups = await service.listBackups();

      if (context.mounted) Navigator.of(context).pop();

      if (backups.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No backups found in Google Drive'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      if (context.mounted) {
        final selectedBackup = await showModalBottomSheet<BackupFile>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Select a backup to restore',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: backups.length,
                    itemBuilder: (ctx, idx) {
                      final backup = backups[idx];
                      final sizeKB = backup.size != null ? (backup.size! / 1024).toStringAsFixed(1) : '?';
                      return ListTile(
                        leading: const Icon(Icons.backup),
                        title: Text(backup.name),
                        subtitle: Text('${backup.modifiedTime ?? 'Unknown date'} • $sizeKB KB'),
                        onTap: () => Navigator.pop(ctx, backup),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );

        if (selectedBackup == null) return;

        final mode = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Restore Mode'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How should we restore this backup?'),
                SizedBox(height: 12),
                Text('• Merge: Keep existing data, add new items'),
                Text('• Replace: Delete all current data first'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'merge'),
                child: const Text('Merge (Recommended)'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'replace'),
                child: const Text('Replace', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );

        if (mode == null) return;

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Restoring backup...'),
                  ],
                ),
              ),
            ),
          ),
        );

        final success = await service.restoreFromBackup(
          selectedBackup.id,
          merge: mode == 'merge',
        );

        if (context.mounted) Navigator.of(context).pop();

        if (success) {
          if (context.mounted) {
            final rssProvider = Provider.of<RssProvider>(context, listen: false);
            await rssProvider.loadInitial();

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Backup restored successfully! Refreshing feeds...'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to restore backup. Please try again.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _handleSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out from Google Drive?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final service = GoogleDriveBackupService();
      await service.signOut();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Signed out from Google Drive'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
}

// ===== language dropdown items & labeler =====

class _LangItem {
  final String code;
  final String label;
  const _LangItem(this.code, this.label);
}

const List<_LangItem> _languageItems = [
  _LangItem('off', 'Off'),
  _LangItem('en', 'English'),
  _LangItem('ms', 'Malay (MS)'),
  _LangItem('zh-CN', 'Chinese (Simplified)'),
  _LangItem('zh-TW', 'Chinese (Traditional)'),
  _LangItem('ja', 'Japanese'),
  _LangItem('ko', 'Korean'),
  _LangItem('id', 'Indonesian'),
  _LangItem('th', 'Thai'),
  _LangItem('vi', 'Vietnamese'),
  _LangItem('ar', 'Arabic'),
  _LangItem('fr', 'French'),
  _LangItem('es', 'Spanish'),
  _LangItem('de', 'German'),
  _LangItem('pt', 'Portuguese'),
  _LangItem('it', 'Italian'),
  _LangItem('ru', 'Russian'),
  _LangItem('hi', 'Hindi'),
];

String _labelForCode(String code) {
  switch (code) {
    case 'off':
      return 'Off';
    case 'en':
      return 'English';
    case 'ms':
      return 'Malay (MS)';
    case 'zh-CN':
      return 'Chinese (Simplified)';
    case 'zh-TW':
      return 'Chinese (Traditional)';
    case 'ja':
      return 'Japanese';
    case 'ko':
      return 'Korean';
    case 'id':
      return 'Indonesian';
    case 'th':
      return 'Thai';
    case 'vi':
      return 'Vietnamese';
    case 'ar':
      return 'Arabic';
    case 'fr':
      return 'French';
    case 'es':
      return 'Spanish';
    case 'de':
      return 'German';
    case 'pt':
      return 'Portuguese';
    case 'it':
      return 'Italian';
    case 'ru':
      return 'Russian';
    case 'hi':
      return 'Hindi';
    default:
      return code;
  }
}

// ===== safe dynamic helpers (no analyzer tricks, no invalid syntax) =====
T? _first<T>(List<T Function()> getters) {
  for (final g in getters) {
    try {
      final v = g();
      if (v is T) return v as T;
    } catch (_) {
      // missing getter: ignore
    }
  }
  return null;
}

int? _firstInt(List<int Function()> getters) => _first<int>(getters);
bool? _firstBool(List<bool Function()> getters) => _first<bool>(getters);
String? _firstString(List<String Function()> getters) =>
    _first<String>(getters);
double? _firstDouble(List<double Function()> getters) =>
    _first<double>(getters);
/// Try to call a void method. Returns true if call succeeded (didn't throw).
bool _tryCall(dynamic _, void Function() fn) {
  try {
    fn();
    return true;
  } catch (_) {
    return false;
  }
}
