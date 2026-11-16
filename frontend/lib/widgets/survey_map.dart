import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/survey.dart';

class SurveyMap extends StatefulWidget {
  const SurveyMap({
    super.key,
    this.userLocation,
    this.accuracyMeters,
    this.savedSurveys = const [],
    this.createTileProvider,
  });

  final LatLng? userLocation;
  final double? accuracyMeters;
  final List<Survey> savedSurveys;
  final TileProvider Function()? createTileProvider;

  @override
  State<SurveyMap> createState() => _SurveyMapState();
}

class _SurveyMapState extends State<SurveyMap> {
  static const _minZoom = 2.0;
  static const _maxZoom = 19.0;
  static const _locationZoom = 16.0;
  static const _positionColor = Color(0xFF1D4ED8);

  final _controller = MapController();
  late bool _centeredOnFix;
  late TileLayer _tiles = _buildTileLayer();
  bool _tileFailed = false;
  int _tileAttempt = 0;

  @override
  void initState() {
    super.initState();
    _centeredOnFix = widget.userLocation != null;
  }

  @override
  void didUpdateWidget(covariant SurveyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_centeredOnFix || widget.userLocation == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fix = widget.userLocation;
      if (!mounted || _centeredOnFix || fix == null) return;
      _centeredOnFix = true;
      _controller.move(fix, _locationZoom);
    });
  }

  TileLayer _buildTileLayer() {
    final attempt = _tileAttempt;
    return TileLayer(
      key: ValueKey(attempt),
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.toposurvey.toposurvey',
      tileProvider:
          widget.createTileProvider?.call() ??
          NetworkTileProvider(attemptDecodeOfHttpErrorResponses: false),
      maxNativeZoom: _maxZoom.toInt(),
      panBuffer: 0,
      errorTileCallback: (_, _, _) {
        if (!mounted || _tileFailed || attempt != _tileAttempt) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _tileFailed || attempt != _tileAttempt) return;
          setState(() => _tileFailed = true);
        });
        WidgetsBinding.instance.ensureVisualUpdate();
      },
    );
  }

  void _retryTiles() {
    setState(() {
      _tileFailed = false;
      _tileAttempt++;
      _tiles = _buildTileLayer();
    });
  }

  void _zoom(double delta) {
    final camera = _controller.camera;
    final zoom = (camera.zoom + delta).clamp(_minZoom, _maxZoom);
    _controller.move(camera.center, zoom);
  }

  Future<void> _openAttribution() async {
    final url = Uri.https('www.openstreetmap.org', '/copyright');
    try {
      if (await launchUrl(url, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Keep the attribution visible if the system cannot open the link.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tautan OpenStreetMap tidak dapat dibuka.')),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fix = widget.userLocation;
    final accuracy = widget.accuracyMeters;
    final savedMarkers = widget.savedSurveys.map((survey) {
      final data = survey.measurement;
      return Marker(
        point: LatLng(data.latitude, data.longitude),
        alignment: Alignment.topCenter,
        child: Icon(
          Icons.location_on,
          size: 32,
          color: colors.primary,
          semanticLabel: 'Titik survei #${survey.id}',
        ),
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 248,
            child: Stack(
              fit: StackFit.expand,
              children: [
                FlutterMap(
                  mapController: _controller,
                  options: MapOptions(
                    initialCenter: fix ?? const LatLng(0, 0),
                    initialZoom: fix == null ? _minZoom : _locationZoom,
                    minZoom: _minZoom,
                    maxZoom: _maxZoom,
                    backgroundColor: colors.outlineVariant,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: [
                    _tiles,
                    if (fix != null && accuracy != null && accuracy > 0)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: fix,
                            radius: accuracy,
                            useRadiusInMeter: true,
                            color: _positionColor.withValues(alpha: 0.16),
                            borderColor: _positionColor,
                            borderStrokeWidth: 1,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        ...savedMarkers,
                        if (fix != null)
                          Marker(
                            point: fix,
                            width: 24,
                            height: 24,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.adjust,
                                color: _positionColor,
                                size: 22,
                                semanticLabel: 'Posisi saat ini',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  right: 64,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: colors.surface,
                        foregroundColor: colors.onSurface,
                        padding: const EdgeInsets.all(8),
                      ),
                      onPressed: _openAttribution,
                      child: Text(
                        '© OpenStreetMap contributors',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Material(
                    color: colors.surface,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: colors.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        IconButton(
                          tooltip: 'Perbesar peta',
                          onPressed: () => _zoom(1),
                          icon: const Icon(Icons.add),
                        ),
                        IconButton(
                          tooltip: 'Perkecil peta',
                          onPressed: () => _zoom(-1),
                          icon: const Icon(Icons.remove),
                        ),
                        IconButton(
                          tooltip: 'Kembali ke posisi saya',
                          onPressed: fix == null
                              ? null
                              : () => _controller.move(
                                  fix,
                                  _controller.camera.zoom,
                                ),
                          icon: const Icon(Icons.my_location),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_tileFailed) ...[
          const SizedBox(height: 8),
          const Text(
            'Peta belum lengkap. Periksa koneksi internet. Pengukuran tetap berjalan.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _retryTiles,
              child: const Text('Muat ulang peta'),
            ),
          ),
        ],
      ],
    );
  }
}
