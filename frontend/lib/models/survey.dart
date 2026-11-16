class SurveyMeasurement {
  const SurveyMeasurement({
    required this.latitude,
    required this.longitude,
    required this.elevation,
  });

  final double latitude;
  final double longitude;
  final double elevation;

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
    return Survey(id: id, measurement: measurement, createdAt: createdAt);
  }

  final int id;
  final SurveyMeasurement measurement;
  final DateTime createdAt;
}
