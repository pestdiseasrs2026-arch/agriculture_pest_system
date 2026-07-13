import 'package:agriculture_pest_system/core/config/app_environment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('application environment always resolves to a known flavor', () {
    expect(AppFlavor.values, contains(AppEnvironment.flavor));
  });
}
