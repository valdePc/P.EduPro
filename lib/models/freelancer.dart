class Freelancer {
  final String nombre;
  final String teacherLink;
  final String studentLink;
  final DateTime fecha;
  final String password; // ✅ NUEVO CAMPO
  bool activo;

  Freelancer({
    required this.nombre,
    required this.teacherLink,
    required this.studentLink,
    required this.fecha,
    required this.password, // ✅ AGREGA AQUÍ TAMBIÉN
    this.activo = true,
  });
}
