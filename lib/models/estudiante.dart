class Estudiante {
  final String id;
  final String nombre;
  final String apellido;
  final String grado;

  Estudiante({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.grado,
  });

  static List<Estudiante> getAll() {
    return [
      Estudiante(id: '1', nombre: 'María', apellido: 'López', grado: '1ro'),
      Estudiante(id: '2', nombre: 'Juan', apellido: 'Pérez', grado: '2do'),
    ];
  }
}

