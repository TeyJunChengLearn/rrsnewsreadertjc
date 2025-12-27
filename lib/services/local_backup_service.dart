import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_rss_reader/models/backup_data.dart';
import 'package:flutter_rss_reader/models/feed_item.dart';
import 'package:flutter_rss_reader/models/feed_source.dart';
import 'package:flutter_rss_reader/services/feed_source_dao.dart';
import 'package:flutter_rss_reader/services/article_dao.dart';
import 'package:flutter_rss_reader/services/database_service.dart';
import 'package:flutter_rss_reader/services/cookie_bridge.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class LocalBackupService {
  final CookieBridge _cookieBridge = CookieBridge();

  /// Export backup to a JSON file
  /// Returns the file path if successful, null otherwise
  Future<String?> exportBackup() async {
    try {
      debugPrint('LocalBackupService: Starting export...');

      // Request storage permission
      if (Platform.isAndroid) {
        debugPrint('LocalBackupService: Checking storage permissions...');

        // Try to request manage storage permission for Android 11+
        var status = await Permission.manageExternalStorage.status;
        debugPrint('LocalBackupService: MANAGE_EXTERNAL_STORAGE status: $status');

        if (!status.isGranted) {
          debugPrint('LocalBackupService: Requesting MANAGE_EXTERNAL_STORAGE...');
          status = await Permission.manageExternalStorage.request();
          debugPrint('LocalBackupService: MANAGE_EXTERNAL_STORAGE after request: $status');
        }

        // If manage storage not granted, try regular storage permission
        if (!status.isGranted) {
          debugPrint('LocalBackupService: Requesting regular storage permission...');
          var storageStatus = await Permission.storage.status;
          debugPrint('LocalBackupService: Storage status: $storageStatus');

          if (!storageStatus.isGranted) {
            storageStatus = await Permission.storage.request();
            debugPrint('LocalBackupService: Storage after request: $storageStatus');
          }

          // Check if permission was denied (not just "not granted")
          if (storageStatus.isDenied || storageStatus.isPermanentlyDenied) {
            debugPrint('LocalBackupService: Storage permission denied or permanently denied');
            return 'PERMISSION_DENIED';
          }

          if (!storageStatus.isGranted) {
            debugPrint('LocalBackupService: Storage permission not granted');
            return 'PERMISSION_DENIED';
          }
        }

        debugPrint('LocalBackupService: Storage permission granted');
      }

      // Gather all data
      final backupData = await _gatherAllData();
      final jsonContent = json.encode(backupData.toJson());
      debugPrint('LocalBackupService: Backup JSON size: ${jsonContent.length} bytes');

      // Generate default filename with timestamp
      final timestamp = DateTime.now().toUtc();
      final defaultFilename = 'rss_reader_backup_${timestamp.toString().replaceAll(RegExp(r'[:\s.-]'), '').substring(0, 14)}.json';
      debugPrint('LocalBackupService: Default filename: $defaultFilename');

      // Let user choose where to save and what to name the file
      debugPrint('LocalBackupService: Opening file picker...');

      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save backup file',
        fileName: defaultFilename,
        bytes: utf8.encode(jsonContent),
      );

      debugPrint('LocalBackupService: File picker returned: $outputPath');

      if (outputPath == null) {
        debugPrint('LocalBackupService: User cancelled file save');
        return null;
      }

      debugPrint('LocalBackupService: ✓ Backup saved successfully to: $outputPath');
      return outputPath;
    } catch (e, stackTrace) {
      debugPrint('LocalBackupService: ✗ Export error: $e');
      debugPrint('LocalBackupService: Stack trace: $stackTrace');
      return null;
    }
  }

  Future<int> _getAndroidVersion() async {
    try {
      // This is a simplified version - in production you'd want to properly check Android API level
      return 33; // Assume modern Android for now
    } catch (e) {
      return 33;
    }
  }

  /// Import backup from HTTP URL
  /// Returns true if successful, false otherwise
  Future<bool> importBackupFromUrl(String url, {bool merge = true}) async {
    try {
      debugPrint('LocalBackupService: Starting import from URL: $url');

      // Download file from URL
      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) {
        debugPrint('LocalBackupService: Failed to download. Status: ${response.statusCode}');
        return false;
      }

      final jsonContent = utf8.decode(response.bodyBytes);
      debugPrint('LocalBackupService: Downloaded ${jsonContent.length} bytes');

      debugPrint('LocalBackupService: Parsing JSON...');
      final backupData = BackupData.fromJson(json.decode(jsonContent));

      if (backupData.version != '1.0') {
        debugPrint('LocalBackupService: Unsupported version: ${backupData.version}');
        return false;
      }

      debugPrint('LocalBackupService: Importing data (merge: $merge)...');
      await _importData(backupData.data, merge);

      debugPrint('LocalBackupService: ✓ Import from URL successful!');
      return true;
    } catch (e, stackTrace) {
      debugPrint('LocalBackupService: ✗ Import from URL error: $e');
      debugPrint('LocalBackupService: Stack trace: $stackTrace');
      return false;
    }
  }

  /// Import backup from a JSON file
  /// Returns true if successful, false otherwise
  Future<bool> importBackup({bool merge = true}) async {
    try {
      debugPrint('LocalBackupService: Starting import...');

      // Let user pick a file (allows browsing Google Drive, Downloads, etc.)
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
        withData: true, // Read file content directly (works with cloud files)
      );

      if (result == null || result.files.isEmpty) {
        debugPrint('LocalBackupService: File picker cancelled');
        return false;
      }

      final pickedFile = result.files.single;
      String jsonContent;

      // Try to read from bytes first (works with cloud files like Google Drive)
      if (pickedFile.bytes != null) {
        debugPrint('LocalBackupService: Reading from bytes (cloud file)');
        jsonContent = utf8.decode(pickedFile.bytes!);
      } else if (pickedFile.path != null) {
        debugPrint('LocalBackupService: Reading from path: ${pickedFile.path}');
        final file = File(pickedFile.path!);
        jsonContent = await file.readAsString();
      } else {
        debugPrint('LocalBackupService: No file data available');
        return false;
      }

      debugPrint('LocalBackupService: Parsing JSON...');
      final backupData = BackupData.fromJson(json.decode(jsonContent));

      if (backupData.version != '1.0') {
        debugPrint('LocalBackupService: Unsupported version: ${backupData.version}');
        return false;
      }

      debugPrint('LocalBackupService: Importing data (merge: $merge)...');
      await _importData(backupData.data, merge);

      debugPrint('LocalBackupService: ✓ Import successful!');
      return true;
    } catch (e, stackTrace) {
      debugPrint('LocalBackupService: ✗ Import error: $e');
      debugPrint('LocalBackupService: Stack trace: $stackTrace');
      return false;
    }
  }

  Future<BackupData> _gatherAllData() async {
    final dbService = DatabaseService();
    final feedSourceDao = FeedSourceDao(dbService);
    final articleDao = ArticleDao(dbService);
    final prefs = await SharedPreferences.getInstance();
    final packageInfo = await PackageInfo.fromPlatform();

    final feedSources = await feedSourceDao.getAllSources();
    final allArticles = await articleDao.getAllArticles();

    final articleMetadata = allArticles.map((article) {
      return ArticleMetadata(
        id: article.id,
        sourceTitle: article.sourceTitle,
        title: article.title,
        link: article.link,
        imageUrl: article.imageUrl,
        pubDateMillis: article.pubDate?.millisecondsSinceEpoch,
        isRead: article.isRead,
        isBookmarked: article.isBookmarked,
        readingPosition: article.readingPosition,
      );
    }).toList();

    final settings = <String, dynamic>{
      'darkTheme': prefs.getBool('darkTheme'),
      'displaySummary': prefs.getBool('displaySummary'),
      'highlightText': prefs.getBool('highlightText'),
      'updateIntervalMinutes': prefs.getInt('updateIntervalMinutes'),
      'articleLimitPerFeed': prefs.getInt('articleLimitPerFeed'),
      'ttsSpeechRate': prefs.getDouble('ttsSpeechRate'),
      'translateLangCode': prefs.getString('translate_lang_code'),
    };

    final domains = feedSources.map((fs) {
      try {
        final uri = Uri.parse(fs.url);
        return uri.host;
      } catch (_) {
        return fs.url;
      }
    }).toSet().toList();

    final cookies = await _cookieBridge.exportAllCookies(domains);

    return BackupData(
      version: '1.0',
      timestamp: DateTime.now().toUtc().toIso8601String(),
      appVersion: packageInfo.version,
      data: BackupContent(
        feedSources: feedSources,
        articles: articleMetadata,
        settings: settings,
        cookies: cookies,
      ),
    );
  }

  Future<void> _importData(BackupContent data, bool merge) async {
    final dbService = DatabaseService();
    final db = await dbService.database;
    final feedSourceDao = FeedSourceDao(dbService);
    final articleDao = ArticleDao(dbService);
    final prefs = await SharedPreferences.getInstance();

    if (!merge) {
      await db.delete('feed_sources');
      await db.delete('articles');
      await prefs.clear();
      await _cookieBridge.clearCookies();
    }

    for (final feedSource in data.feedSources) {
      await feedSourceDao.insertSource(feedSource);
    }

    final feedItems = data.articles.map((meta) {
      return FeedItem(
        id: meta.id,
        sourceTitle: meta.sourceTitle,
        title: meta.title,
        link: meta.link,
        description: null,
        imageUrl: meta.imageUrl,
        pubDate: meta.pubDateMillis != null
            ? DateTime.fromMillisecondsSinceEpoch(meta.pubDateMillis!)
            : null,
        mainText: null,
        isRead: meta.isRead,
        isBookmarked: meta.isBookmarked,
        readingPosition: meta.readingPosition,
      );
    }).toList();

    if (merge) {
      await articleDao.upsertArticles(feedItems);
    } else {
      for (final item in feedItems) {
        final map = item.toMap();
        await db.insert('articles', map);
      }
    }

    data.settings.forEach((key, value) {
      if (value == null) return;
      if (value is bool) {
        prefs.setBool(key, value);
      } else if (value is int) {
        prefs.setInt(key, value);
      } else if (value is double) {
        prefs.setDouble(key, value);
      } else if (value is String) {
        prefs.setString(key, value);
      }
    });

    await _cookieBridge.importCookies(data.cookies);
  }

  // ============ OPML EXPORT/IMPORT ============

  /// Export backup to OPML format (compatible with RSS readers)
  Future<String?> exportOpml() async {
    try {
      debugPrint('LocalBackupService: Starting OPML export...');

      // Request storage permission
      if (Platform.isAndroid) {
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();
        }
        if (!status.isGranted) {
          var storageStatus = await Permission.storage.status;
          if (!storageStatus.isGranted) {
            storageStatus = await Permission.storage.request();
          }
          if (storageStatus.isDenied || storageStatus.isPermanentlyDenied) {
            return 'PERMISSION_DENIED';
          }
        }
      }

      // Gather all data
      final dbService = DatabaseService();
      final feedSourceDao = FeedSourceDao(dbService);
      final articleDao = ArticleDao(dbService);
      final prefs = await SharedPreferences.getInstance();

      final feedSources = await feedSourceDao.getAllSources();
      final allArticles = await articleDao.getAllArticles();

      // Get cookies before building XML
      final domains = feedSources.map((fs) {
        try {
          final uri = Uri.parse(fs.url);
          return uri.host;
        } catch (_) {
          return fs.url;
        }
      }).toSet().toList();

      debugPrint('LocalBackupService: Exporting cookies for ${domains.length} domains');
      final cookies = await _cookieBridge.exportAllCookies(domains);
      debugPrint('LocalBackupService: Exported ${cookies.length} domains with cookies');

      // Log cookie details for verification
      cookies.forEach((domain, domainCookies) {
        debugPrint('  $domain: ${domainCookies.length} cookies');
      });

      // Build OPML XML
      final builder = XmlBuilder();
      builder.processing('xml', 'version="1.0" encoding="UTF-8"');
      builder.element('opml', nest: () {
        builder.attribute('version', '2.0');

        builder.element('head', nest: () {
          builder.element('title', nest: 'RSS Reader Backup');
          builder.element('dateCreated', nest: DateTime.now().toUtc().toIso8601String());
        });

        builder.element('body', nest: () {
          // Export settings
          builder.element('setting', nest: () {
            builder.attribute('darkTheme', prefs.getBool('darkTheme')?.toString() ?? 'false');
            builder.attribute('displaySummary', prefs.getBool('displaySummary')?.toString() ?? 'true');
            builder.attribute('highlightText', prefs.getBool('highlightText')?.toString() ?? 'false');
            builder.attribute('updateIntervalMinutes', prefs.getInt('updateIntervalMinutes')?.toString() ?? '30');
            builder.attribute('articleLimitPerFeed', prefs.getInt('articleLimitPerFeed')?.toString() ?? '1000');
            builder.attribute('ttsSpeechRate', prefs.getDouble('ttsSpeechRate')?.toString() ?? '0.5');
            builder.attribute('translateLangCode', prefs.getString('translate_lang_code') ?? '');
          });

          // Export cookies
          if (cookies.isNotEmpty) {
            builder.element('cookies', nest: () {
              builder.attribute('data', json.encode(cookies));
            });
          }

          // Export each feed with its articles
          for (final feed in feedSources) {
            final feedArticles = allArticles.where((a) => a.sourceTitle == feed.title).toList();

            builder.element('outline', nest: () {
              builder.attribute('type', 'rss');
              builder.attribute('text', feed.title);
              builder.attribute('title', feed.title);
              builder.attribute('xmlUrl', feed.url);
              if (feed.delayTime != null) {
                builder.attribute('delayTime', feed.delayTime.toString());
              }
              builder.attribute('requiresLogin', feed.requiresLogin.toString());

              // Export articles for this feed
              for (final article in feedArticles) {
                builder.element('entry', nest: () {
                  builder.attribute('id', article.id);
                  builder.attribute('title', article.title);
                  builder.attribute('link', article.link);
                  if (article.imageUrl != null) {
                    builder.attribute('imageUrl', article.imageUrl!);
                  }
                  if (article.pubDate != null) {
                    builder.attribute('pubDateMillis', article.pubDate!.millisecondsSinceEpoch.toString());
                  }
                  builder.attribute('isRead', article.isRead.toString());
                  builder.attribute('isBookmarked', article.isBookmarked.toString());
                  if (article.readingPosition != null) {
                    builder.attribute('readingPosition', article.readingPosition.toString());
                  }
                });
              }
            });
          }
        });
      });

      final xmlContent = builder.buildDocument().toXmlString(pretty: true);
      debugPrint('LocalBackupService: OPML size: ${xmlContent.length} bytes');

      // Generate filename
      final timestamp = DateTime.now().toUtc();
      final defaultFilename = 'rss_reader_backup_${timestamp.toString().replaceAll(RegExp(r'[:\s.-]'), '').substring(0, 14)}.opml.xml';

      // Save with file picker
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save OPML backup file',
        fileName: defaultFilename,
        bytes: utf8.encode(xmlContent),
      );

      if (outputPath == null) {
        debugPrint('LocalBackupService: User cancelled save');
        return null;
      }

      debugPrint('LocalBackupService: ✓ OPML backup saved to: $outputPath');
      return outputPath;
    } catch (e, stackTrace) {
      debugPrint('LocalBackupService: ✗ OPML export error: $e');
      debugPrint('LocalBackupService: Stack trace: $stackTrace');
      return null;
    }
  }

  /// Import backup from OPML file
  Future<bool> importOpml({bool merge = true}) async {
    try {
      debugPrint('LocalBackupService: Starting OPML import...');

      // Let user pick OPML file
      // Use FileType.any to allow files regardless of MIME type metadata
      // This allows importing both app-generated files and files from other sources
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        debugPrint('LocalBackupService: File picker cancelled');
        return false;
      }

      final pickedFile = result.files.single;
      String xmlContent;

      if (pickedFile.bytes != null) {
        xmlContent = utf8.decode(pickedFile.bytes!);
      } else if (pickedFile.path != null) {
        final file = File(pickedFile.path!);
        xmlContent = await file.readAsString();
      } else {
        debugPrint('LocalBackupService: No file data available');
        return false;
      }

      debugPrint('LocalBackupService: Parsing OPML XML...');
      final document = XmlDocument.parse(xmlContent);

      // Try to find body element - support both standard location and nested structures
      final bodyElements = document.findAllElements('body');
      if (bodyElements.isEmpty) {
        debugPrint('LocalBackupService: No <body> element found in OPML');
        return false;
      }
      final body = bodyElements.first;

      final dbService = DatabaseService();
      final db = await dbService.database;
      final feedSourceDao = FeedSourceDao(dbService);
      final articleDao = ArticleDao(dbService);
      final prefs = await SharedPreferences.getInstance();

      if (!merge) {
        await db.delete('feed_sources');
        await db.delete('articles');
        await prefs.clear();
        await _cookieBridge.clearCookies();
      }

      // Import settings (optional - only in our custom format)
      final settingElement = body.findElements('setting').firstOrNull;
      if (settingElement != null) {
        debugPrint('LocalBackupService: Importing settings...');
        try {
          final darkTheme = settingElement.getAttribute('darkTheme');
          if (darkTheme != null) prefs.setBool('darkTheme', darkTheme == 'true');

          final displaySummary = settingElement.getAttribute('displaySummary');
          if (displaySummary != null) prefs.setBool('displaySummary', displaySummary == 'true');

          final highlightText = settingElement.getAttribute('highlightText');
          if (highlightText != null) prefs.setBool('highlightText', highlightText == 'true');

          final updateInterval = settingElement.getAttribute('updateIntervalMinutes');
          if (updateInterval != null) prefs.setInt('updateIntervalMinutes', int.parse(updateInterval));

          final articleLimit = settingElement.getAttribute('articleLimitPerFeed');
          if (articleLimit != null) prefs.setInt('articleLimitPerFeed', int.parse(articleLimit));

          final speechRate = settingElement.getAttribute('ttsSpeechRate');
          if (speechRate != null) prefs.setDouble('ttsSpeechRate', double.parse(speechRate));

          final translateLang = settingElement.getAttribute('translateLangCode');
          if (translateLang != null && translateLang.isNotEmpty) {
            prefs.setString('translate_lang_code', translateLang);
          }
        } catch (e) {
          debugPrint('LocalBackupService: Error importing settings: $e');
        }
      }

      // Import cookies (optional - only in our custom format)
      final cookiesElement = body.findElements('cookies').firstOrNull;
      if (cookiesElement != null) {
        debugPrint('LocalBackupService: Importing cookies...');
        try {
          final cookiesData = cookiesElement.getAttribute('data');
          if (cookiesData != null) {
            final cookies = json.decode(cookiesData) as Map<String, dynamic>;
            final cookiesMap = cookies.map((key, value) =>
              MapEntry(key, Map<String, String>.from(value as Map))
            );

            debugPrint('LocalBackupService: Found cookies for ${cookiesMap.length} domains');

            // Log cookie details for verification
            cookiesMap.forEach((domain, domainCookies) {
              debugPrint('  $domain: ${domainCookies.length} cookies');
            });

            final success = await _cookieBridge.importCookies(cookiesMap);
            debugPrint('LocalBackupService: Cookie import ${success ? "succeeded" : "failed"}');
          }
        } catch (e) {
          debugPrint('LocalBackupService: Error importing cookies: $e');
        }
      } else {
        debugPrint('LocalBackupService: No cookies element found in OPML (standard OPML from other apps)');
      }

      // Import feeds - find ALL outline elements recursively (standard OPML support)
      final allOutlines = body.findAllElements('outline');
      int importedFeeds = 0;

      for (final outline in allOutlines) {
        // Check if this outline is a feed (has xmlUrl or type=rss)
        final url = outline.getAttribute('xmlUrl');
        final type = outline.getAttribute('type');

        // Skip if it's a folder/category (no xmlUrl and type is not rss)
        if (url == null && type != 'rss') continue;
        if (url == null) continue; // Must have xmlUrl to be a feed

        final title = outline.getAttribute('text')
          ?? outline.getAttribute('title')
          ?? outline.getAttribute('description')
          ?? 'Untitled Feed';

        // Optional attributes (our custom format)
        final delayTime = outline.getAttribute('delayTime');
        final requiresLogin = outline.getAttribute('requiresLogin') == 'true';

        // Create feed source
        final feedSource = FeedSource(
          title: title,
          url: url,
          delayTime: delayTime != null ? int.tryParse(delayTime) ?? 2000 : 2000,
          requiresLogin: requiresLogin,
        );

        debugPrint('LocalBackupService: Importing feed: $title');
        try {
          await feedSourceDao.insertSource(feedSource);
          importedFeeds++;
        } catch (e) {
          debugPrint('LocalBackupService: Error importing feed $title: $e');
          continue;
        }

        // Import articles for this feed (optional - only in our custom format)
        final entries = outline.findElements('entry');
        if (entries.isNotEmpty) {
          final feedItems = <FeedItem>[];

          for (final entry in entries) {
            try {
              final id = entry.getAttribute('id') ?? '${url}_${entry.getAttribute('link')}';
              final articleTitle = entry.getAttribute('title') ?? '';
              final link = entry.getAttribute('link') ?? '';
              final imageUrl = entry.getAttribute('imageUrl');
              final pubDateMillis = entry.getAttribute('pubDateMillis');
              final isRead = entry.getAttribute('isRead') == 'true' ? 1 : 0;
              final isBookmarked = entry.getAttribute('isBookmarked') == 'true';
              final readingPosition = entry.getAttribute('readingPosition');

              feedItems.add(FeedItem(
                id: id,
                sourceTitle: title,
                title: articleTitle,
                link: link,
                description: null,
                imageUrl: imageUrl,
                pubDate: pubDateMillis != null
                  ? DateTime.fromMillisecondsSinceEpoch(int.parse(pubDateMillis))
                  : null,
                mainText: null,
                isRead: isRead,
                isBookmarked: isBookmarked,
                readingPosition: readingPosition != null ? int.tryParse(readingPosition) : null,
              ));
            } catch (e) {
              debugPrint('LocalBackupService: Error parsing entry: $e');
            }
          }

          if (feedItems.isNotEmpty) {
            debugPrint('LocalBackupService: Importing ${feedItems.length} articles for $title');
            try {
              if (merge) {
                await articleDao.upsertArticles(feedItems);
              } else {
                for (final item in feedItems) {
                  await db.insert('articles', item.toMap());
                }
              }
            } catch (e) {
              debugPrint('LocalBackupService: Error importing articles: $e');
            }
          }
        }
      }

      debugPrint('LocalBackupService: Imported $importedFeeds feeds');
      if (importedFeeds == 0) {
        debugPrint('LocalBackupService: Warning - No feeds found in OPML file');
        return false;
      }

      debugPrint('LocalBackupService: ✓ OPML import successful!');
      return true;
    } catch (e, stackTrace) {
      debugPrint('LocalBackupService: ✗ OPML import error: $e');
      debugPrint('LocalBackupService: Stack trace: $stackTrace');
      return false;
    }
  }
}
