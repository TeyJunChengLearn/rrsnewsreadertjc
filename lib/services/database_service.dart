// lib/services/database_service.dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/feed_source.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  DatabaseService._internal();
  factory DatabaseService() => _instance;

  static const _dbName = 'news_reader.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _openDb();
    return _db!;
  }

  Future<Database> _openDb() async {
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final String dbPath = p.join(appDocDir.path, _dbName);

    return await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1) feed_sources table
    await db.execute('''
      CREATE TABLE feed_sources (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        url TEXT NOT NULL UNIQUE
      )
    ''');

    // 2) articles table (what you already used)
    await db.execute('''
      CREATE TABLE articles (
        id TEXT PRIMARY KEY,
        sourceTitle TEXT,
        title TEXT,
        link TEXT,
        description TEXT,
        imageUrl TEXT,
        pubDateMillis INTEGER,
        isRead INTEGER NOT NULL DEFAULT 0,
        isBookmarked INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }
}
