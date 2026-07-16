import 'package:agriculture_pest_system/features/auth_security/domain/auth_security.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('password policy requires length and character diversity', () {
    expect(PasswordPolicy.validate('short'), isNotNull);
    expect(PasswordPolicy.validate('longbutnouppercase1!'), isNotNull);
    expect(PasswordPolicy.validate('StrongPassword1!'), isNull);
  });

  test('authentication errors are accessible and do not expose internals', () {
    expect(
      accessibleAuthMessage(FirebaseAuthException(code: 'user-not-found')),
      'The email or password is incorrect.',
    );
    expect(
      accessibleAuthMessage(FirebaseAuthException(code: 'requires-recent-login')),
      contains('sign in again'),
    );
  });
}

