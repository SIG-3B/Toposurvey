import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:toposurvey/main.dart';
import 'package:toposurvey/models/survey.dart';
import 'package:toposurvey/screens/history_screen.dart';
import 'package:toposurvey/services/api_service.dart';
import 'package:toposurvey/services/geojson_exporter.dart';
import 'package:toposurvey/services/local_database_service.dart';
import 'package:toposurvey/services/location_service.dart';

class _TestLocation extends LocationService {
  final positions = StreamController<Position>.broadcast();

  @override
  Future<LocationAccess> checkAccess({bool requestPermission = false}) async =>
      LocationAccess.ready;

  @override
  Stream<Position> watchPositions() => positions.stream;
}

Position _position({
  double latitude = -6.9,
  double longitude = 107.6,
  double altitude = -4.5,
}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime.utc(2026, 11, 16, 3),
  accuracy: 5,
  altitude: altitude,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
  hasAltitude: true,
  hasAccuracy: true,
);

Matcher _apiError(String message) => isA<ApiException>().having(
  (error) => error.message,
  'message',
  contains(message),
);

void main() {
  test('LocalDatabaseService supports full offline CRUD lifecycle', () async {
    final db = LocalDatabaseService(
      openDatabase: () async => sqlite3.openInMemory(),
    );
    addTearDown(db.close);

    expect(await db.loadSurveys(), isEmpty);

    for (final invalid in [
      const SurveyMeasurement(latitude: 95, longitude: 0, elevation: 10),
      const SurveyMeasurement(latitude: 0, longitude: 185, elevation: 10),
      const SurveyMeasurement(
        latitude: 0,
        longitude: 0,
        elevation: double.infinity,
      ),
    ]) {
      await expectLater(
        db.saveSurvey(invalid),
        throwsA(_apiError('belum valid')),
      );
    }

    final first = await db.saveSurvey(
      const SurveyMeasurement(latitude: -6.9, longitude: 107.6, elevation: -4.5),
    );
    final second = await db.saveSurvey(
      const SurveyMeasurement(latitude: -6.91, longitude: 107.61, elevation: 12),
    );

    expect(first.id, 1);
    expect(second.id, 2);
    expect(first.createdAt.isUtc, isTrue);

    final list = await db.loadSurveys();
    expect(list.map((s) => s.id), [2, 1]);
    expect(list.last.measurement.elevation, -4.5);

    final detail = await db.loadSurvey(1);
    expect(detail.measurement.latitude, -6.9);

    await expectLater(
      db.loadSurvey(999),
      throwsA(_apiError('tidak ditemukan')),
    );

    await db.deleteSurvey(1);
    expect((await db.loadSurveys()).map((s) => s.id), [2]);

    await expectLater(
      db.deleteSurvey(1),
      throwsA(_apiError('tidak ditemukan')),
    );
  });

  testWidgets('TopoSurveyApp.local saves, displays, and deletes offline', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final db = LocalDatabaseService(
      openDatabase: () async => sqlite3.openInMemory(),
    );
    addTearDown(db.close);
    final location = _TestLocation();
    addTearDown(location.positions.close);

    await tester.pumpWidget(
      TopoSurveyApp.local(database: db, location: location),
    );
    await tester.pumpAndSettle();

    expect(find.text('Belum ada survei tersimpan.'), findsOneWidget);
    expect(find.text('Memeriksa server…'), findsNothing);
    expect(find.text('Server terhubung'), findsNothing);

    await tester.tap(find.text('Mulai Survei'));
    await tester.pump();
    await tester.pump();

    location.positions.add(_position());
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, 'Simpan Hasil Survei');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(find.text('Hasil survei tersimpan.'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Beranda'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 survei tersimpan'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Riwayat'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Survei #1'), findsOneWidget);

    await tester.tap(find.text('Survei #1'));
    await tester.pumpAndSettle();
    expect(find.text('Ketinggian: -4.5 m'), findsOneWidget);
    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Hapus survei #1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus'));
    await tester.pumpAndSettle();
    expect(find.text('Belum ada survei'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  test('surveysToGeoJson produces valid RFC 7946 FeatureCollection', () {
    final createdAt = DateTime.utc(2026, 11, 16, 3);
    final surveys = [
      Survey(
        id: 1,
        measurement: const SurveyMeasurement(
          latitude: -6.9,
          longitude: 107.6,
          elevation: -4.5,
        ),
        createdAt: createdAt,
      ),
    ];

    final decoded = jsonDecode(surveysToGeoJson(surveys)) as Map<String, Object?>;
    expect(decoded['type'], 'FeatureCollection');
    final features = decoded['features'] as List<Object?>;
    expect(features, hasLength(1));

    final feature = features.single as Map<String, Object?>;
    expect(feature['type'], 'Feature');
    expect(feature['id'], 1);
    expect(feature['geometry'], {
      'type': 'Point',
      'coordinates': [107.6, -6.9, -4.5],
    });
    expect(feature['properties'], {
      'id': 1,
      'latitude': -6.9,
      'longitude': 107.6,
      'elevation': -4.5,
      'created_at': '2026-11-16T03:00:00.000Z',
    });
  });

  testWidgets(
    'HistoryScreen Ekspor GeoJSON dialog supports download, copy, and share',
    (tester) async {
      final calls = <(String, Map<Object?, Object?>?)>[];
      String? copiedText;

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(GeoJsonExporter.defaultChannel, (
        call,
      ) async {
        calls.add((call.method, call.arguments as Map<Object?, Object?>?));
        if (call.method == 'saveGeoJson') {
          return 'Download/toposurvey_export.geojson';
        }
        return null;
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<Object?, Object?>;
          copiedText = args['text'] as String?;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          GeoJsonExporter.defaultChannel,
          null,
        );
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final surveys = [
        Survey(
          id: 2,
          measurement: const SurveyMeasurement(
            latitude: -6.91,
            longitude: 107.61,
            elevation: 12,
          ),
          createdAt: DateTime.utc(2026, 11, 16, 4),
        ),
        Survey(
          id: 1,
          measurement: const SurveyMeasurement(
            latitude: -6.9,
            longitude: 107.6,
            elevation: -4.5,
          ),
          createdAt: DateTime.utc(2026, 11, 16, 3),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistoryScreen(
              snapshot: AsyncSnapshot.withData(ConnectionState.done, surveys),
              onStart: () {},
              onReload: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Ekspor GeoJSON'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('"type": "FeatureCollection"'),
        findsOneWidget,
      );

      await tester.tap(find.text('Unduh (.geojson)'));
      await tester.pumpAndSettle();
      expect(
        find.text('GeoJSON disimpan di: Download/toposurvey_export.geojson'),
        findsOneWidget,
      );
      expect(calls.single.$1, 'saveGeoJson');
      expect(calls.single.$2?['fileName'], 'toposurvey_export.geojson');
      final savedJson =
          jsonDecode(calls.single.$2?['content'] as String)
              as Map<String, Object?>;
      expect((savedJson['features'] as List<Object?>).length, 2);

      await tester.tap(find.widgetWithText(FilledButton, 'Ekspor GeoJSON'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salin'));
      await tester.pumpAndSettle();
      expect(find.text('GeoJSON disalin ke clipboard.'), findsOneWidget);
      expect(copiedText, contains('"FeatureCollection"'));
      expect(copiedText, contains('107.61'));

      await tester.tap(find.widgetWithText(FilledButton, 'Ekspor GeoJSON'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bagikan'));
      await tester.pumpAndSettle();
      expect(calls.last.$1, 'shareGeoJson');
      expect(calls.last.$2?['fileName'], 'toposurvey_export.geojson');
    },
  );
}
