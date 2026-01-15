import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/planificacion_model.dart';

class PlanificacionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Obtener periodos académicos de una escuela
  Stream<List<PeriodoAcademico>> getPeriodos(String schoolId) {
    return _db
        .collection('schools')
        .doc(schoolId)
        .collection('config_academica')
        .doc('periodos')
        .collection('lista')
        .orderBy('inicio')
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => PeriodoAcademico.fromMap(doc.id, doc.data()))
            .toList());
  }

  // Guardar o actualizar un periodo
  Future<void> savePeriodo(String schoolId, PeriodoAcademico periodo) async {
    final ref = _db
        .collection('schools')
        .doc(schoolId)
        .collection('config_academica')
        .doc('periodos')
        .collection('lista');

    if (periodo.id.isEmpty) {
      await ref.add(periodo.toMap());
    } else {
      await ref.doc(periodo.id).update(periodo.toMap());
    }
  }

  // Inicializar periodos estándar de RD si no existen
  Future<void> initDefaultRDPeriodos(String schoolId, int year) async {
    final ref = _db
        .collection('schools')
        .doc(schoolId)
        .collection('config_academica')
        .doc('periodos')
        .collection('lista');

    final existing = await ref.limit(1).get();
    if (existing.docs.isNotEmpty) return;

    final periodos = [
      PeriodoAcademico(id: '', nombre: 'P1 (Sept-Oct)', inicio: DateTime(year, 9, 1), fin: DateTime(year, 10, 31)),
      PeriodoAcademico(id: '', nombre: 'P2 (Nov-Dic)', inicio: DateTime(year, 11, 1), fin: DateTime(year, 12, 20)),
      PeriodoAcademico(id: '', nombre: 'P3 (Ene-Mar)', inicio: DateTime(year + 1, 1, 7), fin: DateTime(year + 1, 3, 31)),
      PeriodoAcademico(id: '', nombre: 'P4 (Abr-Jun)', inicio: DateTime(year + 1, 4, 1), fin: DateTime(year + 1, 6, 20)),
    ];

    for (var p in periodos) {
      await ref.add(p.toMap());
    }
  }

  // Gestión de Planificación Anual por Grado
  Future<void> savePlanAnual(PlanificacionAnual plan) async {
    await _db
        .collection('schools')
        .doc(plan.schoolId)
        .collection('planificaciones_anuales')
        .doc('${plan.anioEscolar}_${plan.grado}')
        .set(plan.toMap(), SetOptions(merge: true));
  }
}