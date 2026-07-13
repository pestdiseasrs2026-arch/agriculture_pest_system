import 'dart:async';

import 'package:agriculture_pest_system/core/errors/app_exception.dart';

abstract final class Resilience {
  static Future<T> withTimeout<T>(
    Future<T> operation, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      return await operation.timeout(timeout);
    } on TimeoutException catch (error) {
      throw DataAccessException(
        'The request timed out. Check your connection and retry.',
        error,
      );
    }
  }

  static Stream<T> reconnecting<T>(
    Stream<T> Function() source, {
    int maxRetries = 2,
    Duration retryDelay = const Duration(seconds: 1),
  }) async* {
    var attempt = 0;
    while (true) {
      try {
        await for (final value in source()) {
          attempt = 0;
          yield value;
        }
        return;
      } catch (error, stackTrace) {
        if (attempt >= maxRetries) {
          Error.throwWithStackTrace(AppException.from(error), stackTrace);
        }
        attempt++;
        await Future<void>.delayed(retryDelay);
      }
    }
  }
}
