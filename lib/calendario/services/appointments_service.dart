import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/appointment_model.dart';

class AppointmentsService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  AppointmentsService({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _col(String schoolId) {
    return _db.collection('schools').doc(schoolId).collection('appointments');
  }

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) {
    return _db.collection('users').doc(uid);
  }

  Future<Map<String, dynamic>> _requireUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado.');

    final snap = await _userDoc(user.uid).get();
    if (!snap.exists) throw Exception('Perfil de usuario no encontrado en /users/${user.uid}.');

    final data = snap.data() ?? {};
    if ((data['enabled'] ?? false) != true) {
      throw Exception('Usuario deshabilitado.');
    }
    final role = (data['role'] ?? '').toString();
    final schoolId = (data['schoolId'] ?? '').toString();

    if (role.isEmpty || schoolId.isEmpty) {
      throw Exception('Perfil incompleto: falta role o schoolId.');
    }
    return data;
  }

  Stream<List<AppointmentModel>> watchAppointmentsForDay({
    required String schoolId,
    required DateTime day,
  }) {
    final startDay = DateTime(day.year, day.month, day.day, 0, 0, 0);
    final endDay = DateTime(day.year, day.month, day.day, 23, 59, 59);

    return _col(schoolId)
        .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(startDay))
        .where('start', isLessThanOrEqualTo: Timestamp.fromDate(endDay))
        .orderBy('start')
        .snapshots()
        .map((snap) => snap.docs.map(AppointmentModel.fromDoc).toList());
  }

  Stream<List<AppointmentModel>> watchAppointmentsRange({
    required String schoolId,
    required DateTime from,
    required DateTime to,
  }) {
    return _col(schoolId)
        .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('start', isLessThanOrEqualTo: Timestamp.fromDate(to))
        .orderBy('start')
        .snapshots()
        .map((snap) => snap.docs.map(AppointmentModel.fromDoc).toList());
  }

  Future<void> createAppointment({
    required String schoolId,
    required String title,
    String? description,
    required DateTime start,
    required DateTime end,
    required AudienceScope audience,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado.');

    final profile = await _requireUserProfile();
    final role = (profile['role'] ?? '').toString();
    final mySchoolId = (profile['schoolId'] ?? '').toString();

    // ✅ Seguridad extra (además de reglas)
    if (mySchoolId != schoolId) {
      throw Exception('No tienes acceso a esta escuela.');
    }
    if (role != 'admin') {
      throw Exception('Solo administración puede crear citas.');
    }

    if (title.trim().isEmpty) throw Exception('El título no puede estar vacío.');
    if (!end.isAfter(start)) throw Exception('La hora final debe ser mayor a la inicial.');

    final now = DateTime.now();

    final model = AppointmentModel(
      id: 'new',
      schoolId: schoolId,
      title: title,
      description: description,
      start: start,
      end: end,
      audience: audience,
      createdByUid: user.uid,
      createdByRole: 'admin', // ✅ real porque validamos role
      canceled: false,
      createdAt: now,
    );

    await _col(schoolId).add(model.toMap());
  }

  Future<void> cancelAppointment({
    required String schoolId,
    required String appointmentId,
  }) async {
    final profile = await _requireUserProfile();
    final role = (profile['role'] ?? '').toString();
    final mySchoolId = (profile['schoolId'] ?? '').toString();

    if (mySchoolId != schoolId) throw Exception('No tienes acceso a esta escuela.');
    if (role != 'admin') throw Exception('Solo administración puede cancelar.');

    await _col(schoolId).doc(appointmentId).update({'canceled': true});
  }
}
