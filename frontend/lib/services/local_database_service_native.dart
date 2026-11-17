import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../models/survey.dart';
import '../models/activity_log.dart';
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
      final columns = db
          .select('PRAGMA table_info(surveys)')
          .map((r) => r['name'] as String)
          .toSet();
      const additions = <String, String>{
        'point_code': "TEXT NOT NULL DEFAULT ''",
        'point_name': "TEXT NOT NULL DEFAULT ''",
        'notes': "TEXT NOT NULL DEFAULT ''",
        'horizontal_accuracy': 'REAL',
        'vertical_accuracy': 'REAL',
        'fix_time': "TEXT NOT NULL DEFAULT ''",
        'provider': "TEXT NOT NULL DEFAULT 'GPS'",
        'source': "TEXT NOT NULL DEFAULT 'DEVICE'",
        'quality': "TEXT NOT NULL DEFAULT 'ACCEPTED'",
        'project_id': 'INTEGER NOT NULL DEFAULT 1',
      };
      for (final entry in additions.entries) {
        if (!columns.contains(entry.key)) {
          db.execute(
            'ALTER TABLE surveys ADD COLUMN ${entry.key} ${entry.value}',
          );
        }
      }
      db.execute('''CREATE TABLE IF NOT EXISTS projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )''');
      db.execute(
        "INSERT OR IGNORE INTO projects (id, name) VALUES (1, 'Proyek Utama')",
      );
      db.execute('''CREATE TABLE IF NOT EXISTS activity_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        description TEXT NOT NULL,
        survey_id INTEGER,
        project_id INTEGER,
        created_at TEXT NOT NULL
      )''');
      db.execute(
        "UPDATE surveys SET point_code = 'TP-' || id WHERE point_code = ''",
      );
      db.execute(
        "UPDATE surveys SET point_name = 'Titik ' || id WHERE point_name = ''",
      );
      db.execute(
        "UPDATE surveys SET fix_time = created_at WHERE fix_time = ''",
      );
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
        'SELECT * '
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
        'SELECT * '
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
      if (measurement.pointCode.trim().isNotEmpty &&
          db.select(
            'SELECT 1 FROM surveys WHERE project_id = ? AND lower(point_code) = lower(?)',
            [measurement.projectId, measurement.pointCode.trim()],
          ).isNotEmpty) {
        throw const ApiException('Kode titik sudah dipakai pada proyek ini.');
      }
      db.execute(
        'INSERT INTO surveys (latitude, longitude, elevation, created_at, point_code, point_name, notes, horizontal_accuracy, vertical_accuracy, fix_time, provider, source, quality, project_id) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          measurement.latitude,
          measurement.longitude,
          measurement.elevation,
          createdAt.toIso8601String(),
          measurement.pointCode,
          measurement.pointName,
          measurement.notes,
          measurement.horizontalAccuracy,
          measurement.verticalAccuracy,
          (measurement.fixTime ?? createdAt).toUtc().toIso8601String(),
          measurement.provider,
          measurement.source,
          measurement.quality,
          measurement.projectId,
        ],
      );
      final id = db.lastInsertRowId;
      final code = measurement.pointCode.isEmpty
          ? 'TP-$id'
          : measurement.pointCode;
      final name = measurement.pointName.isEmpty
          ? 'Titik $id'
          : measurement.pointName;
      db.execute(
        'UPDATE surveys SET point_code = ?, point_name = ? WHERE id = ?',
        [code, name, id],
      );
      _log(
        db,
        'CREATE',
        'Titik $code · $name tersimpan',
        id,
        measurement.projectId,
      );
      return Survey(
        id: id,
        measurement: measurement,
        createdAt: createdAt,
        pointCode: code,
        pointName: name,
        notes: measurement.notes,
        horizontalAccuracy: measurement.horizontalAccuracy,
        verticalAccuracy: measurement.verticalAccuracy,
        fixTime: measurement.fixTime ?? createdAt,
        provider: measurement.provider,
        source: measurement.source,
        quality: measurement.quality,
        projectId: measurement.projectId,
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
      final survey = loadSurvey(id);
      final current = await survey;
      db.execute('DELETE FROM surveys WHERE id = ?', [id]);
      if (db.updatedRows == 0) {
        throw const ApiException('Data survei tidak ditemukan.');
      }
      _log(
        db,
        'DELETE',
        'Titik ${current.pointCode} · ${current.pointName} dihapus',
        id,
        current.projectId,
      );
    } on SqliteException {
      throw const ApiException(
        'Penyimpanan lokal sedang tidak tersedia. Coba lagi.',
      );
    }
  }

  Future<void> updateSurveyMetadata(
    int id, {
    required String pointCode,
    required String pointName,
    required String notes,
  }) async {
    final db = await _ensureDatabase();
    if (pointCode.trim().isEmpty || pointName.trim().isEmpty) {
      throw const ApiException('Kode dan nama titik wajib diisi.');
    }
    final survey = await loadSurvey(id);
    try {
      if (db.select(
        'SELECT 1 FROM surveys WHERE project_id = ? AND id <> ? AND lower(point_code) = lower(?)',
        [survey.projectId, id, pointCode.trim()],
      ).isNotEmpty) {
        throw const ApiException('Kode titik sudah dipakai pada proyek ini.');
      }
      db.execute(
        'UPDATE surveys SET point_code = ?, point_name = ?, notes = ? WHERE id = ?',
        [pointCode.trim(), pointName.trim(), notes.trim(), id],
      );
      _log(
        db,
        'EDIT',
        'Metadata titik ${pointCode.trim()} · ${pointName.trim()} diperbarui',
        id,
        survey.projectId,
      );
    } on SqliteException {
      throw const ApiException(
        'Metadata tidak dapat disimpan. Pastikan kode titik unik.',
      );
    }
  }

  Future<List<SurveyProject>> loadProjects() async {
    final db = await _ensureDatabase();
    return db
        .select('SELECT id, name FROM projects ORDER BY id')
        .map(
          (r) => SurveyProject(id: r['id'] as int, name: r['name'] as String),
        )
        .toList();
  }

  Future<int> saveProject(String name, {int? id}) async {
    final db = await _ensureDatabase();
    if (name.trim().isEmpty) {
      throw const ApiException('Nama proyek wajib diisi.');
    }
    if (id == null) {
      db.execute('INSERT INTO projects (name) VALUES (?)', [name.trim()]);
      final newId = db.lastInsertRowId;
      _log(db, 'PROJECT', 'Proyek ${name.trim()} dibuat', null, newId);
      return newId;
    }
    db.execute('UPDATE projects SET name = ? WHERE id = ?', [name.trim(), id]);
    _log(db, 'PROJECT', 'Proyek ${name.trim()} diperbarui', null, id);
    return id;
  }

  Future<void> deleteProject(int id) async {
    final db = await _ensureDatabase();
    if ((db.select('SELECT COUNT(*) AS count FROM projects').first['count']
            as int) <=
        1) {
      throw const ApiException('Proyek terakhir tidak dapat dihapus.');
    }
    final project = db.select('SELECT name FROM projects WHERE id = ?', [id]);
    if (project.isEmpty) throw const ApiException('Proyek tidak ditemukan.');
    final points =
        db.select(
              'SELECT COUNT(*) AS count FROM surveys WHERE project_id = ?',
              [id],
            ).first['count']
            as int;
    if (points > 0) {
      throw const ApiException(
        'Proyek masih memiliki titik. Hapus titiknya terlebih dahulu.',
      );
    }
    db.execute('DELETE FROM projects WHERE id = ?', [id]);
    _log(db, 'PROJECT', 'Proyek ${project.first['name']} dihapus', null, id);
  }

  Future<List<ActivityLog>> loadActivityLogs({int? projectId}) async {
    final db = await _ensureDatabase();
    final rows = projectId == null
        ? db.select('SELECT * FROM activity_logs ORDER BY id DESC')
        : db.select(
            'SELECT * FROM activity_logs WHERE project_id = ? ORDER BY id DESC',
            [projectId],
          );
    return rows
        .map(
          (r) => ActivityLog.fromJson({
            for (final k in [
              'id',
              'action',
              'description',
              'survey_id',
              'project_id',
              'created_at',
            ])
              k: r[k],
          }),
        )
        .toList();
  }

  Future<void> logExport(int? projectId, int count) async {
    final db = await _ensureDatabase();
    _log(db, 'EXPORT', '$count titik diekspor ke GeoJSON', null, projectId);
  }

  void _log(
    Database db,
    String action,
    String description,
    int? surveyId,
    int? projectId,
  ) {
    db.execute(
      'INSERT INTO activity_logs (action, description, survey_id, project_id, created_at) VALUES (?, ?, ?, ?, ?)',
      [
        action,
        description,
        surveyId,
        projectId,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
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
    'point_code': row['point_code'],
    'point_name': row['point_name'],
    'notes': row['notes'],
    'horizontal_accuracy': row['horizontal_accuracy'],
    'vertical_accuracy': row['vertical_accuracy'],
    'fix_time': row['fix_time'],
    'provider': row['provider'],
    'source': row['source'],
    'quality': row['quality'],
    'project_id': row['project_id'],
  });
}
