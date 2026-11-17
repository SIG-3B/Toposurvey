import 'package:flutter/material.dart';

import '../models/activity_log.dart';
import '../models/survey.dart';
import '../services/local_database_service.dart';

class DataSurveyScreen extends StatefulWidget {
  const DataSurveyScreen({
    super.key,
    required this.surveys,
    required this.database,
    required this.onReload,
    required this.onAdd,
  });
  final List<Survey> surveys;
  final LocalDatabaseService? database;
  final VoidCallback onReload;
  final VoidCallback onAdd;

  @override
  State<DataSurveyScreen> createState() => _DataSurveyScreenState();
}

class _DataSurveyScreenState extends State<DataSurveyScreen> {
  final _search = TextEditingController();
  int? _project;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _edit(Survey s) async {
    final code = TextEditingController(text: s.pointCode);
    final name = TextEditingController(text: s.pointName);
    final notes = TextEditingController(text: s.notes);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit metadata titik'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              maxLength: 35,
              decoration: const InputDecoration(labelText: 'Kode titik'),
            ),
            TextField(
              controller: name,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Nama titik'),
            ),
            TextField(
              controller: notes,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Catatan lapangan'),
            ),
            const Text('Koordinat dan data GPS tidak dapat diedit.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (save != true || !mounted) return;
    try {
      await widget.database?.updateSurveyMetadata(
        s.id,
        pointCode: code.text,
        pointName: name.text,
        notes: notes.text,
      );
      widget.onReload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Metadata titik diperbarui.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _delete(Survey s) async {
    if (await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('Hapus ${s.pointCode}?'),
            content: const Text('Data ini tidak dapat dikembalikan.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Hapus'),
              ),
            ],
          ),
        ) !=
        true) {
      return;
    }
    try {
      await widget.database?.deleteSurvey(s.id);
      widget.onReload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _saveProject([SurveyProject? project]) async {
    final name = TextEditingController(text: project?.name ?? '');
    if (await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(project == null ? 'Proyek baru' : 'Edit proyek'),
            content: TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nama proyek'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Simpan'),
              ),
            ],
          ),
        ) !=
        true) {
      return;
    }
    try {
      await widget.database?.saveProject(name.text, id: project?.id);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _deleteProject(SurveyProject project) async {
    if (await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('Hapus ${project.name}?'),
            content: const Text(
              'Proyek hanya dapat dihapus jika tidak memiliki titik, dan setidaknya satu proyek harus tersisa.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Hapus'),
              ),
            ],
          ),
        ) !=
        true) {
      return;
    }
    try {
      await widget.database?.deleteProject(project.id);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _manageProjects() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kelola proyek'),
        content: SizedBox(
          width: 420,
          child: FutureBuilder<List<SurveyProject>>(
            future: widget.database?.loadProjects(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(
                shrinkWrap: true,
                children: (snapshot.data ?? const <SurveyProject>[])
                    .map(
                      (project) => ListTile(
                        title: Text(project.name),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) {
                            Navigator.pop(dialogContext);
                            if (action == 'edit') {
                              _saveProject(project);
                            } else {
                              _deleteProject(project);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Hapus'),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.toLowerCase();
    final rows = widget.surveys
        .where(
          (s) =>
              (_project == null || _project == s.projectId) &&
              '${s.pointCode} ${s.pointName} ${s.notes}'.toLowerCase().contains(
                q,
              ),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${rows.length} dari ${widget.surveys.length} titik tersimpan',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (widget.database != null)
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _manageProjects,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Kelola proyek'),
              ),
              TextButton.icon(
                onPressed: () => _saveProject(),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Proyek baru'),
              ),
            ],
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Cari kode, nama, atau catatan',
            border: OutlineInputBorder(),
          ),
        ),
        FutureBuilder<List<SurveyProject>>(
          future: widget.database?.loadProjects(),
          builder: (context, snapshot) {
            final projects = snapshot.data ?? const <SurveyProject>[];
            return DropdownButtonFormField<int?>(
              initialValue: _project,
              decoration: const InputDecoration(labelText: 'Proyek'),
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
              onChanged: (v) => setState(() => _project = v),
            );
          },
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: widget.onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Tambah titik melalui GPS'),
        ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text('Belum ada titik yang cocok.'),
          ),
        ...rows.map(
          (s) => Card(
            child: ListTile(
              title: Text('${s.pointCode} · ${s.pointName}'),
              subtitle: Text(
                '${s.measurement.latitude.toStringAsFixed(6)}, ${s.measurement.longitude.toStringAsFixed(6)}\nElevasi ${s.measurement.elevation.toStringAsFixed(1)} m · Akurasi ±${s.horizontalAccuracy?.toStringAsFixed(1) ?? '—'} m\nFix ${s.fixTime?.toLocal()} · ${s.provider} · ${s.quality}${s.notes.isEmpty ? '' : '\n${s.notes}'}',
              ),
              isThreeLine: true,
              onTap: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text('${s.pointCode} · ${s.pointName}'),
                  content: Text(
                    'Latitude: ${s.measurement.latitude}\nLongitude: ${s.measurement.longitude}\nElevasi: ${s.measurement.elevation} m\nAkurasi horizontal: ${s.horizontalAccuracy ?? '—'}\nAkurasi vertikal: ${s.verticalAccuracy ?? '—'}\nWaktu GPS: ${s.fixTime?.toLocal()}\nWaktu simpan: ${s.createdAt.toLocal()}\nSumber: ${s.source}\nKualitas: ${s.quality}\nProyek: ${s.projectId}\nCatatan: ${s.notes}',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Tutup'),
                    ),
                  ],
                ),
              ),
              trailing: widget.database == null
                  ? null
                  : PopupMenuButton<String>(
                      onSelected: (v) => v == 'edit' ? _edit(s) : _delete(s),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit metadata'),
                        ),
                        PopupMenuItem(value: 'delete', child: Text('Hapus')),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
