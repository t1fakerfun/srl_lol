import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('reflections.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';

    await db.execute('''
CREATE TABLE reflections (
  id $idType,
  topic $textType,
  content $textType,
  date $textType
)
''');
  }

  Future<void> insertReflection(Map<String, dynamic> reflection) async {
    final db = await instance.database;
    await db.insert('reflections', reflection);
  }

  Future<List<Map<String, dynamic>>> fetchReflections() async {
    final db = await instance.database;
    final orderBy = 'date DESC';
    return await db.query('reflections', orderBy: orderBy);
  }
}
