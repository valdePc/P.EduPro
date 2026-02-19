import 'package:cloud_firestore/cloud_firestore.dart';

class Estudiante {
  final String id;
  final String nombre;
  final String apellido; // ✅ para: e.apellido
  final String grado;
  final String nivel;
  final String seccion;
  final bool activo;

  Estudiante({
    this.id = '',
    required this.nombre,
    this.apellido = '',
    required this.grado,
    this.nivel = '',
    this.seccion = '',
    this.activo = true,
  });

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'apellido': apellido,
        'grado': grado,
        'nivel': nivel,
        'seccion': seccion,
        'activo': activo,
      };

  factory Estudiante.fromMap(String id, Map<String, dynamic> map) => Estudiante(
        id: id,
        nombre: (map['nombre'] ?? '').toString(),
        apellido: (map['apellido'] ?? '').toString(),
        grado: (map['grado'] ?? '').toString(),
        nivel: (map['nivel'] ?? '').toString(),
        seccion: (map['seccion'] ?? '').toString(),
        activo: (map['activo'] is bool) ? map['activo'] as bool : true,
      );

  factory Estudiante.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Estudiante.fromMap(doc.id, data);
  }

  /// ✅ Para que compile tu colocar_calificaciones.dart
  static List<Estudiante> getAll() => <Estudiante>[];
}
