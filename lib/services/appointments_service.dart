// lib/calendario/services/appointments_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/appointment_model.dart';
import '../models/user_role.dart';

class AppointmentsService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  AppointmentsService({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _col(String schoolId) {
    // Ruta recomendada por escuela (más limpio y más seguro)
    return _db.collection('schools').doc(schoolId).collection('appointments');
  }

  // ------------------ Helpers ------------------

  String _roleToString(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return 'admin';
      case UserRole.teacher:
        return 'teacher';
      case UserRole.student:
        return 'student';
    }
  }

  /// Regla de visibilidad por audience:
  /// - adminOnly => solo admins
  /// - adminTeachers => admin + teacher
  /// - adminTeachersStudents => todos
  bool _canSeeByAudience(UserRole role, AudienceScope a) {
    switch (a) {
      case AudienceScope.adminOnly:
        return role == UserRole.admin;
      case AudienceScope.adminTeachers:
        return role == UserRole.admin || role == UserRole.teacher;
      case AudienceScope.adminTeachersStudents:
        return true;
    }
  }

  /// Si el appointment tiene groups:
  /// - admin: ve todo
  /// - teacher/student: debe intersectar con userGroups
  bool _canSeeByGroups({
    required UserRole role,
    required List<String> userGroups,
    required List<String> appointmentGroups,
  }) {
    // si no tiene groups => es global (depende solo de audience)
    if (appointmentGroups.isEmpty) return true;

    // admin ve todo
    if (role == UserRole.admin) return true;

    // teacher/student: necesita match
    if (userGroups.isEmpty) return false;

    final setUser = userGroups.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    for (final g in appointmentGroups) {
      final gg = g.trim();
      if (gg.isNotEmpty && setUser.contains(gg)) return true;
    }
    return false;
  }

  // ------------------ Streams ------------------

  /// 🔒 Stream con filtros de seguridad “en UI”:
  /// - por rango de día
  /// - por audience según rol
  /// - por groups (arrayContainsAny si aplica) + filtro final en memoria
  Stream<List<AppointmentModel>> watchAppointmentsForDay({
    required String schoolId,
    required DateTime day,
    required UserRole role,
    required String userUid,
    required List<String> userGroups,
  }) {
    final startDay = DateTime(day.year, day.month, day.day, 0, 0, 0);
    final endDay = DateTime(day.year, day.month, day.day, 23, 59, 59);

    // Normaliza grupos (sin vacíos / sin repetidos)
    final normGroups = userGroups
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    // Query base por rango
    Query<Map<String, dynamic>> q = _col(schoolId)
        .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(startDay))
        .where('start', isLessThanOrEqualTo: Timestamp.fromDate(endDay))
        .orderBy('start');

    // ⚠️ Firestore limit: arrayContainsAny admite máx 10 valores.
    // Si tienes más de 10, hacemos fallback a filtrar en memoria.
    final canUseArrayContainsAny = normGroups.isNotEmpty && normGroups.length <= 10;

    // Para teacher/student, intentamos reducir desde Firestore:
    // - Traer eventos "globales" (sin groups) NO se puede filtrar directo.
    // - Traer eventos con groups sí (arrayContainsAny).
    //
    // Solución: hacemos 1 stream (q) y filtramos en memoria siempre.
    // Si se quiere optimizar más (2 queries + merge), lo hacemos luego.
    // Por ahora: simple y seguro.
    //
    // Si tú quieres optimización ya, te lo hago con RxDart (combineLatest).
    return q.snapshots().map((snap) {
      final all = snap.docs.map(AppointmentModel.fromDoc).toList();

      final filtered = all.where((a) {
        // 1) audience
        if (!_canSeeByAudience(role, a.audience)) return false;

        // 2) groups
        if (!_canSeeByGroups(
          role: role,
          userGroups: normGroups,
          appointmentGroups: a.groups,
        )) return false;

        return true;
      }).toList();

      return filtered;
    });
  }

  Stream<List<AppointmentModel>> watchAppointmentsRange({
    required String schoolId,
    required DateTime from,
    required DateTime to,
    required UserRole role,
    required String userUid,
    required List<String> userGroups,
  }) {
    final normGroups = userGroups
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    return _col(schoolId)
        .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('start', isLessThanOrEqualTo: Timestamp.fromDate(to))
        .orderBy('start')
        .snapshots()
        .map((snap) {
      final all = snap.docs.map(AppointmentModel.fromDoc).toList();

      final filtered = all.where((a) {
        if (!_canSeeByAudience(role, a.audience)) return false;

        if (!_canSeeByGroups(
          role: role,
          userGroups: normGroups,
          appointmentGroups: a.groups,
        )) return false;

        return true;
      }).toList();

      return filtered;
    });
  }

  // ------------------ Writes ------------------

  Future<void> createAppointment({
    required String schoolId,
    required String title,
    String? description,
    required DateTime start,
    required DateTime end,
    required AudienceScope audience,

    /// ✅ para guardar creador real
    required UserRole role,
    required String createdByUid,

    /// ✅ a quién va dirigido (si vacío => global)
    List<String> groups = const [],
  }) async {
    // Seguridad: requiere auth real (siempre)
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado.');

    // 👀 Si quieres “doble check”:
    // el uid autenticado debe coincidir con createdByUid (evita spoof en UI)
    if (user.uid != createdByUid) {
      throw Exception('UID inválido: no coincide con el usuario autenticado.');
    }

    if (title.trim().isEmpty) throw Exception('El título no puede estar vacío.');
    if (!end.isAfter(start)) {
      throw Exception('La hora final debe ser mayor a la inicial.');
    }

    // ✅ regla dura: solo admin puede crear (por ahora)
    // Si luego quieres que docentes creen pero solo para su grupo,
    // lo abrimos con reglas + validación adicional.
    if (role != UserRole.admin) {
      throw Exception('Solo administración puede agendar.');
    }

    final now = DateTime.now();

    final normGroups = groups
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    final model = AppointmentModel(
      id: 'new',
      schoolId: schoolId,
      title: title,
      description: description,
      start: start,
      end: end,
      audience: audience,
      groups: normGroups,
      createdByUid: createdByUid,
      createdByRole: _roleToString(role),
      canceled: false,
      createdAt: now,
    );

    await _col(schoolId).add(model.toMap());
  }

  Future<void> cancelAppointment({
    required String schoolId,
    required String appointmentId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado.');

    // Nota: aquí ideal es verificar rol real por server/rules.
    await _col(schoolId).doc(appointmentId).update({'canceled': true});
  }
}
