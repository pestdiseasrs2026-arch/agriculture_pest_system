import 'package:agriculture_pest_system/core/logging/diagnostic_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diagnostic events remove personal and secret attributes', () {
    final event = DiagnosticEvent(
      name: 'report_generated',
      category: 'reports',
      outcome: DiagnosticOutcome.success,
      attributes: {
        'email': 'farmer@example.com',
        'userId': 'private-id',
        'apiToken': 'secret',
        'format': 'pdf',
        'recordCount': 12,
      },
    );

    expect(event.attributes, {'format': 'pdf', 'recordCount': 12});
    expect(event.toJson()['outcome'], 'success');
  });

  test('diagnostic events discard complex and oversized values', () {
    final event = DiagnosticEvent(
      name: 'sync',
      category: 'data',
      outcome: DiagnosticOutcome.failure,
      attributes: {
        'payload': {'private': true},
        'message': 'x' * 81,
        'retry': true,
      },
    );

    expect(event.attributes, {'retry': true});
  });
}
