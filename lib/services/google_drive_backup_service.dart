import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_rss_reader/models/backup_data.dart';
import 'package:flutter_rss_reader/models/feed_item.dart';
import 'package:flutter_rss_reader/services/feed_source_dao.dart';
import 'package:flutter_rss_reader/services/article_dao.dart';
import 'package:flutter_rss_reader/services/database_service.dart';
import 'package:flutter_rss_reader/services/cookie_bridge.dart';
import 'package:package_info_plus/package_info_plus.dart';

class GoogleDriveBackupService {
  GoogleSignIn? _googleSignIn;
  drive.DriveApi? _driveApi;
  final CookieBridge _cookieBridge = CookieBridge();

  GoogleDriveBackupService() {
    _googleSignIn = GoogleSignIn(
      scopes: [
        drive.DriveApi.driveFileScope,
      ],
    );
  }

  bool get isSignedIn => _googleSignIn?.currentUser != null;

  Future<bool> signIn() async {
    try {
      debugPrint('GoogleDriveBackupService: Starting sign-in...');
      final account = await _googleSignIn!.signIn();
      if (account == null) {
        debugPrint('GoogleDriveBackupService: Sign-in cancelled by user');
        return false;
      }

      debugPrint('GoogleDriveBackupService: Getting auth headers...');
      final authHeaders = await account.authHeaders;
      final authenticateClient = GoogleAuthClient(authHeaders);
      _driveApi = drive.DriveApi(authenticateClient);

      debugPrint('GoogleDriveBackupService: Sign-in successful!');
      return true;
    } catch (e, stackTrace) {
      debugPrint('Google Sign-In error: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn?.signOut();
      _driveApi = null;
    } catch (e) {
      debugPrint('Google Sign-Out error: $e');
    }
  }

  Future<String?> uploadBackup() async {
    try {
      debugPrint('GoogleDriveBackupService: Starting uploadBackup...');

      if (!isSignedIn) {
        debugPrint('GoogleDriveBackupService: Not signed in, attempting sign-in...');
        final signedIn = await signIn();
        if (!signedIn) {
          debugPrint('GoogleDriveBackupService: Sign-in failed or cancelled');
          return null;
        }
      }

      debugPrint('GoogleDriveBackupService: Gathering data...');
      final backupData = await _gatherAllData();
      final jsonContent = json.encode(backupData.toJson());
      debugPrint('GoogleDriveBackupService: Backup JSON size: ${jsonContent.length} bytes');

      debugPrint('GoogleDriveBackupService: Getting/creating backup folder...');
      final folderId = await _getOrCreateBackupFolder();
      if (folderId == null) {
        debugPrint('GoogleDriveBackupService: Failed to get/create folder');
        return null;
      }
      debugPrint('GoogleDriveBackupService: Folder ID: $folderId');

      final timestamp = DateTime.now().toUtc();
      final filename = 'rss_reader_backup_${timestamp.toString().replaceAll(RegExp(r'[:\s.-]'), '').substring(0, 14)}.json';
      debugPrint('GoogleDriveBackupService: Uploading as: $filename');

      final driveFile = drive.File()
        ..name = filename
        ..parents = [folderId]
        ..mimeType = 'application/json';

      final media = drive.Media(
        Stream.value(utf8.encode(jsonContent)),
        jsonContent.length,
      );

      debugPrint('GoogleDriveBackupService: Creating file in Drive...');
      final uploadedFile = await _driveApi!.files.create(
        driveFile,
        uploadMedia: media,
      );

      debugPrint('GoogleDriveBackupService: ✓ Backup uploaded: ${uploadedFile.id} (${uploadedFile.name})');
      return uploadedFile.id;
    } catch (e, stackTrace) {
      debugPrint('GoogleDriveBackupService: ✗ Upload backup error: $e');
      debugPrint('GoogleDriveBackupService: Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<List<BackupFile>> listBackups() async {
    try {
      if (!isSignedIn) {
        final signedIn = await signIn();
        if (!signedIn) return [];
      }

      final folderId = await _getOrCreateBackupFolder();
      if (folderId == null) return [];

      final fileList = await _driveApi!.files.list(
        q: "'$folderId' in parents and trashed=false and mimeType='application/json'",
        orderBy: 'modifiedTime desc',
        spaces: 'drive',
        $fields: 'files(id, name, modifiedTime, size)',
      );

      if (fileList.files == null || fileList.files!.isEmpty) {
        return [];
      }

      return fileList.files!.map((file) {
        return BackupFile(
          id: file.id!,
          name: file.name ?? 'Unknown',
          modifiedTime: file.modifiedTime?.toIso8601String(),
          size: file.size != null ? int.tryParse(file.size!) : null,
        );
      }).toList();
    } catch (e) {
      debugPrint('List backups error: $e');
      return [];
    }
  }

  Future<bool> restoreFromBackup(String fileId, {bool merge = true}) async {
    try {
      if (!isSignedIn) {
        final signedIn = await signIn();
        if (!signedIn) return false;
      }

      final file = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final jsonBytes = <int>[];
      await for (var chunk in file.stream) {
        jsonBytes.addAll(chunk);
      }

      final jsonContent = utf8.decode(jsonBytes);
      final backupData = BackupData.fromJson(json.decode(jsonContent));

      if (backupData.version != '1.0') {
        debugPrint('Unsupported backup version: ${backupData.version}');
        return false;
      }

      await _importData(backupData.data, merge);
      return true;
    } catch (e) {
      debugPrint('Restore backup error: $e');
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

  Future<String?> _getOrCreateBackupFolder() async {
    try {
      final response = await _driveApi!.files.list(
        q: "name='RSS Reader Backups' and mimeType='application/vnd.google-apps.folder' and trashed=false",
        spaces: 'drive',
        $fields: 'files(id, name)',
      );

      if (response.files != null && response.files!.isNotEmpty) {
        return response.files!.first.id;
      }

      final folder = drive.File()
        ..name = 'RSS Reader Backups'
        ..mimeType = 'application/vnd.google-apps.folder';

      final createdFolder = await _driveApi!.files.create(folder);
      return createdFolder.id;
    } catch (e) {
      debugPrint('Get/create folder error: $e');
      return null;
    }
  }
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}
