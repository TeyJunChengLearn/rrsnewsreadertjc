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
    final clamped = (isRead == 2)
        ? 2
        : isRead == 1
            ? 1
            : 0;
    await db.update(
      'articles',
      {'isRead': clamped},
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

  Future<FeedItem?> findById(String id) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'articles',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return FeedItem.fromMap(rows.first);
  }

  Future<void> updateContent(
      String id, String? mainText, String? imageUrl) async {
    final db = await _dbService.database;
    final updates = <String, Object?>{};
    if (mainText != null) updates['mainText'] = mainText;
    if (imageUrl != null) updates['imageUrl'] = imageUrl;
    if (updates.isEmpty) return;
    await db.update(
      'articles',
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

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

  Future<int> deleteBySourceTitle(String sourceTitle) async {
    final db = await _dbService.database;
    // Only delete unbookmarked articles; preserve bookmarked ones
    return db.delete(
      'articles',
      where: 'sourceTitle = ? AND COALESCE(isBookmarked, 0) = 0',
      whereArgs: [sourceTitle],
    );
  }

  Future<int> hideOlderThan(DateTime cutoff) async {
    final db = await _dbService.database;
    final cutoffMillis = cutoff.millisecondsSinceEpoch;
    return db.update(
      'articles',
      {'isRead': 2},
      where: 'COALESCE(pubDateMillis, 0) < ?',
      whereArgs: [cutoffMillis],
    );
  }

  Future<int> hideAllRead() async {
    final db = await _dbService.database;
    return db.update(
      'articles',
      {'isRead': 2},
      where: 'COALESCE(isRead, 0) = 1',
    );
  }

  Future<void> updateReadingPosition(String id, int? position) async {
    final db = await _dbService.database;
    await db.update(
      'articles',
      {'readingPosition': position},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> incrementEnrichmentAttempts(String id) async {
    final db = await _dbService.database;
    await db.rawUpdate(
      'UPDATE articles SET enrichmentAttempts = enrichmentAttempts + 1 WHERE id = ?',
      [id],
    );
  }

  /// Get all hidden/trashed articles (isRead == 2)
  Future<List<FeedItem>> getHiddenArticles() async {
    final db = await _dbService.database;
    final rows = await db.query(
      'articles',
      where: 'isRead = 2',
      orderBy: 'pubDateMillis DESC',
    );
    return rows.map(FeedItem.fromMap).toList();
  }

  /// Permanently delete an article by ID
  Future<int> permanentlyDeleteById(String id) async {
    final db = await _dbService.database;
    return db.delete(
      'articles',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Permanently delete multiple articles by IDs
  Future<int> permanentlyDeleteByIds(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final db = await _dbService.database;
    final placeholders = ids.map((_) => '?').join(', ');
    return db.delete(
      'articles',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  /// Permanently delete all hidden articles (isRead == 2)
  Future<int> permanentlyDeleteAllHidden() async {
    final db = await _dbService.database;
    return db.delete(
      'articles',
      where: 'isRead = 2',
    );
  }

  /// Restore an article from trash (set isRead back to 1)
  Future<void> restoreFromTrash(String id) async {
    final db = await _dbService.database;
    await db.update(
      'articles',
      {'isRead': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Restore multiple articles from trash
  Future<void> restoreMultipleFromTrash(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbService.database;
    final placeholders = ids.map((_) => '?').join(', ');
    await db.update(
      'articles',
      {'isRead': 1},
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }
}
