import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/survey.dart';

class GeoJsonExportException implements Exception {
  const GeoJsonExportException(this.message);

  final String message;
}

class GeoJsonExporter {
  const GeoJsonExporter({MethodChannel? channel})
    : _channel = channel ?? defaultChannel;

  static const defaultChannel = MethodChannel(
    'com.toposurvey.toposurvey/geojson',
  );

  final MethodChannel _channel;

  String _defaultFileName(List<Survey> surveys) => surveys.length == 1
      ? 'toposurvey_${surveys.single.id}.geojson'
      : 'toposurvey_export.geojson';

  String _normalizeFileName(String fileName) {
    final sanitized = p.basename(fileName).trim();
    final base = sanitized.isEmpty ? 'toposurvey_export.geojson' : sanitized;
    return base.endsWith('.geojson') ? base : '$base.geojson';
  }

  Future<String> saveGeoJson({
    required List<Survey> surveys,
    String? fileName,
  }) async {
    if (surveys.isEmpty) {
      throw const GeoJsonExportException(
        'Belum ada data survei untuk diekspor.',
      );
    }
    final content = surveysToGeoJson(surveys);
    final name = _normalizeFileName(fileName ?? _defaultFileName(surveys));

    try {
      final savedLocation = await _channel.invokeMethod<String>('saveGeoJson', {
        'fileName': name,
        'content': content,
      });
      if (savedLocation != null && savedLocation.isNotEmpty) {
        return savedLocation;
      }
    } on MissingPluginException {
      // Fall back to local file directory on non-Android platforms.
    } on PlatformException catch (error) {
      throw GeoJsonExportException(
        error.message ?? 'Gagal menyimpan file GeoJSON ke perangkat.',
      );
    }

    if (kIsWeb) {
      throw const GeoJsonExportException(
        'Unduh file langsung belum didukung di web. Gunakan tombol Salin.',
      );
    }
    try {
      final directory =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final file = File(p.join(directory.path, name));
      await file.writeAsString(content, flush: true);
      return file.path;
    } on FileSystemException {
      throw const GeoJsonExportException(
        'Gagal menyimpan file GeoJSON ke penyimpanan lokal.',
      );
    }
  }

  Future<void> shareGeoJson({
    required List<Survey> surveys,
    String? fileName,
  }) async {
    if (surveys.isEmpty) {
      throw const GeoJsonExportException(
        'Belum ada data survei untuk diekspor.',
      );
    }
    final content = surveysToGeoJson(surveys);
    final name = _normalizeFileName(fileName ?? _defaultFileName(surveys));

    try {
      await _channel.invokeMethod<void>('shareGeoJson', {
        'fileName': name,
        'content': content,
      });
    } on MissingPluginException {
      throw const GeoJsonExportException(
        'Fitur bagikan belum tersedia di platform ini. Gunakan Unduh atau Salin.',
      );
    } on PlatformException catch (error) {
      throw GeoJsonExportException(
        error.message ?? 'Gagal membagikan file GeoJSON.',
      );
    }
  }

  Future<void> copyGeoJson(List<Survey> surveys) async {
    if (surveys.isEmpty) {
      throw const GeoJsonExportException(
        'Belum ada data survei untuk diekspor.',
      );
    }
    await Clipboard.setData(ClipboardData(text: surveysToGeoJson(surveys)));
  }
}
