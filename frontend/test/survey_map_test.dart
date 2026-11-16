import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:toposurvey/models/survey.dart';
import 'package:toposurvey/widgets/survey_map.dart';

final _tilePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGOYdPAuAAQZAjF+1YEmAAAAAElFTkSuQmCC',
);
final _drawnTile = find.byWidgetPredicate(
  (widget) => widget is RawImage && widget.image != null,
);

Widget mapApp({
  LatLng? fix,
  List<Survey> savedSurveys = const [],
  required http.Client client,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 320,
        child: SurveyMap(
          userLocation: fix,
          accuracyMeters: fix == null ? null : 12,
          savedSurveys: savedSurveys,
          createTileProvider: () => NetworkTileProvider(
            httpClient: client,
            cachingProvider: const DisabledMapCachingProvider(),
            attemptDecodeOfHttpErrorResponses: false,
          ),
        ),
      ),
    ),
  ),
);

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  // Flutter's tile image decoder completes outside the widget test clock.
  for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 40));
  }
  expect(finder, findsWidgets);
}

void main() {
  testWidgets('Draw map, keep panned camera and recenter on request', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response.bytes(
        _tilePng,
        200,
        headers: {'Content-Type': 'image/png'},
      );
    });
    addTearDown(client.close);
    const first = LatLng(-6.9, 107.6);
    const updated = LatLng(-6.9001, 107.6001);
    final map = find.byType(FlutterMap);
    final recenter = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton && widget.tooltip == 'Kembali ke posisi saya',
    );

    await tester.pumpWidget(mapApp(client: client));
    await waitFor(tester, _drawnTile);
    expect(requests.first.url.host, 'tile.openstreetmap.org');
    expect(
      requests.first.headers['user-agent'],
      contains('com.toposurvey.toposurvey'),
    );
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(tester.widget<IconButton>(recenter).onPressed, isNull);
    expect(
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
      isEmpty,
    );

    final saved = Survey(
      id: 12,
      measurement: const SurveyMeasurement(
        latitude: -6.9,
        longitude: 107.601,
        elevation: 10,
      ),
      createdAt: DateTime.utc(2026),
    );
    await tester.pumpWidget(
      mapApp(client: client, fix: first, savedSurveys: [saved]),
    );
    await tester.pumpAndSettle();
    final controller = tester.widget<FlutterMap>(map).mapController!;
    expect(controller.camera.center, first);
    expect(controller.camera.zoom, 16);
    final circle = tester
        .widget<CircleLayer>(find.byType(CircleLayer))
        .circles
        .single;
    expect(circle.radius, 12);
    expect(circle.useRadiusInMeter, isTrue);

    await tester.tap(find.byTooltip('Perbesar peta'));
    await tester.pumpAndSettle();
    expect(controller.camera.zoom, 17);
    await tester.tap(find.byTooltip('Perkecil peta'));
    await tester.pumpAndSettle();
    expect(controller.camera.zoom, 16);
    await tester.drag(map, const Offset(-50, 32));
    await tester.pumpAndSettle();
    final pannedCenter = controller.camera.center;
    expect(pannedCenter, isNot(first));

    await tester.pumpWidget(
      mapApp(client: client, fix: updated, savedSurveys: [saved]),
    );
    await tester.pumpAndSettle();
    expect(controller.camera.center, pannedCenter);
    expect(
      tester
          .widget<MarkerLayer>(find.byType(MarkerLayer))
          .markers
          .map((marker) => marker.point),
      [const LatLng(-6.9, 107.601), updated],
    );
    await tester.tap(recenter);
    await tester.pumpAndSettle();
    expect(controller.camera.center, updated);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Report tile failure and retry without removing location', (
    tester,
  ) async {
    var offline = true;
    final client = MockClient(
      (request) async => offline
          ? http.Response('unavailable', 503)
          : http.Response.bytes(
              _tilePng,
              200,
              headers: {'Content-Type': 'image/png'},
            ),
    );
    addTearDown(client.close);
    const fix = LatLng(-7.255, 112.74);
    await tester.pumpWidget(mapApp(client: client, fix: fix));
    await waitFor(tester, find.textContaining('Peta belum lengkap'));
    expect(
      tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.single.point,
      fix,
    );
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);

    offline = false;
    await tester.tap(find.text('Muat ulang peta'));
    await tester.pumpAndSettle();
    await waitFor(tester, _drawnTile);
    expect(find.textContaining('Peta belum lengkap'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
