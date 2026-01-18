import 'package:cloud_firestore/cloud_firestore.dart';

class Teacher {
  final String teacherId;
  final String nombreCompleto;
  final String nivelAsignado; // e.g., 'Primaria', 'Secundaria'
  final String gradoAsignado; // e.g., '5to', '1ro'
  final double kpiCurricularScore; // 0.0 - 1.0 (e.g., 0.85)
  final double kpiAttendanceRate; // 0.0 - 1.0 (e.g., 0.98)
  final Timestamp lastActivity;

  Teacher({
    required this.teacherId,
    required this.nombreCompleto,
    required this.nivelAsignado,
    required this.gradoAsignado,
    required this.kpiCurricularScore,
    required this.kpiAttendanceRate,
    required this.lastActivity,
  });

  // Convertir a Map para Firestore
  Map<String, dynamic> toMap() => {
    'teacherId': teacherId,
    'nombreCompleto': nombreCompleto,
    'nivelAsignado': nivelAsignado,
    'gradoAsignado': gradoAsignado,
    'kpi_curricular_score': kpiCurricularScore,
    'kpi_attendance_rate': kpiAttendanceRate,
    'lastActivity': lastActivity,
  };

  // Crear desde documento de Firestore
  factory Teacher.fromMap(String id, Map<String, dynamic> map) {
    return Teacher(
      teacherId: id,
      nombreCompleto: map['nombreCompleto'] ?? '',
      nivelAsignado: map['nivelAsignado'] ?? '',
      gradoAsignado: map['gradoAsignado'] ?? '',
      kpiCurricularScore: (map['kpi_curricular_score'] ?? 0.0).toDouble(),
      kpiAttendanceRate: (map['kpi_attendance_rate'] ?? 0.0).toDouble(),
      lastActivity: map['lastActivity'] ?? Timestamp.now(),
    );
  }

  // Determinar estado basado en KPIs
  String getStatus() {
    final avgKpi = (kpiCurricularScore + kpiAttendanceRate) / 2;
    if (avgKpi >= 0.85) return 'excellent';
    if (avgKpi >= 0.70) return 'attention';
    return 'critical';
  }
}


