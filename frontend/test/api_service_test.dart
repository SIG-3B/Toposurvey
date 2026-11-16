import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:toposurvey/models/survey.dart';
import 'package:toposurvey/services/api_service.dart';

const point = SurveyMeasurement(latitude: -6.9, longitude: 107.6, elevation: 0);

Matcher apiError(String message) => isA<ApiException>().having(
  (error) => error.message,
  'message',
  contains(message),
);

void main() {
  test('All five methods use the FastAPI contract', () async {
    final calls = <String>[];
    final survey = {
      ...point.toJson(),
      'id': 3,
      'created_at': '2026-11-16T03:00:00Z',
    };
    final client = MockClient((request) async {
      expect(request.url.origin, 'http://127.0.0.1:8000');
      final call = '${request.method} ${request.url.path}';
      calls.add(call);
      return switch (call) {
        'GET /api/health' => http.Response(
          '{"status":"ok","database":"ok"}',
          200,
        ),
        'POST /api/surveys' => () {
          expect(
            request.headers['content-type'],
            startsWith('application/json'),
          );
          expect(jsonDecode(request.body), point.toJson());
          return http.Response(jsonEncode(survey), 201);
        }(),
        'GET /api/surveys' => http.Response(jsonEncode([survey]), 200),
        'GET /api/surveys/3' => http.Response(jsonEncode(survey), 200),
        'DELETE /api/surveys/3' => http.Response('', 204),
        _ => throw StateError('Unexpected request'),
      };
    });
    addTearDown(client.close);
    final api = ApiService(baseUrl: 'http://127.0.0.1:8000/', client: client);
    await api.checkHealth();
    final saved = await api.saveSurvey(point);
    expect(saved.id, 3);
    expect(saved.createdAt, DateTime.utc(2026, 11, 16, 3));
    expect((await api.loadSurveys()).single.measurement.elevation, 0);
    expect((await api.loadSurvey(3)).id, 3);
    await api.deleteSurvey(3);
    expect(calls, [
      'GET /api/health',
      'POST /api/surveys',
      'GET /api/surveys',
      'GET /api/surveys/3',
      'DELETE /api/surveys/3',
    ]);
  });

  test(
    'Reject invalid GPS and handle malformed or unavailable responses',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return switch (request.url.path) {
          '/api/health' => throw http.ClientException('connection refused'),
          '/api/surveys' => http.Response('[{"id":3}]', 200),
          _ => http.Response('', 404),
        };
      });
      addTearDown(client.close);
      final api = ApiService(client: client);
      for (final elevation in [double.nan, double.infinity]) {
        await expectLater(
          api.saveSurvey(
            SurveyMeasurement(latitude: 0, longitude: 0, elevation: elevation),
          ),
          throwsA(apiError('belum valid')),
        );
      }
      expect(requests, 0);
      await expectLater(
        api.checkHealth(),
        throwsA(apiError('Tidak dapat terhubung')),
      );
      await expectLater(
        api.loadSurveys(),
        throwsA(apiError('tidak dapat dibaca')),
      );
      await expectLater(
        api.deleteSurvey(3),
        throwsA(apiError('tidak ditemukan')),
      );
    },
  );

  test('Timed-out POST warns to check history before retrying', () async {
    final response = Completer<http.Response>();
    final client = MockClient((_) => response.future);
    addTearDown(client.close);
    final api = ApiService(
      client: client,
      timeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      api.saveSurvey(point),
      throwsA(apiError('Periksa Riwayat')),
    );
    response.complete(http.Response('offline', 503));
  });
}
