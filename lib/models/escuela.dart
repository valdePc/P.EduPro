// lib/models/escuela.dart

class Escuela {
  final String nombre;
  final String adminLink;
  final String profLink;
  final String alumLink;
  final DateTime fecha;
  final String password;
  final List<String> grados; // 👈 ESTE CAMPO DEBE ESTAR
  bool activo;

  Escuela({
    required this.nombre,
    required this.adminLink,
    required this.profLink,
    required this.alumLink,
    required this.fecha,
    required this.password,
    required this.grados,     // 👈 TAMBIÉN EN EL CONSTRUCTOR
    this.activo = true,
  });
}

