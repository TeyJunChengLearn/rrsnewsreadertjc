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
  static const _dbVersion = 5;

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
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1) feed_sources table
    await db.execute('''
      CREATE TABLE feed_sources (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        url TEXT NOT NULL UNIQUE,
        delayTime INTEGER NOT NULL DEFAULT 2000,
        requiresLogin INTEGER NOT NULL DEFAULT 0
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
        mainText TEXT,
        isRead INTEGER NOT NULL DEFAULT 0,
        isBookmarked INTEGER NOT NULL DEFAULT 0,
        readingPosition INTEGER,
        enrichmentAttempts INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }
   Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE articles ADD COLUMN mainText TEXT');
    }
    if (oldVersion < 3) {
      // Add WebView extraction support fields
      await db.execute('ALTER TABLE feed_sources ADD COLUMN delayTime INTEGER NOT NULL DEFAULT 2000');
      await db.execute('ALTER TABLE feed_sources ADD COLUMN requiresLogin INTEGER NOT NULL DEFAULT 0');
    }
    if (oldVersion < 4) {
      // Add reading position tracking
      await db.execute('ALTER TABLE articles ADD COLUMN readingPosition INTEGER');
    }
    if (oldVersion < 5) {
      // Add enrichment failure tracking
      await db.execute('ALTER TABLE articles ADD COLUMN enrichmentAttempts INTEGER NOT NULL DEFAULT 0');
    }
  }
}
