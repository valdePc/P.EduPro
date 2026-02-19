class Escuela {
  final String nombre;
  final String adminLink;
  final String profLink;
  final String alumLink;
  final DateTime fecha;
  final String password;
  final List<String>? grados; // opcional
  bool activo;

  Escuela({
    required this.nombre,
    required this.adminLink,
    required this.profLink,
    required this.alumLink,
    required this.fecha,
    required this.password,
    this.grados,
    this.activo = true,
  });
}