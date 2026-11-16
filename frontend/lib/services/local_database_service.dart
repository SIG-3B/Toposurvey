import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/survey.dart';
import 'api_service.dart';

class LocalDatabaseService {
  LocalDatabaseService({Future<Database> Function()? openDatabase})
    : _openDatabase = openDatabase ?? _defaultOpenDatabase;

  final Future<Database> Function() _openDatabase;
  Future<Database>? _databaseFuture;
  Database? _database;

  static Future<Database> _defaultOpenDatabase() async {
    final directory = await getApplicationDocumentsDirectory();
    final dbPath = p.join(directory.path, 'toposurvey.sqlite3');
    return sqlite3.open(dbPath);
  }

  Future<Database> _ensureDatabase() {
    return _databaseFuture ??= _initDatabase();
  }

  Future<Database> _initDatabase() async {
    try {
      final db = await _openDatabase();
      db.execute('''
        CREATE TABLE IF NOT EXISTS surveys (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          elevation REAL NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      _database = db;
      return db;
    } catch (_) {
      _databaseFuture = null;
      throw const ApiException(
        'Penyimpanan lokal sedang tidak tersedia. Coba lagi.',
      );
    }
  }

  Future<List<Survey>> loadSurveys() async {
    final db = await _ensureDatabase();
    try {
      final rows = db.select(
        'SELECT id, latitude, longitude, elevation, created_at '
        'FROM surveys ORDER BY id DESC',
      );
      return rows.map(_rowToSurvey).toList();
    } on SqliteException {
      throw const ApiException(
        'Penyimpanan lokal sedang tidak tersedia. Coba lagi.',
      );
    }
  }

  Future<Survey> loadSurvey(int id) async {
    final db = await _ensureDatabase();
    try {
      final rows = db.select(
        'SELECT id, latitude, longitude, elevation, created_at '
        'FROM surveys WHERE id = ?',
        [id],
      );
      if (rows.isEmpty) {
        throw const ApiException('Data survei tidak ditemukan.');
      }
      return _rowToSurvey(rows.first);
    } on SqliteException {
      throw const ApiException(
        'Penyimpanan lokal sedang tidak tersedia. Coba lagi.',
      );
    }
  }

  Future<Survey> saveSurvey(SurveyMeasurement measurement) async {
    if (!measurement.isValid) {
      throw const ApiException('Koordinat atau ketinggian belum valid.');
    }
    final db = await _ensureDatabase();
    final createdAt = DateTime.now().toUtc();
    try {
      db.execute(
        'INSERT INTO surveys (latitude, longitude, elevation, created_at) '
        'VALUES (?, ?, ?, ?)',
        [
          measurement.latitude,
          measurement.longitude,
          measurement.elevation,
          createdAt.toIso8601String(),
        ],
      );
      return Survey(
        id: db.lastInsertRowId,
        measurement: measurement,
        createdAt: createdAt,
      );
    } on SqliteException {
      throw const ApiException(
        'Penyimpanan lokal sedang tidak tersedia. Coba lagi.',
      );
    }
  }

  Future<void> deleteSurvey(int id) async {
    final db = await _ensureDatabase();
    try {
      db.execute('DELETE FROM surveys WHERE id = ?', [id]);
      if (db.updatedRows == 0) {
        throw const ApiException('Data survei tidak ditemukan.');
      }
    } on SqliteException {
      throw const ApiException(
        'Penyimpanan lokal sedang tidak tersedia. Coba lagi.',
      );
    }
  }

  void close() {
    _database?.close();
    _database = null;
    _databaseFuture = null;
  }

  Survey _rowToSurvey(Row row) => Survey.fromJson({
    'id': row['id'] as int,
    'latitude': row['latitude'] as num,
    'longitude': row['longitude'] as num,
    'elevation': row['elevation'] as num,
    'created_at': row['created_at'] as String,
  });
}
