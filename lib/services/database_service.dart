import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  DatabaseService._internal();
  factory DatabaseService() => _instance;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _openDb();
    return _db!;
  }

  Future<Database> _openDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'rss_reader.db');

    return openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE articles (
            id TEXT PRIMARY KEY,
            sourceTitle TEXT,
            title TEXT,
            link TEXT,
            description TEXT,
            imageUrl TEXT,
            pubDateMillis INTEGER,
            isRead INTEGER,
            isBookmarked INTEGER
          )
        ''');
      },
    );
  }
}
