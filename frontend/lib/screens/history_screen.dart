import 'package:flutter/material.dart';

import '../models/survey.dart';
import '../models/survey_preferences.dart';
import '../services/api_service.dart';
import '../services/geojson_exporter.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.snapshot,
    required this.onStart,
    required this.onReload,
    this.loadDetail,
    this.onDelete,
    this.onExport,
    this.exporter = const GeoJsonExporter(),
    this.elevationUnit = ElevationUnit.meters,
  });

  final AsyncSnapshot<List<Survey>> snapshot;
  final VoidCallback onStart;
  final VoidCallback onReload;
  final Future<Survey> Function(int)? loadDetail;
  final Future<void> Function(int)? onDelete;
  final Future<void> Function(int)? onExport;
  final GeoJsonExporter exporter;
  final ElevationUnit elevationUnit;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int? _deletingId;

  Future<void> _confirmDelete(Survey survey) async {
    final onDelete = widget.onDelete;
    if (onDelete == null || _deletingId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('Hapus survei #${survey.id}?'),
        content: const Text('Data yang dihapus tidak dapat dikembalikan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingId = survey.id);
    try {
      await onDelete(survey.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              error is ApiException
                  ? 'Gagal menghapus. ${error.message}'
                  : 'Survei gagal dihapus. Coba lagi.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  void _showDetail(Survey survey) {
    final loadDetail = widget.loadDetail;
    Future<Survey>? detail;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => FutureBuilder<Survey>(
        future: loadDetail == null
            ? null
            : (detail ??= Future.sync(() => loadDetail(survey.id))),
        builder: (dialogContext, snapshot) {
          final target = snapshot.data ?? survey;
          final ready =
              snapshot.connectionState != ConnectionState.waiting &&
              !snapshot.hasError;
          return AlertDialog(
            scrollable: true,
            title: Text('Survei #${survey.id}'),
            content: switch (snapshot) {
              AsyncSnapshot(connectionState: ConnectionState.waiting) =>
                const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Memuat detail survei',
                  ),
                ),
              AsyncSnapshot(error: ApiException(:final message)) => Text(
                message,
              ),
              AsyncSnapshot(hasError: true) => const Text(
                'Detail survei tidak dapat dimuat. Coba buka lagi.',
              ),
              _ => _detailContent(target),
            },
            actions: [
              if (ready)
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _showExportDialog([
                      target,
                    ], title: 'Ekspor GeoJSON #${target.id}');
                  },
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Ekspor GeoJSON'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Tutup'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showExportDialog(
    List<Survey> surveys, {
    String title = 'Ekspor GeoJSON',
  }) async {
    final message = await showDialog<String>(
      context: context,
      builder: (context) => _ExportGeoJsonDialog(
        title: title,
        surveys: surveys,
        exporter: widget.exporter,
      ),
    );
    if (!mounted || message == null || message.isEmpty) return;
    await widget.onExport?.call(surveys.length);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _detailContent(Survey survey) {
    final data = survey.measurement;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Garis Lintang: ${data.latitude.toStringAsFixed(6)}°'),
        const SizedBox(height: 8),
        Text('Garis Bujur: ${data.longitude.toStringAsFixed(6)}°'),
        const SizedBox(height: 8),
        Text(
          'Ketinggian: ${widget.elevationUnit.fromMeters(data.elevation).toStringAsFixed(1)} ${widget.elevationUnit.symbol}',
        ),
        const SizedBox(height: 8),
        Text('Waktu tersimpan: ${_localTime(survey.createdAt)}'),
      ],
    );
  }

  String _localTime(DateTime timestamp) {
    final local = timestamp.toLocal();
    String pad(int number) => number.toString().padLeft(2, '0');
    return '${pad(local.day)}/${pad(local.month)}/${local.year} '
        '• ${pad(local.hour)}:${pad(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final surveys = snapshot.data;
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Memuat riwayat'),
      );
    }

    if (snapshot.hasError) {
      final error = snapshot.error;
      return _HistoryMessage(
        icon: Icons.error_outline,
        title: 'Riwayat tidak dapat dimuat',
        description: error is ApiException
            ? error.message
            : 'Coba muat kembali riwayat survei.',
        actionLabel: 'Coba lagi',
        onAction: widget.onReload,
      );
    }

    if (surveys == null || surveys.isEmpty) {
      return _HistoryMessage(
        icon: Icons.history,
        title: surveys == null ? 'Riwayat belum tersedia' : 'Belum ada survei',
        description: surveys == null
            ? 'Penyimpanan belum terhubung.'
            : 'Hasil survei yang disimpan akan tampil di sini.',
        actionLabel: 'Mulai Survei',
        onAction: widget.onStart,
      );
    }

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${surveys.length} survei tersimpan',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _showExportDialog(surveys),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Ekspor GeoJSON'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            itemCount: surveys.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final survey = surveys[index];
              final data = survey.measurement;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                title: Text('Survei #${survey.id}'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Lintang ${data.latitude.toStringAsFixed(6)}°\n'
                    'Bujur ${data.longitude.toStringAsFixed(6)}°\n'
                    'Ketinggian ${widget.elevationUnit.fromMeters(data.elevation).toStringAsFixed(1)} ${widget.elevationUnit.symbol}\n'
                    '${_localTime(survey.createdAt)}',
                  ),
                ),
                onTap: () => _showDetail(survey),
                trailing: widget.onDelete == null
                    ? null
                    : IconButton(
                        tooltip: 'Hapus survei #${survey.id}',
                        onPressed: _deletingId == null
                            ? () => _confirmDelete(survey)
                            : null,
                        icon: _deletingId == survey.id
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.delete_outline),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ExportGeoJsonDialog extends StatefulWidget {
  const _ExportGeoJsonDialog({
    required this.title,
    required this.surveys,
    required this.exporter,
  });

  final String title;
  final List<Survey> surveys;
  final GeoJsonExporter exporter;

  @override
  State<_ExportGeoJsonDialog> createState() => _ExportGeoJsonDialogState();
}

class _ExportGeoJsonDialogState extends State<_ExportGeoJsonDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _runAction(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await action();
      if (!mounted) return;
      Navigator.pop(context, result);
    } on GeoJsonExportException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Gagal mengekspor GeoJSON. Coba lagi.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final geoJson = surveysToGeoJson(widget.surveys);

    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.surveys.length} titik survei siap diekspor dalam '
              'format GeoJSON (FeatureCollection).',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    geoJson,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _runAction(() async {
                          final location = await widget.exporter.saveGeoJson(
                            surveys: widget.surveys,
                          );
                          return 'GeoJSON disimpan di: $location';
                        }),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Unduh (.geojson)'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _runAction(() async {
                          await widget.exporter.copyGeoJson(widget.surveys);
                          return 'GeoJSON disalin ke clipboard.';
                        }),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Salin'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _runAction(() async {
                          await widget.exporter.shareGeoJson(
                            surveys: widget.surveys,
                          );
                          return 'GeoJSON dibagikan.';
                        }),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Bagikan'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Icon(icon, size: 32, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 16),
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          description,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
        ),
      ],
    );
  }
}
