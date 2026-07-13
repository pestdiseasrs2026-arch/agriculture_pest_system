import 'dart:async';

import 'package:agriculture_pest_system/core/errors/app_exception.dart';
import 'package:agriculture_pest_system/core/network/resilience.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('timeout gives a recoverable data-access message', () async {
    await expectLater(
      Resilience.withTimeout(
        Completer<int>().future,
        timeout: const Duration(milliseconds: 1),
      ),
      throwsA(
        isA<DataAccessException>().having(
          (error) => error.message,
          'message',
          contains('retry'),
        ),
      ),
    );
  });

  test('stream reconnects after an offline failure', () async {
    var connections = 0;
    Stream<int> source() {
      connections++;
      return connections == 1
          ? Stream<int>.error(StateError('offline'))
          : Stream<int>.value(42);
    }

    expect(
      await Resilience.reconnecting(source, retryDelay: Duration.zero).single,
      42,
    );
    expect(connections, 2);
  });

  test('stream exposes a typed error after retry exhaustion', () async {
    await expectLater(
      Resilience.reconnecting<int>(
        () => Stream<int>.error(StateError('offline')),
        maxRetries: 1,
        retryDelay: Duration.zero,
      ),
      emitsError(isA<DataAccessException>()),
    );
  });
}
