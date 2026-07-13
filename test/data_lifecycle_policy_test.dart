import 'package:agriculture_pest_system/core/repositories/data_lifecycle_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('privacy lifecycle keeps explicit grace and retention periods', () {
    expect(DataLifecyclePolicy.deletionGracePeriod, const Duration(days: 7));
    expect(DataLifecyclePolicy.diagnosticRetention, const Duration(days: 90));
    expect(DataLifecyclePolicy.auditLogRetention, const Duration(days: 365));
  });
}
