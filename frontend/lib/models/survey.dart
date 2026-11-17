import 'dart:convert';

class SurveyMeasurement {
  const SurveyMeasurement({
    required this.latitude,
    required this.longitude,
    required this.elevation,
    this.horizontalAccuracy,
    this.verticalAccuracy,
    this.fixTime,
    this.provider = 'GPS',
    this.source = 'DEVICE',
    this.quality = 'ACCEPTED',
    this.pointCode = '',
    this.pointName = '',
    this.notes = '',
    this.projectId = 1,
  });

  final double latitude;
  final double longitude;
  final double elevation;
  final double? horizontalAccuracy;
  final double? verticalAccuracy;
  final DateTime? fixTime;
  final String provider;
  final String source;
  final String quality;
  final String pointCode;
  final String pointName;
  final String notes;
  final int projectId;

  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      elevation.isFinite;

  Map<String, double> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'elevation': elevation,
  };
}

class Survey {
  const Survey({
    required this.id,
    required this.measurement,
    required this.createdAt,
    this.pointCode = '',
    this.pointName = '',
    this.notes = '',
    this.horizontalAccuracy,
    this.verticalAccuracy,
    this.fixTime,
    this.provider = 'GPS',
    this.source = 'DEVICE',
    this.quality = 'ACCEPTED',
    this.projectId = 1,
  });

  factory Survey.fromJson(Map<String, Object?> json) {
    final id = json['id'] as int;
    final measurement = SurveyMeasurement(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      elevation: (json['elevation'] as num).toDouble(),
    );
    final createdAt = DateTime.parse(json['created_at'] as String);
    if (id <= 0 || !measurement.isValid || !createdAt.isUtc) {
      throw const FormatException('Invalid survey data');
    }
    return Survey(
      id: id,
      measurement: measurement,
      createdAt: createdAt,
      pointCode: json['point_code'] as String? ?? 'TP-$id',
      pointName: json['point_name'] as String? ?? 'Titik $id',
      notes: json['notes'] as String? ?? '',
      horizontalAccuracy: (json['horizontal_accuracy'] as num?)?.toDouble(),
      verticalAccuracy: (json['vertical_accuracy'] as num?)?.toDouble(),
      fixTime:
          DateTime.tryParse(json['fix_time'] as String? ?? '') ?? createdAt,
      provider: json['provider'] as String? ?? 'GPS',
      source: json['source'] as String? ?? 'DEVICE',
      quality: json['quality'] as String? ?? 'ACCEPTED',
      projectId: json['project_id'] as int? ?? 1,
    );
  }

  final int id;
  final SurveyMeasurement measurement;
  final DateTime createdAt;
  final String pointCode;
  final String pointName;
  final String notes;
  final double? horizontalAccuracy;
  final double? verticalAccuracy;
  final DateTime? fixTime;
  final String provider;
  final String source;
  final String quality;
  final int projectId;

  Survey copyWith({String? pointCode, String? pointName, String? notes}) =>
      Survey(
        id: id,
        measurement: measurement,
        createdAt: createdAt,
        pointCode: pointCode ?? this.pointCode,
        pointName: pointName ?? this.pointName,
        notes: notes ?? this.notes,
        horizontalAccuracy: horizontalAccuracy,
        verticalAccuracy: verticalAccuracy,
        fixTime: fixTime,
        provider: provider,
        source: source,
        quality: quality,
        projectId: projectId,
      );

  Map<String, Object?> toGeoJsonFeature() => {
    'type': 'Feature',
    'id': id,
    'geometry': {
      'type': 'Point',
      'coordinates': [
        measurement.longitude,
        measurement.latitude,
        measurement.elevation,
      ],
    },
    'properties': {
      'id': id,
      'point_code': pointCode,
      'point_name': pointName,
      'notes': notes,
      'latitude': measurement.latitude,
      'longitude': measurement.longitude,
      'elevation': measurement.elevation,
      'horizontal_accuracy_m': horizontalAccuracy,
      'vertical_accuracy_m': verticalAccuracy,
      'fix_time_utc': (fixTime ?? createdAt).toUtc().toIso8601String(),
      'provider': provider,
      'source': source,
      'quality': quality,
      'project_id': projectId,
      'created_at': createdAt.toUtc().toIso8601String(),
    },
  };
}

String surveysToGeoJson(List<Survey> surveys) =>
    const JsonEncoder.withIndent('  ').convert({
      'type': 'FeatureCollection',
      'features': surveys.map((survey) => survey.toGeoJsonFeature()).toList(),
    });
