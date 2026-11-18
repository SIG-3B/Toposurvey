import 'package:shared_preferences/shared_preferences.dart';

enum ElevationUnit {
  meters('Meter', 'm', 1),
  feet('Kaki', 'ft', 3.280839895);

  const ElevationUnit(this.label, this.symbol, this.multiplier);

  final String label;
  final String symbol;
  final double multiplier;

  double fromMeters(double value) => value * multiplier;
}

class SurveyPreferences {
  const SurveyPreferences({
    this.accuracyThresholdMeters = 10,
    this.elevationUnit = ElevationUnit.meters,
    this.showOpenStreetMap = true,
  });

  final double accuracyThresholdMeters;
  final ElevationUnit elevationUnit;
  final bool showOpenStreetMap;

  SurveyPreferences copyWith({
    double? accuracyThresholdMeters,
    ElevationUnit? elevationUnit,
    bool? showOpenStreetMap,
  }) => SurveyPreferences(
    accuracyThresholdMeters:
        accuracyThresholdMeters ?? this.accuracyThresholdMeters,
    elevationUnit: elevationUnit ?? this.elevationUnit,
    showOpenStreetMap: showOpenStreetMap ?? this.showOpenStreetMap,
  );
}

class SurveyPreferencesStore {
  static const _accuracyKey = 'toposurvey.settings.accuracyThresholdMeters';
  static const _unitKey = 'toposurvey.settings.elevationUnit';
  static const _basemapKey = 'toposurvey.settings.showOpenStreetMap';

  Future<SurveyPreferences> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final unit = ElevationUnit.values.firstWhere(
        (value) => value.name == preferences.getString(_unitKey),
        orElse: () => ElevationUnit.meters,
      );
      final threshold = preferences.getDouble(_accuracyKey) ?? 10;
      return SurveyPreferences(
        accuracyThresholdMeters: threshold.isFinite && threshold >= 1
            ? threshold.clamp(1, 100)
            : 10,
        elevationUnit: unit,
        showOpenStreetMap: preferences.getBool(_basemapKey) ?? true,
      );
    } catch (_) {
      return const SurveyPreferences();
    }
  }

  Future<void> save(SurveyPreferences value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_accuracyKey, value.accuracyThresholdMeters);
    await preferences.setString(_unitKey, value.elevationUnit.name);
    await preferences.setBool(_basemapKey, value.showOpenStreetMap);
  }
}
