import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/activity_log.dart';
import '../models/survey.dart';
import 'api_service.dart';

class LocalDatabaseService {
  LocalDatabaseService();

  static const _storageKey = 'toposurvey.webDatabase.v1';
  Future<SharedPreferences>? _preferencesFuture;
  Map<String, dynamic>? _state;

  Future<SharedPreferences> _preferences() =>
      _preferencesFuture ??= SharedPreferences.getInstance();

  Future<Map<String, dynamic>> _load() async {
    if (_state != null) return _state!;
    final preferences = await _preferences();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null) {
      _state = {
        'surveys': <Map<String, Object?>>[],
        'projects': <Map<String, Object?>>[
          {'id': 1, 'name': 'Proyek Utama'},
        ],
        'activity_logs': <Map<String, Object?>>[],
        'next_survey_id': 1,
        'next_project_id': 2,
        'next_activity_id': 1,
      };
    } else {
      _state = jsonDecode(encoded) as Map<String, dynamic>;
    }
    return _state!;
  }

  Future<void> _save() async {
    final state = _state;
    if (state == null) return;
    await (await _preferences()).setString(_storageKey, jsonEncode(state));
  }

  Future<List<Survey>> loadSurveys() async {
    final state = await _load();
    final rows = (state['surveys'] as List).cast<Map<String, dynamic>>();
    return rows
        .map((row) => Survey.fromJson(row.cast<String, Object?>()))
        .toList()
      ..sort((a, b) => b.id.compareTo(a.id));
  }

  Future<Survey> loadSurvey(int id) async {
    final rows = await loadSurveys();
    return rows.firstWhere(
      (survey) => survey.id == id,
      orElse: () => throw const ApiException('Data survei tidak ditemukan.'),
    );
  }

  Future<Survey> saveSurvey(SurveyMeasurement measurement) async {
    if (!measurement.isValid) {
      throw const ApiException('Koordinat atau ketinggian belum valid.');
    }
    final state = await _load();
    final surveys = (state['surveys'] as List).cast<Map<String, dynamic>>();
    final projectId = measurement.projectId;
    final code = measurement.pointCode.trim();
    if (code.isNotEmpty &&
        surveys.any(
          (row) =>
              row['project_id'] == projectId &&
              (row['point_code'] as String).toLowerCase() == code.toLowerCase(),
        )) {
      throw const ApiException('Kode titik sudah dipakai pada proyek ini.');
    }
    final id = state['next_survey_id'] as int;
    state['next_survey_id'] = id + 1;
    final createdAt = DateTime.now().toUtc();
    final actualCode = code.isEmpty ? 'TP-$id' : code;
    final actualName = measurement.pointName.trim().isEmpty
        ? 'Titik $id'
        : measurement.pointName.trim();
    final row = <String, Object?>{
      'id': id,
      'latitude': measurement.latitude,
      'longitude': measurement.longitude,
      'elevation': measurement.elevation,
      'created_at': createdAt.toIso8601String(),
      'point_code': actualCode,
      'point_name': actualName,
      'notes': measurement.notes,
      'horizontal_accuracy': measurement.horizontalAccuracy,
      'vertical_accuracy': measurement.verticalAccuracy,
      'fix_time': (measurement.fixTime ?? createdAt).toUtc().toIso8601String(),
      'provider': measurement.provider,
      'source': measurement.source,
      'quality': measurement.quality,
      'project_id': projectId,
    };
    surveys.add(row);
    _log(
      state,
      'CREATE',
      'Titik $actualCode · $actualName tersimpan',
      id,
      projectId,
    );
    await _save();
    return Survey.fromJson(row);
  }

  Future<void> updateSurveyMetadata(
    int id, {
    required String pointCode,
    required String pointName,
    required String notes,
  }) async {
    if (pointCode.trim().isEmpty || pointName.trim().isEmpty) {
      throw const ApiException('Kode dan nama titik wajib diisi.');
    }
    final state = await _load();
    final surveys = (state['surveys'] as List).cast<Map<String, dynamic>>();
    final index = surveys.indexWhere((item) => item['id'] == id);
    if (index < 0) throw const ApiException('Data survei tidak ditemukan.');
    final row = surveys[index];
    if (surveys.any(
      (other) =>
          other['id'] != id &&
          other['project_id'] == row['project_id'] &&
          (other['point_code'] as String).toLowerCase() ==
              pointCode.trim().toLowerCase(),
    )) {
      throw const ApiException('Kode titik sudah dipakai pada proyek ini.');
    }
    row['point_code'] = pointCode.trim();
    row['point_name'] = pointName.trim();
    row['notes'] = notes.trim();
    _log(
      state,
      'EDIT',
      'Metadata titik ${row['point_code']} · ${row['point_name']} diperbarui',
      id,
      row['project_id'] as int,
    );
    await _save();
  }

  Future<void> deleteSurvey(int id) async {
    final state = await _load();
    final surveys = (state['surveys'] as List).cast<Map<String, dynamic>>();
    final index = surveys.indexWhere((item) => item['id'] == id);
    if (index < 0) throw const ApiException('Data survei tidak ditemukan.');
    final row = surveys[index];
    surveys.remove(row);
    _log(
      state,
      'DELETE',
      'Titik ${row['point_code']} · ${row['point_name']} dihapus',
      id,
      row['project_id'] as int,
    );
    await _save();
  }

  Future<List<SurveyProject>> loadProjects() async {
    final state = await _load();
    return (state['projects'] as List)
        .cast<Map<String, dynamic>>()
        .map(
          (row) =>
              SurveyProject(id: row['id'] as int, name: row['name'] as String),
        )
        .toList();
  }

  Future<int> saveProject(String name, {int? id}) async {
    final label = name.trim();
    if (label.isEmpty) throw const ApiException('Nama proyek wajib diisi.');
    final state = await _load();
    final projects = (state['projects'] as List).cast<Map<String, dynamic>>();
    if (projects.any(
      (row) =>
          row['id'] != id &&
          (row['name'] as String).toLowerCase() == label.toLowerCase(),
    )) {
      throw const ApiException('Nama proyek sudah digunakan.');
    }
    final projectId = id;
    if (projectId == null) {
      final newId = state['next_project_id'] as int;
      state['next_project_id'] = newId + 1;
      projects.add({'id': newId, 'name': label});
      _log(state, 'PROJECT', 'Proyek $label dibuat', null, newId);
      await _save();
      return newId;
    } else {
      final index = projects.indexWhere((item) => item['id'] == projectId);
      if (index < 0) throw const ApiException('Proyek tidak ditemukan.');
      final row = projects[index];
      row['name'] = label;
      _log(state, 'PROJECT', 'Proyek $label diperbarui', null, projectId);
    }
    await _save();
    return projectId;
  }

  Future<void> deleteProject(int id) async {
    final state = await _load();
    final projects = (state['projects'] as List).cast<Map<String, dynamic>>();
    if (projects.length <= 1) {
      throw const ApiException('Proyek terakhir tidak dapat dihapus.');
    }
    final index = projects.indexWhere((row) => row['id'] == id);
    if (index < 0) throw const ApiException('Proyek tidak ditemukan.');
    final project = projects[index];
    final surveys = (state['surveys'] as List).cast<Map<String, dynamic>>();
    if (surveys.any((row) => row['project_id'] == id)) {
      throw const ApiException(
        'Proyek masih memiliki titik. Hapus titiknya terlebih dahulu.',
      );
    }
    projects.remove(project);
    _log(state, 'PROJECT', 'Proyek ${project['name']} dihapus', null, id);
    await _save();
  }

  Future<List<ActivityLog>> loadActivityLogs({int? projectId}) async {
    final state = await _load();
    final rows = (state['activity_logs'] as List).cast<Map<String, dynamic>>();
    return rows
        .where((row) => projectId == null || row['project_id'] == projectId)
        .map((row) => ActivityLog.fromJson(row.cast<String, Object?>()))
        .toList()
      ..sort((a, b) => b.id.compareTo(a.id));
  }

  Future<void> logExport(int? projectId, int count) async {
    final state = await _load();
    _log(state, 'EXPORT', '$count titik diekspor ke GeoJSON', null, projectId);
    await _save();
  }

  void _log(
    Map<String, dynamic> state,
    String action,
    String description,
    int? surveyId,
    int? projectId,
  ) {
    final id = state['next_activity_id'] as int;
    state['next_activity_id'] = id + 1;
    (state['activity_logs'] as List).add({
      'id': id,
      'action': action,
      'description': description,
      'survey_id': surveyId,
      'project_id': projectId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  void close() {}
}
