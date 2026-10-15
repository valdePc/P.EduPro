import 'package:cloud_firestore/cloud_firestore.dart';

class CompetenciasService {
  CompetenciasService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // ⚠️ Si tu proyecto usa otro nombre para subjects, cambia esto:
  static const String subjectsCol = 'subjects';
  static const String competenciasSubcol = 'competencias';

  CollectionReference<Map<String, dynamic>> _subjectsRef(String sid) =>
      _db.collection('schools').doc(sid).collection(subjectsCol);

  CollectionReference<Map<String, dynamic>> _competenciasRef(String sid, String subjectDocId) =>
      _subjectsRef(sid).doc(subjectDocId).collection(competenciasSubcol);

  Stream<QuerySnapshot<Map<String, dynamic>>> streamSubjects(String sid) {
    return _subjectsRef(sid)
        .orderBy('isDefault', descending: true) // defaults arriba
        .orderBy('name')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamCompetencias(String sid, String subjectDocId) {
    return _competenciasRef(sid, subjectDocId)
        .orderBy('order')
        .snapshots();
  }

  Future<void> addCompetencia({
    required String sid,
    required String subjectDocId,
    required String title,
    String? description,
    int? order,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return;

    final ref = _competenciasRef(sid, subjectDocId).doc();
    await ref.set(<String, dynamic>{
      'title': cleanTitle,
      'description': (description ?? '').trim(),
      'order': order ?? 9999,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateCompetencia({
    required String sid,
    required String subjectDocId,
    required String competenciaId,
    required Map<String, dynamic> patch,
  }) async {
    if (patch.isEmpty) return;
    await _competenciasRef(sid, subjectDocId).doc(competenciaId).update(patch);
  }

  Future<void> deleteCompetencia({
    required String sid,
    required String subjectDocId,
    required String competenciaId,
  }) async {
    await _competenciasRef(sid, subjectDocId).doc(competenciaId).delete();
  }

  /// Para el módulo de calificaciones: leer por subjectDocId (más estable si ya lo tienes).
  Future<List<Map<String, dynamic>>> getCompetenciasOnce({
    required String sid,
    required String subjectDocId,
  }) async {
    final snap = await _competenciasRef(sid, subjectDocId).orderBy('order').get();
    return snap.docs.map((d) => <String, dynamic>{'id': d.id, ...d.data()}).toList();
  }
}