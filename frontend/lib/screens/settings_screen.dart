import 'package:flutter/material.dart';

import '../models/survey_preferences.dart';
import '../services/location_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.location,
    required this.preferences,
    required this.onSave,
  });

  final LocationService location;
  final SurveyPreferences preferences;
  final Future<void> Function(SurveyPreferences) onSave;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SurveyPreferences _preferences;
  late Future<LocationAccess> _access;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _preferences = widget.preferences;
    _access = widget.location.checkAccess();
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences != widget.preferences) {
      _preferences = widget.preferences;
    }
  }

  Future<void> _save(SurveyPreferences value) async {
    setState(() => _saving = true);
    try {
      await widget.onSave(value);
      if (mounted) setState(() => _preferences = value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pengaturan tidak dapat disimpan.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshAccess({bool request = false}) async {
    final access = widget.location.checkAccess(requestPermission: request);
    setState(() => _access = access);
    final result = await access;
    if (!mounted) return;
    if (result == LocationAccess.deniedForever) {
      await widget.location.openAppSettings();
    } else if (result == LocationAccess.disabled) {
      await widget.location.openLocationSettings();
    }
    if (mounted) setState(() => _access = widget.location.checkAccess());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Pengaturan', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Preferensi ini berlaku untuk tampilan dan penandaan kualitas pengukuran berikutnya.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.speed_outlined),
                title: const Text('Ambang akurasi horizontal'),
                subtitle: Text(
                  '${_preferences.accuracyThresholdMeters.round()} meter · di atas nilai ini titik ditandai kualitas rendah',
                ),
              ),
              Slider(
                min: 1,
                max: 100,
                divisions: 99,
                label: '${_preferences.accuracyThresholdMeters.round()} m',
                value: _preferences.accuracyThresholdMeters,
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _preferences = _preferences.copyWith(
                          accuracyThresholdMeters: value,
                        );
                      }),
                onChangeEnd: (value) => _save(
                  _preferences.copyWith(accuracyThresholdMeters: value),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.height_outlined),
                title: const Text('Satuan elevasi'),
                trailing: DropdownButton<ElevationUnit>(
                  value: _preferences.elevationUnit,
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            _save(_preferences.copyWith(elevationUnit: value));
                          }
                        },
                  items: ElevationUnit.values
                      .map(
                        (unit) => DropdownMenuItem(
                          value: unit,
                          child: Text(unit.label),
                        ),
                      )
                      .toList(),
                ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.map_outlined),
                title: const Text('Peta dasar OpenStreetMap'),
                subtitle: const Text(
                  'Memerlukan internet. Marker dan data tetap tersedia saat tile tidak termuat.',
                ),
                value: _preferences.showOpenStreetMap,
                onChanged: _saving
                    ? null
                    : (value) => _save(
                        _preferences.copyWith(showOpenStreetMap: value),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: FutureBuilder<LocationAccess>(
            future: _access,
            builder: (context, snapshot) {
              final access = snapshot.data;
              return ListTile(
                leading: const Icon(Icons.location_searching_outlined),
                title: const Text('Izin dan layanan lokasi'),
                subtitle: Text(access?.label ?? 'Memeriksa status lokasi…'),
                trailing: TextButton(
                  onPressed: () => _refreshAccess(request: true),
                  child: const Text('Periksa / atur'),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: const [
              ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Privasi dan penyimpanan'),
                subtitle: Text(
                  'Titik dan riwayat disimpan di perangkat. Data hanya keluar saat kamu memilih ekspor atau berbagi file.',
                ),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Tentang TopoSurvey'),
                subtitle: Text(
                  'Elevasi ponsel mengacu pada elipsoid WGS 84 jika tersedia. Akurasi GPS ponsel bukan jaminan ketelitian survei geodesi.',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
