import 'package:edupro/utils/auth_input_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reauthentication passes the exact password to Firebase', () {
    for (final password in ['  synthetic secret  ', 'á\tsecreto\n', '      ']) {
      final credential = exactPasswordCredential(
        email: ' synthetic@example.invalid ',
        password: password,
      );
      final serialized = credential.asMap();
      expect(serialized['secret'], password);
      expect(serialized['email'], 'synthetic@example.invalid');
      expect(credential.providerId, 'password');
    }
  });

  test('empty password is rejected without embedding it in an error', () {
    expect(
      () => exactPasswordCredential(email: 'synthetic@example.invalid', password: ''),
      throwsArgumentError,
    );
  });
}
