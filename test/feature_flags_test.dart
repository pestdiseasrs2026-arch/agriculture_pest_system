import 'package:agriculture_pest_system/core/config/feature_flags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production kill switches have availability-safe defaults', () {
    final flags = FeatureFlags.instance;
    expect(flags.maintenanceMode, isFalse);
    expect(flags.aiDetectionEnabled, isTrue);
    expect(flags.uploadsEnabled, isTrue);
    expect(flags.maintenanceMessage, isNotEmpty);
    expect(flags.minimumSupportedVersion, '1.0.0');
  });
}
