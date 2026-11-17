import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/activity_log.dart';
import '../models/survey.dart';
import '../services/local_database_service.dart';
import '../widgets/survey_map.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.surveys,
    this.database,
    this.userLocation,
    this.accuracyMeters,
  });
  final List<Survey> surveys;
  final LocalDatabaseService? database;
  final LatLng? userLocation;
  final double? accuracyMeters;
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  int? _project;
  Survey? _selected;
  @override
  Widget build(BuildContext context) {
    final surveys = widget.surveys
        .where((s) => _project == null || _project == s.projectId)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FutureBuilder<List<SurveyProject>>(
          future: widget.database?.loadProjects(),
          builder: (context, snap) {
            final projects = snap.data ?? const <SurveyProject>[];
            return DropdownButtonFormField<int?>(
              initialValue: _project,
              decoration: const InputDecoration(labelText: 'Filter proyek'),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Semua proyek'),
                ),
                ...projects.map(
                  (p) =>
                      DropdownMenuItem<int?>(value: p.id, child: Text(p.name)),
                ),
              ],
              onChanged: (v) => setState(() {
                _project = v;
                _selected = null;
              }),
            );
          },
        ),
        const SizedBox(height: 12),
        SurveyMap(
          savedSurveys: surveys,
          userLocation: widget.userLocation,
          accuracyMeters: widget.accuracyMeters,
          expand: true,
          focusSurvey: _selected,
          onSurveyTap: (s) => setState(() => _selected = s),
        ),
        if (_selected != null)
          Card(
            child: ListTile(
              title: Text('${_selected!.pointCode} · ${_selected!.pointName}'),
              subtitle: Text(
                'Lat ${_selected!.measurement.latitude}\nLon ${_selected!.measurement.longitude}\nElevasi ${_selected!.measurement.elevation} m · ${_selected!.fixTime?.toLocal()}',
              ),
              isThreeLine: true,
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Titik survei (${surveys.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (surveys.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Belum ada titik pada proyek ini. Data tersimpan tetap tersedia saat offline.',
            ),
          ),
        ...surveys.map(
          (s) => ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text('${s.pointCode} · ${s.pointName}'),
            subtitle: Text(
              '${s.measurement.latitude.toStringAsFixed(6)}, ${s.measurement.longitude.toStringAsFixed(6)} · ${s.measurement.elevation.toStringAsFixed(1)} m',
            ),
            onTap: () => setState(() => _selected = s),
          ),
        ),
      ],
    );
  }
}
