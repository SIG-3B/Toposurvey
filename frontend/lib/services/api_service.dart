import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_config.dart';
import '../models/survey.dart';

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;
}

class ApiService {
  ApiService({
    String baseUrl = apiBaseUrl,
    this._client,
    this._timeout = const Duration(seconds: 10),
  }) : _baseUrl = Uri.tryParse(baseUrl);

  final Uri? _baseUrl;
  final http.Client? _client;
  final Duration _timeout;

  Future<void> checkHealth() async {
    final response = await _request('GET', '/api/health', 200);
    _decode(response, (json) {
      final health = json as Map<String, Object?>;
      if (health['status'] != 'ok' || health['database'] != 'ok') {
        throw const FormatException();
      }
    });
  }

  Future<List<Survey>> loadSurveys() async {
    final response = await _request('GET', '/api/surveys', 200);
    return _decode(
      response,
      (json) => (json as List<Object?>).map(_parseSurvey).toList(),
    );
  }

  Future<Survey> loadSurvey(int id) async {
    final response = await _request('GET', '/api/surveys/$id', 200);
    return _decode(response, (json) {
      final survey = _parseSurvey(json);
      if (survey.id != id) throw const FormatException();
      return survey;
    });
  }

  Future<Survey> saveSurvey(SurveyMeasurement measurement) async {
    if (!measurement.isValid) {
      throw const ApiException('Koordinat atau ketinggian belum valid.');
    }
    final response = await _request(
      'POST',
      '/api/surveys',
      201,
      body: measurement.toJson(),
    );
    return _decode(response, _parseSurvey);
  }

  Future<void> deleteSurvey(int id) async {
    await _request('DELETE', '/api/surveys/$id', 204);
  }

  Future<http.Response> _request(
    String method,
    String path,
    int expectedStatus, {
    Map<String, double>? body,
  }) async {
    final baseUrl = _baseUrl;
    if (baseUrl == null ||
        !baseUrl.hasAuthority ||
        baseUrl.host.isEmpty ||
        (baseUrl.scheme != 'http' && baseUrl.scheme != 'https')) {
      throw const ApiException('Alamat server tidak valid.');
    }
    final client = _client ?? http.Client();
    try {
      final request = http.Request(method, baseUrl.resolve(path))
        ..headers['Accept'] = 'application/json';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(_timeout);
      if (response.statusCode != expectedStatus) {
        throw ApiException(switch (response.statusCode) {
          404 => 'Data survei tidak ditemukan.',
          422 => 'Data survei tidak valid.',
          503 => 'Penyimpanan server sedang tidak tersedia. Coba lagi.',
          _ => 'Server tidak dapat memproses permintaan. Coba lagi.',
        });
      }
      return response;
    } on TimeoutException {
      throw ApiException(
        method == 'POST'
            ? 'Server terlalu lama merespons. Periksa Riwayat sebelum menyimpan lagi.'
            : 'Server terlalu lama merespons. Coba lagi.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Tidak dapat terhubung ke server. Periksa jaringan dan coba lagi.',
      );
    } finally {
      if (_client == null) client.close();
    }
  }

  T _decode<T>(http.Response response, T Function(Object?) read) {
    try {
      return read(jsonDecode(utf8.decode(response.bodyBytes)));
    } on FormatException {
      throw const ApiException('Balasan server tidak dapat dibaca.');
    } on TypeError {
      throw const ApiException('Balasan server tidak dapat dibaca.');
    }
  }

  Survey _parseSurvey(Object? json) =>
      Survey.fromJson(json as Map<String, Object?>);
}
