import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/activity_log.dart';
import '../models/survey.dart';
import '../models/survey_preferences.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/local_database_service.dart';
import '../widgets/survey_map.dart';

class SurveyScreen extends StatefulWidget {
  const SurveyScreen({
    super.key,
    required this.location,
    this.savedSurveys = const [],
    this.isSaving = false,
    this.storageUnavailable = false,
    this.onSave,
    this.database,
    this.onPositionChanged,
    this.accuracyThresholdMeters = 10,
    this.elevationUnit = ElevationUnit.meters,
    this.showOpenStreetMap = true,
  });

  final LocationService location;
  final List<Survey> savedSurveys;
  final bool isSaving;
  final bool storageUnavailable;
  final Future<Survey> Function(SurveyMeasurement)? onSave;
  final LocalDatabaseService? database;
  final ValueChanged<Position>? onPositionChanged;
  final double accuracyThresholdMeters;
  final ElevationUnit elevationUnit;
  final bool showOpenStreetMap;

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _notes = TextEditingController();
  int _projectId = 1;
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<Position>? _subscription;
  Future<void>? _cancellation;
  int _session = 0;
  bool _suspended = false;
  bool _searching = true;
  LocationAccess? _access;
  Position? _position;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _suspended = true;
        unawaited(_stop());
        setState(() => _position = null);
      },
      onResume: () {
        if (_suspended) {
          _suspended = false;
          unawaited(_start());
        }
      },
    );
    unawaited(_start());
  }

  Future<void> _stop() async {
    _session++;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      _cancellation = subscription.cancel().catchError((Object error) {
        debugPrint('Location stream cancellation failed: $error');
      });
    }
    await _cancellation;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_stop());
    _code.dispose();
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool _isCurrent(int session) => mounted && !_suspended && session == _session;

  Future<void> _start({bool requestPermission = false}) async {
    final stopped = _stop();
    final session = _session;
    setState(() {
      _searching = true;
      _access = null;
      _position = null;
      _failure = null;
    });
    try {
      await stopped;
      if (!_isCurrent(session)) return;
      final access = await widget.location.checkAccess(
        requestPermission: requestPermission,
      );
      if (!_isCurrent(session)) return;
      setState(() {
        _access = access;
        _searching = access == LocationAccess.ready;
      });
      if (access != LocationAccess.ready) return;

      _subscription = widget.location.watchPositions().listen(
        (position) {
          if (!_isCurrent(session)) return;
          setState(() {
            _position = position;
            _searching = false;
          });
          widget.onPositionChanged?.call(position);
        },
        onError: (Object error) => _fail(session, error),
        onDone: () => _fail(session, StateError('Location stream ended')),
      );
    } catch (error) {
      _fail(session, error);
    }
  }

  void _fail(int session, Object error) {
    if (!_isCurrent(session)) return;
    unawaited(_stop());
    setState(() {
      _position = null;
      _searching = false;
      switch (error) {
        case LocationServiceDisabledException():
          _access = LocationAccess.disabled;
        case PermissionDeniedException():
          _access = kIsWeb
              ? LocationAccess.deniedForever
              : LocationAccess.denied;
        case TimeoutException():
          _failure =
              'Pencarian posisi melebihi batas waktu. Coba di area terbuka.';
        default:
          _failure = 'Posisi tidak dapat diperoleh. Silakan coba lagi.';
      }
    });
  }

  Future<void> _settings(Future<bool> Function() open) async {
    try {
      if (await open()) return;
    } catch (_) {
      // The same message also covers platforms that cannot open settings.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pengaturan ponsel tidak dapat dibuka.')),
    );
  }

  Future<void> _editMetadata() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Metadata titik'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _code,
              maxLength: 35,
              decoration: const InputDecoration(labelText: 'Kode titik'),
            ),
            TextField(
              controller: _name,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Nama titik'),
            ),
            TextField(
              controller: _notes,
              maxLength: 500,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Catatan lapangan'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (changed == true && mounted) setState(() {});
  }

  Future<void> _save(SurveyMeasurement measurement) async {
    final onSave = widget.onSave;
    if (onSave == null || widget.isSaving) return;
    String message;
    try {
      await onSave(measurement);
      message = 'Hasil survei tersimpan.';
    } catch (error) {
      message = error is ApiException
          ? 'Gagal menyimpan. ${error.message}'
          : 'Hasil survei gagal disimpan. Coba lagi.';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final position = _position;
    final latitude = position?.latitude;
    final longitude = position?.longitude;
    final validLatitude = latitude != null && latitude >= -90 && latitude <= 90;
    final validLongitude =
        longitude != null && longitude >= -180 && longitude <= 180;
    final altitude =
        position != null && position.hasAltitude && position.altitude.isFinite
        ? position.altitude
        : null;
    final accuracy =
        position != null &&
            position.hasAccuracy &&
            position.accuracy.isFinite &&
            position.accuracy >= 0
        ? position.accuracy
        : null;
    final canSave =
        widget.onSave != null &&
        !widget.isSaving &&
        !_suspended &&
        validLatitude &&
        validLongitude &&
        altitude != null;

    final label = switch ((_searching, position)) {
      (true, _) =>
        _access == LocationAccess.ready ? 'Mencari posisi…' : 'Memeriksa GPS…',
      (_, Position(isMocked: true)) => 'Posisi simulasi',
      (_, Position()) => 'Posisi diterima',
      _ => _failure ?? (_access ?? LocationAccess.unavailable).label,
    };
    final (actionLabel, action) = switch ((_searching, position, _access)) {
      (true, _, _) || (_, Position(), _) => (null, null),
      (_, _, LocationAccess.disabled) => (
        'Aktifkan GPS',
        () => _settings(widget.location.openLocationSettings),
      ),
      (_, _, LocationAccess.deniedForever) when kIsWeb => (
        'Coba lagi',
        () => _start(requestPermission: true),
      ),
      (_, _, LocationAccess.deniedForever) => (
        'Buka pengaturan aplikasi',
        () => _settings(widget.location.openAppSettings),
      ),
      (_, _, LocationAccess.denied || LocationAccess.unavailable) => (
        'Aktifkan GPS',
        () => _start(requestPermission: true),
      ),
      _ => ('Cari posisi lagi', () => _start(requestPermission: true)),
    };

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Lihat posisi di peta dan ukur koordinat serta ketinggian titik.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: ListTile(
                    tileColor: colors.primaryContainer,
                    textColor: colors.onPrimaryContainer,
                    iconColor: colors.onPrimaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    leading: _searching
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            position != null ? Icons.gps_fixed : Icons.gps_off,
                          ),
                    title: const Text('Status GPS'),
                    subtitle: Text(label),
                  ),
                ),
                if (action != null && actionLabel != null) ...[
                  const SizedBox(height: 8),
                  if (kIsWeb && _access == LocationAccess.deniedForever)
                    const Text(
                      'Izinkan Lokasi di pengaturan situs browser, lalu ketuk Coba lagi.',
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: action,
                      icon: const Icon(Icons.my_location),
                      label: Text(actionLabel),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  accuracy == null
                      ? 'Perkiraan akurasi horizontal: —'
                      : 'Perkiraan akurasi horizontal: ±${accuracy.toStringAsFixed(1)} m',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (accuracy != null &&
                    accuracy > widget.accuracyThresholdMeters)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Akurasi melewati ambang ${widget.accuracyThresholdMeters.round()} m. Titik akan ditandai kualitas rendah.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                SurveyMap(
                  userLocation: validLatitude && validLongitude
                      ? LatLng(latitude, longitude)
                      : null,
                  accuracyMeters: accuracy,
                  savedSurveys: widget.savedSurveys,
                  showOpenStreetMap: widget.showOpenStreetMap,
                ),
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border.all(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Reading(
                        label: 'Garis Lintang',
                        value: validLatitude
                            ? '${latitude.toStringAsFixed(6)}°'
                            : '—',
                      ),
                      const Divider(height: 1),
                      _Reading(
                        label: 'Garis Bujur',
                        value: validLongitude
                            ? '${longitude.toStringAsFixed(6)}°'
                            : '—',
                      ),
                      const Divider(height: 1),
                      _Reading(
                        label: 'Ketinggian',
                        value: altitude == null
                            ? '—'
                            : '${widget.elevationUnit.fromMeters(altitude).toStringAsFixed(1)} ${widget.elevationUnit.symbol}',
                        note: 'Relatif terhadap elipsoid WGS 84',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (widget.database != null)
                  FutureBuilder<List<SurveyProject>>(
                    future: widget.database!.loadProjects(),
                    builder: (context, snapshot) {
                      final projects = snapshot.data ?? const <SurveyProject>[];
                      if (projects.isNotEmpty &&
                          !projects.any((p) => p.id == _projectId)) {
                        _projectId = projects.first.id;
                      }
                      return DropdownButtonFormField<int>(
                        initialValue: projects.any((p) => p.id == _projectId)
                            ? _projectId
                            : null,
                        decoration: const InputDecoration(labelText: 'Proyek'),
                        items: projects
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(p.name),
                              ),
                            )
                            .toList(),
                        onChanged: (id) {
                          if (id != null) setState(() => _projectId = id);
                        },
                      );
                    },
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _editMetadata,
                  icon: const Icon(Icons.edit_note),
                  label: Text(
                    _code.text.isEmpty && _name.text.isEmpty
                        ? 'Atur metadata titik'
                        : '${_code.text} · ${_name.text}',
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: canSave
                      ? () => _save(
                          SurveyMeasurement(
                            latitude: latitude,
                            longitude: longitude,
                            elevation: altitude,
                            horizontalAccuracy: accuracy,
                            verticalAccuracy: position!.altitudeAccuracy,
                            fixTime: position.timestamp.toUtc(),
                            pointCode: _code.text.trim(),
                            pointName: _name.text.trim(),
                            notes: _notes.text.trim(),
                            projectId: _projectId,
                            provider: position.isMocked ? 'MOCK' : 'GPS',
                            source: position.isMocked ? 'SIMULATED' : 'DEVICE',
                            quality:
                                accuracy != null &&
                                    accuracy > widget.accuracyThresholdMeters
                                ? 'LOW_QUALITY'
                                : 'ACCEPTED',
                          ),
                        )
                      : null,
                  icon: widget.isSaving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    widget.isSaving ? 'Menyimpan…' : 'Simpan Hasil Survei',
                  ),
                ),
                if (widget.onSave == null ||
                    (position != null && altitude == null))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      widget.onSave == null
                          ? 'Penyimpanan belum terhubung.'
                          : 'Ponsel belum memberikan data ketinggian.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (widget.storageUnavailable)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Penyimpanan belum bisa diakses. GPS tetap bisa digunakan.',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({required this.label, required this.value, this.note});

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
            ),
          ),
          if (note != null)
            Text(
              note!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
