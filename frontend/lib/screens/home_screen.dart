import 'package:flutter/material.dart';

import '../services/location_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.location,
    required this.surveyCount,
    required this.onStart,
    required this.onHistory,
    required this.onReload,
    this.checkBackend,
    this.historyUnavailable = false,
    this.historyLoading = false,
  });

  final LocationService location;
  final int? surveyCount;
  final VoidCallback onStart;
  final VoidCallback onHistory;
  final VoidCallback onReload;
  final Future<void> Function()? checkBackend;
  final bool historyUnavailable;
  final bool historyLoading;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<LocationAccess> _access;
  Future<void>? _backendCheck;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _access = widget.location.checkAccess();
    _backendCheck = _checkBackend();
    _lifecycle = AppLifecycleListener(onResume: _refreshAccess);
  }

  Future<void>? _checkBackend() {
    final check = widget.checkBackend;
    return check == null ? null : Future.sync(check);
  }

  void _reload() {
    final check = _checkBackend();
    setState(() {
      _backendCheck = check;
    });
    widget.onReload();
  }

  void _refreshAccess() {
    final access = widget.location.checkAccess();
    setState(() {
      _access = access;
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final count = widget.surveyCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Survei topografi', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Ukur koordinat dan ketinggian titik menggunakan lokasi ponsel.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FutureBuilder<LocationAccess>(
            future: _access,
            builder: (context, snapshot) {
              final access = snapshot.data;
              final label = switch (snapshot.connectionState) {
                ConnectionState.waiting => 'Memeriksa GPS…',
                _ => access?.label ?? LocationAccess.unavailable.label,
              };
              return ListTile(
                tileColor: colors.primaryContainer,
                textColor: colors.onPrimaryContainer,
                iconColor: colors.onPrimaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  access == LocationAccess.ready
                      ? Icons.gps_fixed
                      : Icons.gps_not_fixed,
                ),
                title: const Text('Status GPS'),
                subtitle: Text(label),
              );
            },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: widget.onStart,
            icon: const Icon(Icons.my_location_outlined),
            label: const Text('Mulai Survei'),
          ),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),
          Text('Data survei tersimpan', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            switch (count) {
              null when widget.historyLoading => 'Memuat jumlah survei…',
              null => 'Jumlah survei belum tersedia.',
              0 => 'Belum ada survei tersimpan.',
              _ => '$count survei tersimpan',
            },
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (_backendCheck != null || widget.historyUnavailable)
            FutureBuilder<void>(
              future: _backendCheck,
              builder: (context, snapshot) {
                if (widget.historyUnavailable || snapshot.hasError) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _reload,
                      child: const Text('Data belum tersedia. Coba lagi'),
                    ),
                  );
                }
                return Text(
                  snapshot.connectionState == ConnectionState.waiting
                      ? 'Memeriksa server…'
                      : 'Server terhubung',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                );
              },
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.onHistory,
              icon: const Icon(Icons.history),
              label: const Text('Lihat Riwayat'),
            ),
          ),
        ],
      ),
    );
  }
}
