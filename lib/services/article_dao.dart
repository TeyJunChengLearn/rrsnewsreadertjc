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
      orderBy: 'pubDateMillis DESC',
    );
    return rows.map(FeedItem.fromMap).toList();
  }

  Future<void> upsertArticles(List<FeedItem> items) async {
    final db = await _dbService.database;
    final batch = db.batch();
    for (final item in items) {
      batch.insert(
        'articles',
        item.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateReadStatus(String id, bool isRead) async {
    final db = await _dbService.database;
    await db.update(
      'articles',
      {'isRead': isRead ? 1 : 0},
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
}
