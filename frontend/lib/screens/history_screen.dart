import 'package:flutter/material.dart';

import '../models/survey.dart';
import '../services/api_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.snapshot,
    required this.onStart,
    required this.onReload,
    this.loadDetail,
    this.onDelete,
  });

  final AsyncSnapshot<List<Survey>> snapshot;
  final VoidCallback onStart;
  final VoidCallback onReload;
  final Future<Survey> Function(int)? loadDetail;
  final Future<void> Function(int)? onDelete;

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
      builder: (context) => FutureBuilder<Survey>(
        future: loadDetail == null
            ? null
            : (detail ??= Future.sync(() => loadDetail(survey.id))),
        builder: (context, snapshot) => AlertDialog(
          scrollable: true,
          title: Text('Survei #${survey.id}'),
          content: switch (snapshot) {
            AsyncSnapshot(connectionState: ConnectionState.waiting) =>
              const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Memuat detail survei',
                ),
              ),
            AsyncSnapshot(error: ApiException(:final message)) => Text(message),
            AsyncSnapshot(hasError: true) => const Text(
              'Detail survei tidak dapat dimuat. Coba buka lagi.',
            ),
            _ => _detailContent(snapshot.data ?? survey),
          },
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ],
        ),
      ),
    );
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
        Text('Ketinggian: ${data.elevation.toStringAsFixed(1)} m'),
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

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
              'Ketinggian ${data.elevation.toStringAsFixed(1)} m\n'
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                ),
        );
      },
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
