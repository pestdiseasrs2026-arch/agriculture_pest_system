import 'package:firebase_auth/firebase_auth.dart';

abstract final class PasswordPolicy {
  static const minimumLength = 12;

  static List<String> violations(String value) {
    final failures = <String>[];
    if (value.length < minimumLength) failures.add('Use at least 12 characters');
    if (!RegExp(r'[A-Z]').hasMatch(value)) failures.add('Add an uppercase letter');
    if (!RegExp(r'[a-z]').hasMatch(value)) failures.add('Add a lowercase letter');
    if (!RegExp(r'[0-9]').hasMatch(value)) failures.add('Add a number');
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(value)) failures.add('Add a symbol');
    return failures;
  }

  static String? validate(String? value) {
    final failures = violations(value ?? '');
    return failures.isEmpty ? null : failures.first;
  }
}

String accessibleAuthMessage(Object error) {
  if (error is! FirebaseAuthException) {
    return 'Authentication could not be completed. Please try again.';
  }
  return switch (error.code) {
    'invalid-credential' || 'wrong-password' || 'user-not-found' =>
      'The email or password is incorrect.',
    'invalid-email' => 'Enter a valid email address.',
    'email-already-in-use' => 'An account already uses this email address.',
    'weak-password' => 'Choose a stronger password.',
    'too-many-requests' => 'Too many attempts. Wait a moment and try again.',
    'network-request-failed' => 'Check your internet connection and try again.',
    'requires-recent-login' => 'For security, sign in again before continuing.',
    _ => 'Authentication could not be completed. Please try again.',
  };
}

