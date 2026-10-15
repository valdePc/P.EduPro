import 'package:firebase_auth/firebase_auth.dart';

/// Email is an identifier; password whitespace is part of the credential.
AuthCredential exactPasswordCredential({
  required String email,
  required String password,
}) {
  if (password.isEmpty) {
    throw ArgumentError('La contrasena no puede estar vacia.');
  }
  return EmailAuthProvider.credential(email: email.trim(), password: password);
}
