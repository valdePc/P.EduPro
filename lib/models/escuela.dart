import 'package:cloud_firestore/cloud_firestore.dart';

class Escuela {
  final String id; // 🔴 DOCUMENT ID REAL
  final String nombre;
  final String adminLink;
  final String profLink;
  final String alumLink;
  final DateTime fecha;
  final List<String>? grados;
  bool activo;

  Escuela({
    required this.id,
    required this.nombre,
    required this.adminLink,
    required this.profLink,
    required this.alumLink,
    required this.fecha,
    this.grados,
    this.activo = true,
  });

  /// 🔥 Constructor desde Firestore
  factory Escuela.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Escuela(
      id: doc.id, // 🔴 AQUÍ SE GUARDA EL DOCUMENT ID
      nombre: data['name'] ?? '',
      adminLink: data['adminLink'] ?? '',
      profLink: data['profLink'] ?? '',
      alumLink: data['alumLink'] ?? '',
      fecha: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      grados: (data['grados'] as List?)?.map((e) => e.toString()).toList(),
      activo: data['active'] ?? true,
    );
  }
}
