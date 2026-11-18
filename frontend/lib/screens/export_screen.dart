import 'package:flutter/material.dart';

import '../models/activity_log.dart';
import '../models/survey.dart';
import '../services/local_database_service.dart';
import '../services/survey_exporter.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({
    super.key,
    required this.surveys,
    required this.database,
  });

  final List<Survey> surveys;
  final LocalDatabaseService? database;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final _exporter = const SurveyExporter();
  late Future<List<SurveyProject>> _projects;
  int? _projectId;
  DateTimeRange? _range;
  SurveyExportFormat _format = SurveyExportFormat.csv;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _projects = widget.database?.loadProjects() ?? Future.value(const []);
  }

  Future<void> _chooseDates() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(today.year + 1),
      initialDateRange: _range,
      helpText: 'Pilih rentang tanggal pengukuran',
      saveText: 'Terapkan',
    );
    if (range != null && mounted) setState(() => _range = range);
  }

  Future<void> _export(
    List<Survey> surveys,
    List<SurveyProject> projects,
  ) async {
    if (_busy || surveys.isEmpty) return;
    setState(() => _busy = true);
    try {
      final names = {for (final project in projects) project.id: project.name};
      final projectName = _projectId == null
          ? 'Semua proyek'
          : names[_projectId] ?? 'Proyek';
      final destination = await _exporter.save(
        surveys: surveys,
        format: _format,
        projectName: projectName,
        projectNames: names,
      );
      if (destination == null || !mounted) return;
      await widget.database?.logExport(
        _projectId,
        surveys.length,
        format: _format.label,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('${_format.label} tersimpan: $destination')),
        );
    } on SurveyExportException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Ekspor gagal. Periksa penyimpanan lalu coba lagi.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SurveyProject>>(
    future: _projects,
    builder: (context, snapshot) {
      final projects = snapshot.data ?? const <SurveyProject>[];
      final filtered = widget.surveys.where((survey) {
        if (_projectId != null && survey.projectId != _projectId) return false;
        if (_range == null) return true;
        final date = DateUtils.dateOnly(survey.createdAt.toLocal());
        return !date.isBefore(DateUtils.dateOnly(_range!.start)) &&
            !date.isAfter(DateUtils.dateOnly(_range!.end));
      }).toList();
      final rangeLabel = _range == null
          ? 'Semua tanggal'
          : '${_date(_range!.start)} – ${_date(_range!.end)}';

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Ekspor data survei',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Pilih cakupan dan format. File dibuat dari data lokal yang tersimpan.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<int?>(
                    initialValue: _projectId,
                    decoration: const InputDecoration(labelText: 'Proyek'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Semua proyek'),
                      ),
                      ...projects.map(
                        (project) => DropdownMenuItem<int?>(
                          value: project.id,
                          child: Text(project.name),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _projectId = value),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _chooseDates,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(rangeLabel),
                  ),
                  if (_range != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(() => _range = null),
                        child: const Text('Hapus rentang tanggal'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<SurveyExportFormat>(
                    initialValue: _format,
                    decoration: const InputDecoration(labelText: 'Format file'),
                    items: SurveyExportFormat.values
                        .map(
                          (format) => DropdownMenuItem(
                            value: format,
                            child: Text(format.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _format = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('${filtered.length} titik akan diekspor'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy || filtered.isEmpty
                        ? null
                        : () => _export(filtered, projects),
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_alt_outlined),
                    label: Text(_busy ? 'Membuat file…' : 'Ekspor file'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Privasi data'),
            subtitle: Text(
              'Data tetap tersimpan lokal. File hanya disimpan setelah kamu memilih lokasi tujuan.',
            ),
          ),
        ],
      );
    },
  );

  String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
