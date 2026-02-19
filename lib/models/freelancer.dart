import 'package:cloud_firestore/cloud_firestore.dart';

class Freelancer {
  final String id;
  final String nombre;
  final String teacherLink;
  final String studentLink;
  final DateTime fecha;
  final String password;
  bool activo;

  Freelancer({
    this.id = '',
    required this.nombre,
    required this.teacherLink,
    required this.studentLink,
    required this.fecha,
    required this.password,
    this.activo = true,
  });

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'teacherLink': teacherLink,
        'studentLink': studentLink,
        'fecha': Timestamp.fromDate(fecha),
        'password': password,
        'activo': activo,
      };

  static DateTime _readDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.now();
  }

  factory Freelancer.fromMap(String id, Map<String, dynamic> map) => Freelancer(
        id: id,
        nombre: (map['nombre'] ?? '').toString(),
        teacherLink: (map['teacherLink'] ?? '').toString(),
        studentLink: (map['studentLink'] ?? '').toString(),
        fecha: _readDate(map['fecha']),
        password: (map['password'] ?? '').toString(),
        activo: (map['activo'] is bool) ? map['activo'] as bool : true,
      );

  factory Freelancer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Freelancer.fromMap(doc.id, data);
  }
}
