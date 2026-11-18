import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;

import '../models/survey.dart';
import 'survey_export_platform.dart';

enum SurveyExportFormat {
  csv('CSV', 'csv', 'text/csv'),
  pdf('PDF', 'pdf', 'application/pdf'),
  geoJson('GeoJSON', 'geojson', 'application/geo+json');

  const SurveyExportFormat(this.label, this.extension, this.mimeType);

  final String label;
  final String extension;
  final String mimeType;
}

class SurveyExporter {
  const SurveyExporter({this.platform = const SurveyExportPlatform()});

  final SurveyExportPlatform platform;

  String buildCsv(
    List<Survey> surveys, {
    Map<int, String> projectNames = const {},
  }) {
    const columns = [
      'id',
      'project_id',
      'project_name',
      'point_code',
      'point_name',
      'latitude',
      'longitude',
      'altitude_ellipsoid_m',
      'altitude_msl_m',
      'horizontal_accuracy_m',
      'vertical_accuracy_m',
      'fix_time_utc',
      'recorded_at_utc',
      'provider',
      'source',
      'fix_age_ms_at_capture',
      'quality_flag',
      'notes',
    ];
    final rows = <String>[columns.join(',')];
    for (final survey in surveys) {
      final measurement = survey.measurement;
      final fixTime = (survey.fixTime ?? survey.createdAt).toUtc();
      final fixAgeMs = survey.createdAt.difference(fixTime).inMilliseconds;
      rows.add(
        [
          survey.id.toString(),
          survey.projectId.toString(),
          _csvText(projectNames[survey.projectId] ?? ''),
          _csvText(survey.pointCode),
          _csvText(survey.pointName),
          measurement.latitude.toString(),
          measurement.longitude.toString(),
          measurement.elevation.toString(),
          '',
          survey.horizontalAccuracy?.toString() ?? '',
          survey.verticalAccuracy?.toString() ?? '',
          fixTime.toIso8601String(),
          survey.createdAt.toUtc().toIso8601String(),
          _csvText(survey.provider),
          _csvText(survey.source),
          fixAgeMs >= 0 ? fixAgeMs.toString() : '',
          _csvText(survey.quality),
          _csvText(survey.notes),
        ].join(','),
      );
    }
    return '${rows.join('\r\n')}\r\n';
  }

  Future<List<int>> buildPdf(
    List<Survey> surveys, {
    required String projectName,
    Map<int, String> projectNames = const {},
  }) async {
    final regularFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
    );
    final document = pw.Document();
    final ordered = [...surveys]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final first = ordered.isEmpty ? null : ordered.first.createdAt.toLocal();
    final last = ordered.isEmpty ? null : ordered.last.createdAt.toLocal();
    final lowQuality = surveys
        .where((survey) => survey.quality == 'LOW_QUALITY')
        .length;
    final accepted = surveys.length - lowQuality;
    document.addPage(
      pw.MultiPage(
        maxPages: 1000,
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            'Laporan Survei Topografi',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Proyek: $projectName'),
          pw.Text(
            'Tanggal cetak: ${DateTime.now().toLocal().toIso8601String()}',
          ),
          pw.Text(
            'Jumlah titik: ${surveys.length}  |  Diterima: $accepted  |  Kualitas rendah: $lowQuality',
          ),
          if (first != null && last != null)
            pw.Text(
              'Periode pengukuran: ${first.toIso8601String()} sampai ${last.toIso8601String()}',
            ),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Kode',
              'Proyek',
              'Nama titik',
              'Latitude',
              'Longitude',
              'Elevasi ellipsoid (m)',
              'Akurasi H (m)',
              'Akurasi V (m)',
              'Waktu fix (UTC)',
              'Kualitas',
            ],
            data: surveys.map((survey) {
              final measurement = survey.measurement;
              return [
                survey.pointCode,
                projectNames[survey.projectId] ?? projectName,
                survey.pointName,
                measurement.latitude.toStringAsFixed(7),
                measurement.longitude.toStringAsFixed(7),
                measurement.elevation.toStringAsFixed(2),
                survey.horizontalAccuracy?.toStringAsFixed(2) ??
                    'Tidak tersedia',
                survey.verticalAccuracy?.toStringAsFixed(2) ?? 'Tidak tersedia',
                (survey.fixTime ?? survey.createdAt).toUtc().toIso8601String(),
                survey.quality,
              ];
            }).toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 8,
            ),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellAlignment: pw.Alignment.centerLeft,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green100),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 5,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Keterangan: elevasi adalah tinggi ellipsoid WGS 84, bukan tinggi muka laut. GPS ponsel memiliki keterbatasan; nilai akurasi merupakan estimasi provider. Kolom kosong berarti data tidak tersedia.',
          ),
        ],
      ),
    );
    return document.save();
  }

  Future<String?> save({
    required List<Survey> surveys,
    required SurveyExportFormat format,
    required String projectName,
    Map<int, String> projectNames = const {},
  }) async {
    if (surveys.isEmpty) {
      throw const SurveyExportException('Tidak ada titik untuk diekspor.');
    }
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[-:.]'), '')
        .replaceAll('Z', '');
    final fileName = 'toposurvey_$stamp.${format.extension}';
    final Object content = switch (format) {
      SurveyExportFormat.csv => buildCsv(surveys, projectNames: projectNames),
      SurveyExportFormat.pdf => await buildPdf(
        surveys,
        projectName: projectName,
        projectNames: projectNames,
      ),
      SurveyExportFormat.geoJson => surveysToGeoJson(surveys),
    };
    try {
      return await platform.saveFile(
        fileName: fileName,
        mimeType: format.mimeType,
        content: content,
      );
    } catch (error) {
      throw SurveyExportException('Gagal mengekspor ${format.label}: $error');
    }
  }
}

String _csvText(String value) {
  var safe = value;
  if (safe.trimLeft().startsWith(RegExp(r'[=+@-]'))) safe = "'$safe";
  if (safe.contains(RegExp(r'[",\r\n]'))) {
    safe = '"${safe.replaceAll('"', '""')}"';
  }
  return safe;
}

class SurveyExportException implements Exception {
  const SurveyExportException(this.message);
  final String message;
  @override
  String toString() => message;
}
