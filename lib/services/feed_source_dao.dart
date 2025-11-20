// lib/services/feed_source_dao.dart
import 'package:sqflite/sqflite.dart';

import '../models/feed_source.dart';
import 'database_service.dart';

class FeedSourceDao {
  final DatabaseService _dbService;
  FeedSourceDao(this._dbService);

  Future<List<FeedSource>> getAllSources() async {
    final Database db = await _dbService.database;
    final rows = await db.query(
      'feed_sources',
      orderBy: 'title ASC',
    );
    return rows.map((e) => FeedSource.fromMap(e)).toList();
  }

  Future<FeedSource> insertSource(FeedSource source) async {
    final Database db = await _dbService.database;
    final id = await db.insert('feed_sources', source.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return source.copyWith(id: id);
  }

  Future<void> deleteSource(int id) async {
    final Database db = await _dbService.database;
    await db.delete(
      'feed_sources',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Optional: find by URL (to avoid duplicates in UI)
  Future<FeedSource?> findByUrl(String url) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'feed_sources',
      where: 'url = ?',
      whereArgs: [url],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return FeedSource.fromMap(rows.first);
  }

  Future<int> deleteDefaultSourcesIfPresent() async {
    final db = await _dbService.database;

    // Check if `isDefault` column exists on feed_sources
    final cols = await db.rawQuery("PRAGMA table_info('feed_sources')");
    final hasIsDefault =
        cols.any((c) => (c['name'] as String?)?.toLowerCase() == 'isdefault');

    if (!hasIsDefault) {
      // Nothing to delete by flag; return 0 changes.
      return 0;
    }

    return await db.delete(
      'feed_sources',
      where: 'COALESCE(isDefault, 0) = 1',
    );
  }

  /// Delete a specific source by its URL (useful if your seed inserted a known URL).
  Future<int> deleteSourceByUrl(String url) async {
    final db = await _dbService.database;
    return await db.delete(
      'feed_sources',
      where: 'url = ?',
      whereArgs: [url],
    );
  }
}
