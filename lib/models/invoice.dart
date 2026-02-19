// lib/models/invoice.dart
class Invoice {
  Invoice({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.monto,
    required this.fecha,
    required this.estado,
    this.origen,
  });

  final String id;
  final String nombre;
  final String tipo; // 'Colegio' | 'Freelancer'
  final double monto;
  final DateTime fecha;
  String estado; // 'Pagado'|'Pendiente'|'Vencido'
  final Object? origen; // puede ser Escuela o Freelancer u otro
}