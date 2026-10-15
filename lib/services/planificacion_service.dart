import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/planificacion_model.dart';

class PlanificacionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<List<PeriodoAcademico>> getPeriodos(String schoolId) {
    return _db
        .collection('schools')
        .doc(schoolId)
        .collection('config_academica')
        .doc('periodos')
        .collection('lista')
        .orderBy('inicio')
        .snapshots()
        .map((snap) => snap.docs.map((doc) => PeriodoAcademico.fromMap(doc.id, doc.data())).toList());
  }

  Future<void> savePeriodo(String schoolId, PeriodoAcademico periodo) async {
    final ref = _db.collection('schools').doc(schoolId).collection('config_academica').doc('periodos').collection('lista');

    if (periodo.id.isEmpty) {
      await ref.add(periodo.toMap());
    } else {
      await ref.doc(periodo.id).update(periodo.toMap());
    }
  }

  Future<void> initDefaultRDPeriodos(String schoolId, int year) async {
    final ref = _db.collection('schools').doc(schoolId).collection('config_academica').doc('periodos').collection('lista');

    final existing = await ref.limit(1).get();
    if (existing.docs.isNotEmpty) return;

    final periodos = [
      PeriodoAcademico(id: '', nombre: 'P1 (Sept-Oct)', inicio: DateTime(year, 9, 1), fin: DateTime(year, 10, 31)),
      PeriodoAcademico(id: '', nombre: 'P2 (Nov-Dic)', inicio: DateTime(year, 11, 1), fin: DateTime(year, 12, 20)),
      PeriodoAcademico(id: '', nombre: 'P3 (Ene-Mar)', inicio: DateTime(year + 1, 1, 7), fin: DateTime(year + 1, 3, 31)),
      PeriodoAcademico(id: '', nombre: 'P4 (Abr-Jun)', inicio: DateTime(year + 1, 4, 1), fin: DateTime(year + 1, 6, 20)),
    ];

    for (final p in periodos) {
      await ref.add(p.toMap());
    }
  }

  String buildPlanDocId({
    required String anioEscolar,
    required String gradeId,
    required String asignaturaId,
    required String teacherDocId,
  }) {
    final safe = (String input) => input.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    return '${safe(anioEscolar)}_${safe(gradeId)}_${safe(asignaturaId)}_${safe(teacherDocId)}';
  }

  Future<PlanificacionAnual?> getPlanAnual({
    required String schoolId,
    required String anioEscolar,
    required String gradeId,
    required String asignaturaId,
    required String teacherDocId,
  }) async {
    final docId = buildPlanDocId(
      anioEscolar: anioEscolar,
      gradeId: gradeId,
      asignaturaId: asignaturaId,
      teacherDocId: teacherDocId,
    );

    final doc = await _db.collection('schools').doc(schoolId).collection('planificaciones_anuales').doc(docId).get();
    if (doc.exists) {
      return PlanificacionAnual.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});
    }

    final q = await _db
        .collection('schools')
        .doc(schoolId)
        .collection('planificaciones_anuales')
        .where('anioEscolar', isEqualTo: anioEscolar)
        .where('gradeId', isEqualTo: gradeId)
        .where('asignaturaId', isEqualTo: asignaturaId)
        .where('teacherDocId', isEqualTo: teacherDocId)
        .limit(1)
        .get();

    if (q.docs.isEmpty) return null;
    final hit = q.docs.first;
    return PlanificacionAnual.fromMap(hit.id, hit.data());
  }

  Stream<List<PlanificacionAnual>> streamTeacherPlans({
    required String schoolId,
    required String teacherDocId,
    required String anioEscolar,
  }) {
    return _db
        .collection('schools')
        .doc(schoolId)
        .collection('planificaciones_anuales')
        .where('teacherDocId', isEqualTo: teacherDocId)
        .where('anioEscolar', isEqualTo: anioEscolar)
        .snapshots()
        .map((qs) => qs.docs.map((d) => PlanificacionAnual.fromMap(d.id, d.data())).toList());
  }

  Future<void> savePlanAnual(PlanificacionAnual plan) async {
    final docId = plan.id.isNotEmpty
        ? plan.id
        : buildPlanDocId(
            anioEscolar: plan.anioEscolar,
            gradeId: plan.gradeId,
            asignaturaId: plan.asignaturaId,
            teacherDocId: plan.teacherDocId,
          );

    await _db.collection('schools').doc(plan.schoolId).collection('planificaciones_anuales').doc(docId).set(
          plan.copyWith(id: docId, teacherUid: plan.teacherUid.isNotEmpty ? plan.teacherUid : (_auth.currentUser?.uid ?? '')).toMap(),
          SetOptions(merge: true),
        );
  }
}
