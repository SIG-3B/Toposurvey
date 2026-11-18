import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:toposurvey/main.dart';
import 'package:toposurvey/models/survey.dart';
import 'package:toposurvey/services/api_service.dart';
import 'package:toposurvey/services/location_service.dart';

class TestLocation extends LocationService {
  TestLocation({this.access = LocationAccess.ready});

  LocationAccess access;
  LocationAccess? requestedAccess;
  int permissionRequests = 0;
  int appSettingsOpened = 0;
  int locationSettingsOpened = 0;
  final positions = StreamController<Position>.broadcast();

  @override
  Future<LocationAccess> checkAccess({bool requestPermission = false}) async {
    if (requestPermission) {
      permissionRequests++;
      access = requestedAccess ?? access;
    }
    return access;
  }

  @override
  Stream<Position> watchPositions() => positions.stream;

  @override
  Future<bool> openAppSettings() async {
    appSettingsOpened++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsOpened++;
    return true;
  }
}

Position position({
  double latitude = -6.9,
  double longitude = 107.6,
  double altitude = -4.5,
  bool hasAltitude = true,
  bool hasAccuracy = true,
}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime.utc(2026, 11, 16, 3),
  accuracy: hasAccuracy ? 5 : 0,
  altitude: altitude,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
  hasAltitude: hasAltitude,
  hasAccuracy: hasAccuracy,
);

Finder tab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Finder get saveButton =>
    find.widgetWithText(FilledButton, 'Simpan Hasil Survei');

Future<void> tap(WidgetTester tester, Finder target) async {
  if (target.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(target);
  }
  await tester.tap(target);
  await tester.pump();
  await tester.pump();
}

Future<void> startSurvey(WidgetTester tester) async {
  await tap(tester, find.text('Mulai Survei'));
  await tester.pump();
}

Future<void> unmount(WidgetTester tester, TestLocation location) async {
  await tester.pumpWidget(const SizedBox());
  await location.positions.close();
}

Future<void> changeLifecycle(WidgetTester tester, AppLifecycleState state) {
  return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    SystemChannels.lifecycle.codec.encodeMessage(state.toString()),
    (_) {},
  );
}

Future<void> expectTracking(WidgetTester tester, TestLocation location) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
  expect(location.positions.hasListener, isTrue, reason: shownText(tester));
}

String shownText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data)
    .join(' | ');

void main() {
  testWidgets('Navigation, honest empty state and narrow text layout', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final location = TestLocation();
    await tester.pumpWidget(TopoSurveyApp(location: location));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('TopoSurvey'), findsOneWidget);
    expect(
      find.text('GPS siap digunakan'),
      findsOneWidget,
      reason: shownText(tester),
    );
    expect(find.text('Jumlah survei belum tersedia.'), findsOneWidget);
    expect(location.permissionRequests, 0);
    expect(location.positions.hasListener, isFalse);

    await startSurvey(tester);
    expect(find.text('Mencari posisi…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(location.positions.hasListener, isTrue);
    location.positions.add(position());
    await tester.pumpAndSettle();
    expect(find.text('Posisi diterima'), findsOneWidget);
    await tester.ensureVisible(saveButton);
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    expect(find.text('Penyimpanan belum terhubung.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tap(tester, tab('Riwayat'));
    await tester.pumpAndSettle();
    expect(location.positions.hasListener, isFalse);
    expect(find.text('Riwayat belum tersedia'), findsOneWidget);
    await tap(tester, tab('Beranda'));
    expect(find.text('Survei topografi'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester, location);
  });

  testWidgets('Menu Lainnya opens Export Data and Settings', (tester) async {
    final location = TestLocation();
    await tester.pumpWidget(TopoSurveyApp(location: location));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Lainnya'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ekspor Data').last);
    await tester.pumpAndSettle();
    expect(find.text('Ekspor data survei'), findsOneWidget);
    expect(find.text('Format file'), findsOneWidget);

    await tester.tap(find.byTooltip('Lainnya'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pengaturan').last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Pengaturan'),
      ),
      findsOneWidget,
    );
    expect(find.text('Ambang akurasi horizontal'), findsOneWidget);
    expect(find.text('Satuan elevasi'), findsOneWidget);
    await unmount(tester, location);
  });

  testWidgets('Denied access requests permission and handles blocked access', (
    tester,
  ) async {
    final location = TestLocation(access: LocationAccess.denied)
      ..requestedAccess = LocationAccess.denied;
    await tester.pumpWidget(TopoSurveyApp(location: location));
    await startSurvey(tester);
    expect(find.text('Izin lokasi belum diberikan'), findsOneWidget);
    await tap(tester, find.text('Aktifkan GPS'));
    await tester.pumpAndSettle();
    expect(location.permissionRequests, 1, reason: shownText(tester));
    expect(
      find.text('Izin lokasi belum diberikan'),
      findsOneWidget,
      reason: shownText(tester),
    );
    expect(location.permissionRequests, 1);

    location.requestedAccess = LocationAccess.deniedForever;
    await tap(tester, find.text('Aktifkan GPS'));
    await tester.pumpAndSettle();
    expect(find.text('Izin lokasi diblokir'), findsOneWidget);
    await tap(tester, find.text('Buka pengaturan aplikasi'));
    expect(location.appSettingsOpened, 1);
    expect(location.positions.hasListener, isFalse);
    await unmount(tester, location);
  });

  testWidgets('Service settings, foreground stream and timeout recovery', (
    tester,
  ) async {
    final location = TestLocation(access: LocationAccess.disabled);
    await changeLifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpWidget(TopoSurveyApp(location: location));
    await startSurvey(tester);
    expect(find.text('Layanan lokasi nonaktif'), findsOneWidget);
    await tap(tester, find.text('Aktifkan GPS'));
    expect(location.locationSettingsOpened, 1);

    await changeLifecycle(tester, AppLifecycleState.paused);
    location.access = LocationAccess.ready;
    await changeLifecycle(tester, AppLifecycleState.resumed);
    await tester.pump();
    expect(location.positions.hasListener, isTrue);
    location.positions.add(position());
    await tester.pumpAndSettle();

    await changeLifecycle(tester, AppLifecycleState.paused);
    await tester.pump();
    expect(location.positions.hasListener, isFalse);
    await changeLifecycle(tester, AppLifecycleState.resumed);
    await expectTracking(tester, location);
    expect(find.text('Mencari posisi…'), findsOneWidget);

    location.positions.addError(TimeoutException('test timeout'));
    await tester.pumpAndSettle();
    expect(find.textContaining('melebihi batas waktu'), findsOneWidget);
    expect(location.positions.hasListener, isFalse);
    await tap(tester, find.text('Cari posisi lagi'));
    await expectTracking(tester, location);
    location.positions.addError(StateError('test failure'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Posisi tidak dapat diperoleh'), findsOneWidget);
    expect(location.positions.hasListener, isFalse);
    await unmount(tester, location);
  });

  testWidgets('Measurements update and save only after valid elevation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final location = TestLocation();
    final pendingSave = Completer<Survey>();
    final submitted = <Map<String, double>>[];
    await tester.pumpWidget(
      TopoSurveyApp(
        location: location,
        saveSurvey: (measurement) {
          submitted.add(measurement.toJson());
          if (submitted.length > 1) {
            throw const ApiException('Server tidak dapat dihubungi.');
          }
          return pendingSave.future;
        },
      ),
    );
    await startSurvey(tester);
    location.positions.add(
      position(altitude: 0, hasAltitude: false, hasAccuracy: false),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(saveButton);
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    expect(find.text('0.0 m'), findsNothing);
    expect(find.text('Perkiraan akurasi horizontal: —'), findsOneWidget);

    location.positions.add(position(latitude: double.nan));
    await tester.pump();
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    location.positions.add(position(altitude: double.infinity));
    await tester.pump();
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    location.positions.add(position(altitude: 0));
    await tester.pumpAndSettle();
    expect(find.text('0.0 m'), findsOneWidget);
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);

    location.positions.add(position(latitude: -6.91));
    await tester.pumpAndSettle();
    expect(find.text('-6.910000°'), findsOneWidget);
    expect(find.text('107.600000°'), findsOneWidget);
    expect(find.text('-4.5 m'), findsOneWidget);
    expect(find.text('Perkiraan akurasi horizontal: ±5.0 m'), findsOneWidget);
    await tester.ensureVisible(saveButton);
    await tap(tester, saveButton);
    expect(find.text('Menyimpan…'), findsOneWidget);
    expect(find.text('Hasil survei tersimpan.'), findsNothing);
    expect(submitted.single, {
      'latitude': -6.91,
      'longitude': 107.6,
      'elevation': -4.5,
    });
    location.positions.add(position(latitude: -6.95, altitude: 12));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Menyimpan…'))
          .onPressed,
      isNull,
    );
    expect(submitted.single['latitude'], -6.91);
    pendingSave.complete(
      Survey.fromJson({
        ...submitted.single,
        'id': 1,
        'created_at': '2026-11-16T03:00:00Z',
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hasil survei tersimpan.'), findsOneWidget);
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.ensureVisible(saveButton);
    await tap(tester, saveButton);
    await tester.pumpAndSettle();
    expect(
      find.text('Gagal menyimpan. Server tidak dapat dihubungi.'),
      findsOneWidget,
    );
    expect(find.text('Hasil survei tersimpan.'), findsNothing);
    await unmount(tester, location);
  });

  testWidgets('History retries, opens details and confirms deletion', (
    tester,
  ) async {
    final location = TestLocation();
    final records = [
      Survey.fromJson({
        'id': 12,
        'latitude': -6.9,
        'longitude': 107,
        'elevation': -4.5,
        'created_at': '2026-11-16T03:00:00Z',
      }),
    ];
    var loads = 0;
    final detailIds = <int>[];
    await tester.pumpWidget(
      TopoSurveyApp(
        location: location,
        loadSurveys: () async {
          if (++loads == 1) throw StateError('test load failure');
          return List.of(records);
        },
        loadSurvey: (id) async {
          detailIds.add(id);
          return records.single;
        },
        deleteSurvey: (id) async => records.removeWhere((row) => row.id == id),
      ),
    );
    await tap(tester, find.text('Lihat Riwayat'));
    expect(find.text('Riwayat tidak dapat dimuat'), findsOneWidget);
    await tap(tester, find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(find.text('Survei #12'), findsOneWidget);
    await tap(tester, find.text('Survei #12'));
    await tester.pumpAndSettle();
    expect(find.text('Ketinggian: -4.5 m'), findsOneWidget);
    expect(detailIds, [12]);
    expect(find.textContaining('16/11/2026'), findsWidgets);
    await tap(tester, find.text('Tutup'));
    await tester.pumpAndSettle();

    await tap(tester, find.byTooltip('Hapus survei #12'));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Batal'));
    await tester.pumpAndSettle();
    expect(records.single.id, 12);
    await tap(tester, find.byTooltip('Hapus survei #12'));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Hapus'));
    await tester.pumpAndSettle();
    expect(records, isEmpty);
    expect(find.text('Belum ada survei'), findsOneWidget);
    await tap(tester, tab('Beranda'));
    expect(find.text('Belum ada survei tersimpan.'), findsOneWidget);
    await unmount(tester, location);
  });

  testWidgets(
    'Refresh history when the server reports an already removed survey',
    (tester) async {
      final location = TestLocation();
      final initial = Completer<List<Survey>>();
      var loads = 0;
      final survey = Survey(
        id: 8,
        measurement: const SurveyMeasurement(
          latitude: -6.9,
          longitude: 107.6,
          elevation: 0,
        ),
        createdAt: DateTime.utc(2026),
      );
      await tester.pumpWidget(
        TopoSurveyApp(
          location: location,
          loadSurveys: () => ++loads == 1 ? initial.future : Future.value([]),
          deleteSurvey: (_) async {
            throw const ApiException('Data survei tidak ditemukan.');
          },
        ),
      );
      expect(find.text('Memuat jumlah survei…'), findsOneWidget);
      initial.complete([survey]);
      await tester.pumpAndSettle();
      expect(find.text('1 survei tersimpan'), findsOneWidget);
      await tap(tester, tab('Riwayat'));
      await tap(tester, find.byTooltip('Hapus survei #8'));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Hapus'));
      await tester.pumpAndSettle();
      expect(
        find.text('Gagal menghapus. Data survei tidak ditemukan.'),
        findsOneWidget,
      );
      expect(find.text('Survei #8'), findsNothing);
      expect(find.text('Belum ada survei'), findsOneWidget);
      await tap(tester, tab('Beranda'));
      expect(find.text('Belum ada survei tersimpan.'), findsOneWidget);
      await unmount(tester, location);
    },
  );
}
