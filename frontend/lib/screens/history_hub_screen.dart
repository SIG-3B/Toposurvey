import 'package:flutter/material.dart';
import '../models/activity_log.dart';
import '../models/survey.dart';
import '../models/survey_preferences.dart';
import '../services/local_database_service.dart';
import 'history_screen.dart';

class HistoryHubScreen extends StatefulWidget {
  const HistoryHubScreen({
    super.key,
    required this.snapshot,
    required this.database,
    required this.onStart,
    required this.onReload,
    this.loadDetail,
    this.onDelete,
    this.elevationUnit = ElevationUnit.meters,
  });
  final AsyncSnapshot<List<Survey>> snapshot;
  final LocalDatabaseService? database;
  final VoidCallback onStart;
  final VoidCallback onReload;
  final Future<Survey> Function(int)? loadDetail;
  final Future<void> Function(int)? onDelete;
  final ElevationUnit elevationUnit;
  @override
  State<HistoryHubScreen> createState() => _HistoryHubScreenState();
}

class _HistoryHubScreenState extends State<HistoryHubScreen> {
  int? _project;
  Future<void> _activityDetail(ActivityLog activity) async {
    final id = activity.surveyId;
    if (id == null || widget.database == null) return;
    try {
      final survey = await widget.database!.loadSurvey(id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('${survey.pointCode} · ${survey.pointName}'),
          content: Text(
            'Latitude ${survey.measurement.latitude}\nLongitude ${survey.measurement.longitude}\nElevasi ${widget.elevationUnit.fromMeters(survey.measurement.elevation).toStringAsFixed(1)} ${widget.elevationUnit.symbol}\n${survey.createdAt.toLocal()}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    } catch (_) {}
  }

  Future<void> _logExport(int count) async {
    await widget.database?.logExport(null, count);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.database == null) {
      return HistoryScreen(
        snapshot: widget.snapshot,
        onStart: widget.onStart,
        onReload: widget.onReload,
        loadDetail: widget.loadDetail,
        onDelete: widget.onDelete,
        elevationUnit: widget.elevationUnit,
      );
    }
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Aktivitas'),
              Tab(text: 'Pengukuran'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                FutureBuilder<List<ActivityLog>>(
                  future: widget.database?.loadActivityLogs(
                    projectId: _project,
                  ),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        FutureBuilder<List<SurveyProject>>(
                          future: widget.database?.loadProjects(),
                          builder: (context, p) =>
                              DropdownButtonFormField<int?>(
                                initialValue: _project,
                                decoration: const InputDecoration(
                                  labelText: 'Filter proyek',
                                ),
                                items: [
                                  const DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text('Semua proyek'),
                                  ),
                                  ...(p.data ?? const <SurveyProject>[]).map(
                                    (x) => DropdownMenuItem<int?>(
                                      value: x.id,
                                      child: Text(x.name),
                                    ),
                                  ),
                                ],
                                onChanged: (v) => setState(() => _project = v),
                              ),
                        ),
                        const SizedBox(height: 12),
                        if ((snap.data ?? []).isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Belum ada aktivitas tersimpan.'),
                          ),
                        ...(snap.data ?? const <ActivityLog>[]).map(
                          (a) => Card(
                            child: ListTile(
                              leading: Icon(switch (a.action) {
                                'CREATE' => Icons.add_location_alt_outlined,
                                'EDIT' => Icons.edit_outlined,
                                'DELETE' => Icons.delete_outline,
                                'EXPORT' => Icons.download_outlined,
                                _ => Icons.folder_outlined,
                              }),
                              title: Text(switch (a.action) {
                                'CREATE' => 'Titik ditambahkan',
                                'EDIT' => 'Titik diperbarui',
                                'DELETE' => 'Titik dihapus',
                                'EXPORT' => 'Data diekspor',
                                'PROJECT' => 'Proyek diubah',
                                _ => a.action,
                              }),
                              subtitle: Text(
                                '${a.description}\n${a.createdAt.toLocal()} · Proyek ${a.projectId ?? '—'}',
                              ),
                              isThreeLine: true,
                              onTap: a.surveyId == null || a.action == 'DELETE'
                                  ? null
                                  : () => _activityDetail(a),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                HistoryScreen(
                  snapshot: widget.snapshot,
                  onStart: widget.onStart,
                  onReload: widget.onReload,
                  loadDetail: widget.loadDetail,
                  onDelete: widget.onDelete,
                  onExport: _logExport,
                  elevationUnit: widget.elevationUnit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
