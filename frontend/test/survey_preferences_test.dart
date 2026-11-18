import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toposurvey/models/survey_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'settings persist accuracy threshold, units and basemap preference',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SurveyPreferencesStore();
      await store.save(
        const SurveyPreferences(
          accuracyThresholdMeters: 18,
          elevationUnit: ElevationUnit.feet,
          showOpenStreetMap: false,
        ),
      );

      final loaded = await store.load();
      expect(loaded.accuracyThresholdMeters, 18);
      expect(loaded.elevationUnit, ElevationUnit.feet);
      expect(loaded.showOpenStreetMap, isFalse);
    },
  );
}
