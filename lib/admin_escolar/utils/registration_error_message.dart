import 'package:firebase_core/firebase_core.dart';

/// Deliberately ignores provider messages: they may contain paths or input data.
String registrationErrorMessage(Object error) {
  final code = error is FirebaseException ? error.code : '';
  switch (code) {
    case 'unauthenticated':
    case 'permission-denied':
      return 'Tu acceso de registro venció o fue revocado. Renueva el acceso y vuelve a intentar. Tus datos siguen en el formulario.';
    case 'unavailable':
    case 'network-request-failed':
    case 'deadline-exceeded':
      return 'No se pudo confirmar el registro por un problema de conexión. Conservamos tus datos; vuelve a intentar.';
    case 'already-exists':
      return 'Ya existe un estudiante con esa matrícula o con el mismo nombre y fecha de nacimiento. Revisa la lista antes de continuar.';
    case 'resource-exhausted':
      return 'Se alcanzó el límite de estudiantes o de solicitudes. Espera e inténtalo de nuevo; si continúa, contacta al administrador.';
    case 'invalid-argument':
      return 'Revisa los datos del formulario: hay un campo con formato o longitud no válidos.';
    case 'failed-precondition':
      return 'No se pudo completar el registro con la configuración actual. Revisa el grado y contacta al administrador si continúa.';
    default:
      return 'No se pudo registrar al estudiante. Tus datos siguen en el formulario. Inténtalo de nuevo o contacta al administrador.';
  }
}

bool registrationNeedsRenewal(Object error) =>
    error is FirebaseException &&
    (error.code == 'unauthenticated' || error.code == 'permission-denied');
