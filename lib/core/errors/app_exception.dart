import 'package:firebase_core/firebase_core.dart';

sealed class AppException implements Exception {
  final String message;
  final Object? cause;

  const AppException(this.message, [this.cause]);

  factory AppException.from(Object error) {
    if (error is FirebaseException) {
      return DataAccessException(switch (error.code) {
        'permission-denied' => 'You do not have permission to view this data.',
        'unavailable' => 'The service is temporarily unavailable.',
        'deadline-exceeded' => 'The request took too long. Please retry.',
        _ => error.message ?? 'Firebase could not complete the request.',
      }, error);
    }
    return DataAccessException(
      'Something went wrong while loading data.',
      error,
    );
  }

  @override
  String toString() => message;
}

final class DataAccessException extends AppException {
  const DataAccessException(super.message, [super.cause]);
}
