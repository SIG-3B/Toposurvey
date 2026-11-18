import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toposurvey/models/survey.dart';
import 'package:toposurvey/services/survey_exporter.dart';

Survey _survey({String code = 'TP-01', String notes = 'Patok, utara'}) =>
    Survey.fromJson({
      'id': 1,
      'project_id': 2,
      'point_code': code,
      'point_name': 'Titik kontrol',
      'notes': notes,
      'latitude': -6.9,
      'longitude': 107.6,
      'elevation': 12.5,
      'horizontal_accuracy': 4.2,
      'vertical_accuracy': null,
      'fix_time': '2026-11-17T03:00:00.000Z',
      'created_at': '2026-11-17T03:01:00.000Z',
      'provider': 'GPS',
      'source': 'DEVICE',
      'quality': 'ACCEPTED',
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const exporter = SurveyExporter();

  test('CSV contains documented fields and escapes text safely', () {
    final csv = exporter.buildCsv(
      [_survey(notes: 'Patok, "utara"\nbaris dua')],
      projectNames: const {2: 'Kampus Utara'},
    );

    expect(csv, contains('altitude_ellipsoid_m,altitude_msl_m'));
    expect(csv, contains('Kampus Utara'));
    expect(csv, contains('"Patok, ""utara""\nbaris dua"'));
    expect(csv, contains('-6.9,107.6,12.5'));
    expect(csv, contains(',GPS,DEVICE,60000,ACCEPTED,'));
  });

  test('CSV neutralizes spreadsheet formulas in text columns', () {
    final csv = exporter.buildCsv([_survey(code: '=HYPERLINK("x")')]);
    expect(csv, contains("'=HYPERLINK("));
  });

  test('PDF exporter creates a readable PDF document', () async {
    final bytes = await exporter.buildPdf([_survey()], projectName: 'Kampus');
    expect(utf8.decode(bytes.take(4).toList()), '%PDF');
    expect(bytes.length, greaterThan(500));
  });
}
