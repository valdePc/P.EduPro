import 'package:cloud_firestore/cloud_firestore.dart';

enum TipoPeriodo { bimestre, trimestre, semestre }

class PeriodoAcademico {
  final String id;
  final String nombre; // P1, P2, P3, P4
  final DateTime inicio;
  final DateTime fin;
  final bool activo;

  PeriodoAcademico({
    required this.id,
    required this.nombre,
    required this.inicio,
    required this.fin,
    this.activo = true,
  });

  Map<String, dynamic> toMap() => {
        'nombre': nombre,
        'inicio': Timestamp.fromDate(inicio),
        'fin': Timestamp.fromDate(fin),
        'activo': activo,
      };

  factory PeriodoAcademico.fromMap(String id, Map<String, dynamic> map) =>
      PeriodoAcademico(
        id: id,
        nombre: map['nombre'] ?? '',
        inicio: (map['inicio'] as Timestamp).toDate(),
        fin: (map['fin'] as Timestamp).toDate(),
        activo: map['activo'] ?? true,
      );
}

class PlanificacionAnual {
  final String id;
  final String schoolId;
  final String anioEscolar;// Ej: 2025-2026
  final String nivel; // Inicial, Primaria, Secundaria
  final String grado;
  final List<UnidadDidactica> unidades;

  PlanificacionAnual({
    required this.id,
    required this.schoolId,
    required this.anioEscolar,
    required this.nivel,
    required this.grado,
    this.unidades = const [],
  });

  Map<String, dynamic> toMap() => {
        'schoolId': schoolId,
        'anioEscolar': anioEscolar,
        'nivel': nivel,
        'grado': grado,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

class UnidadDidactica {
  final String id;
  final String titulo;
  final String mes;
  final List<String> competenciasEspecificas;
  final List<String> contenidos;
  final List<String> indicadoresLogro;

  UnidadDidactica({
    required this.id,
    required this.titulo,
    required this.mes,
    this.competenciasEspecificas = const [],
    this.contenidos = const [],
    this.indicadoresLogro = const [],
  });

  Map<String, dynamic> toMap() => {
        'titulo': titulo,
        'mes': mes,
        'competenciasEspecificas': competenciasEspecificas,
        'contenidos': contenidos,
        'indicadoresLogro': indicadoresLogro,
      };
}
