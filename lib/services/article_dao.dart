import 'package:sqflite/sqflite.dart';
import '../models/feed_item.dart';
import 'database_service.dart';

class ArticleDao {
  final DatabaseService _dbService;
  ArticleDao(this._dbService);

Future<List<FeedItem>> getAllArticles() async {
  final db = await _dbService.database;
  final rows = await db.query(
    'articles',
    // NOTE: we do NOT filter isRead here; UI will decide what to hide/show.
    orderBy: 'pubDateMillis DESC',
  );
  return rows.map(FeedItem.fromMap).toList();
}


  Future<void> upsertArticles(List<FeedItem> items) async {
    final db = await _dbService.database;

    await db.transaction((txn) async {
      final batch = txn.batch();

      for (final it in items) {
        final map = it.toMap();

        // 1) INSERT if missing, default flags to unread/unbookmarked
        final insertMap = Map<String, Object?>.from(map)
          ..['isRead'] = 0
          ..['isBookmarked'] = 0;
        batch.insert(
          'articles',
          insertMap,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        // 2) UPDATE existing rows but DO NOT touch flags
        final updateMap = Map<String, Object?>.from(map)
          ..remove('isRead')
          ..remove('isBookmarked');
        batch.update(
          'articles',
          updateMap,
          where: 'id = ?',
          whereArgs: [it.id],
        );
      }

      await batch.commit(noResult: true);
    });
  }

  Future<void> updateReadStatus(String id, int isRead) async {
    final db = await _dbService.database;
    await db.update(
      'articles',
      {'isRead': isRead == 1 ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateBookmark(String id, bool isBookmarked) async {
    final db = await _dbService.database;
    await db.update(
      'articles',
      {'isBookmarked': isBookmarked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // In lib/services/article_dao.dart
// Replace your existing method with this version.
// Keeps only the newest `keepCount` UNREAD & UNBOOKMARKED articles globally.
// Bookmarked items are never deleted. Read items are ignored.
// Per-feed cap: keep only newest `keepCount` UNBOOKMARKED for a given sourceTitle.
// Bookmarked rows are preserved. Sorted by pubDateMillis desc then id.
// Per-feed cap: keep only newest `keepCount` UNBOOKMARKED for a given sourceTitle.
// Bookmarked rows are preserved. Sort by pubDateMillis DESC, then id DESC.
// Uses OFFSET trick so we delete "everything after the top N".
  Future<int> enforceUnbookmarkedLimitForSourceTitle(
    String sourceTitle,
    int keepCount,
  ) async {
    final db = await _dbService.database;

    // Delete all rows beyond the newest `keepCount`
    // NOTE: LIMIT -1 OFFSET ? means "skip the first N rows, delete the rest"
    final deleted = await db.rawDelete('''
    DELETE FROM articles
    WHERE COALESCE(isBookmarked, 0) = 0
      AND sourceTitle = ?
      AND id IN (
        SELECT id FROM articles
        WHERE COALESCE(isBookmarked, 0) = 0
          AND sourceTitle = ?
        ORDER BY 
          CASE WHEN pubDateMillis IS NULL THEN 0 ELSE pubDateMillis END DESC,
          id DESC
        LIMIT -1 OFFSET ?
      )
  ''', [sourceTitle, sourceTitle, keepCount]);

    return deleted;
  }

  Future<int> hideAllRead() async {
    final db = await _dbService.database;
    return db.update(
      'articles',
      {'isRead': 2},
      where: 'COALESCE(isRead, 0) = 1',
    );
  }
}
