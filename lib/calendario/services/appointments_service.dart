import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/appointment_model.dart';
import 'package:edupro/utils/school_utils.dart' show lookupSchoolPublicMeta;

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

  DocumentReference<Map<String, dynamic>> _memberDoc(String schoolId, String uid) {
    return _db.collection('schools').doc(schoolId).collection('members').doc(uid);
  }

  Future<String> _resolveSchoolId(String schoolId) async {
    final sid = schoolId.trim();
    if (sid.isEmpty) return sid;

    try {
      final lookup = await lookupSchoolPublicMeta(_db, sid);
      if (lookup != null) return lookup.schoolId;
    } catch (_) {}

    final candidates = <String>{sid, sid.toUpperCase(), sid.toLowerCase()};
    for (final c in candidates) {
      try {
        final d = await _db.collection('schools').doc(c).get();
        if (d.exists) return c;
      } catch (_) {}
    }
    return sid;
  }

  String _roleLower(Map<String, dynamic> data) {
    final role = (data['role'] ?? data['rol'] ?? data['enrol'] ?? '').toString().trim().toLowerCase();
    return role;
  }

  bool _isAdminRole(String role) {
    return role == 'admin' ||
        role == 'admin_escolar' ||
        role == 'director' ||
        role == 'school_admin' ||
        role == 'staff';
  }

  bool _isTeacherRole(String role) {
    return role == 'teacher' || role == 'docente';
  }

  Set<String> _schoolIdsFromProfile(Map<String, dynamic> data) {
    final out = <String>{};
    final primary = (data['schoolId'] ?? '').toString().trim();
    if (primary.isNotEmpty) out.add(primary);

    final listRaw = data['schoolIds'];
    if (listRaw is List) {
      for (final v in listRaw) {
        final sid = v.toString().trim();
        if (sid.isNotEmpty) out.add(sid);
      }
    }
    return out;
  }

  bool _hasSchoolAccess(Map<String, dynamic> profile, String schoolId) {
    final sid = schoolId.trim();
    if (sid.isEmpty) return false;
    final ids = _schoolIdsFromProfile(profile);
    if (ids.contains(sid)) return true;

    // fallback case-insensitive por datos legacy
    final sidL = sid.toLowerCase();
    for (final id in ids) {
      if (id.toLowerCase() == sidL) return true;
    }
    return false;
  }

  Future<Map<String, dynamic>> _tryUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado.');

    final snap = await _userDoc(user.uid).get();
    if (!snap.exists) return const <String, dynamic>{};

    final data = snap.data() ?? {};
    final enabled = data['enabled'];
    if (enabled is bool && enabled == false) {
      throw Exception('Usuario deshabilitado.');
    }
    final role = _roleLower(data);
    final schoolIds = _schoolIdsFromProfile(data);

    if (role.isEmpty || schoolIds.isEmpty) return const <String, dynamic>{};
    return data;
  }

  Future<Map<String, dynamic>> _loadAccessContext({
    required String schoolId,
    required String uid,
  }) async {
    // 1) Fuente principal: members/{uid} de la escuela
    final ms = await _memberDoc(schoolId, uid).get();
    if (ms.exists) {
      final md = ms.data() ?? const <String, dynamic>{};
      final enabled = md['enabled'];
      if (!(enabled is bool && enabled == false)) {
        final role = _roleLower(md);
        if (role.isNotEmpty) {
          return <String, dynamic>{
            'role': role,
            'hasAccess': true,
          };
        }
      }
    }

    // 2) Fallback: users/{uid}
    final ud = await _tryUserProfile();
    if (ud.isNotEmpty && _hasSchoolAccess(ud, schoolId)) {
      final role = _roleLower(ud);
      if (role.isNotEmpty) {
        return <String, dynamic>{
          'role': role,
          'hasAccess': true,
        };
      }
    }

    return const <String, dynamic>{
      'role': '',
      'hasAccess': false,
    };
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
    // Compat: agenda tradicional = disponibilidad de una sola vez
    await createAvailability(
      schoolId: schoolId,
      title: title,
      description: description,
      start: start,
      end: end,
      audience: audience,
      repeatMode: 'once',
      repeatFrom: start,
    );
  }

  Future<void> createAvailability({
    required String schoolId,
    required String title,
    String? description,
    required DateTime start,
    required DateTime end,
    required AudienceScope audience,
    required String repeatMode, // once | all_days | mon_fri | weekly | custom_weekdays
    DateTime? repeatFrom,
    DateTime? repeatUntil,
    List<int> repeatWeekdays = const [], // 1..7 (Mon..Sun)
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No hay usuario autenticado.');

    final resolvedSchoolId = await _resolveSchoolId(schoolId);
    final ctx = await _loadAccessContext(schoolId: resolvedSchoolId, uid: user.uid);
    final role = (ctx['role'] ?? '').toString();
    final hasAccess = (ctx['hasAccess'] == true);

    // ✅ Seguridad extra (además de reglas)
    if (!hasAccess) {
      throw Exception(
        'No tienes acceso a esta escuela. '
        '(schoolId=$resolvedSchoolId uid=${user.uid})',
      );
    }
    if (!_isAdminRole(role) && !_isTeacherRole(role)) {
      throw Exception('Solo administración y docentes pueden definir disponibilidad.');
    }

    if (title.trim().isEmpty) throw Exception('El título no puede estar vacío.');
    if (!end.isAfter(start)) throw Exception('La hora final debe ser mayor a la inicial.');

    final mode = repeatMode.trim().toLowerCase();
    if (mode == 'once') {
      await _addOneAvailability(
        schoolId: resolvedSchoolId,
        title: title,
        description: description,
        start: start,
        end: end,
        audience: audience,
        createdByUid: user.uid,
        createdByRole: role,
      );
      return;
    }

    if (mode != 'all_days' &&
        mode != 'mon_fri' &&
        mode != 'weekly' &&
        mode != 'custom_weekdays') {
      throw Exception('Frecuencia inválida.');
    }

    if (repeatUntil == null) {
      throw Exception('Debes indicar hasta qué fecha repetir.');
    }

    final fromBase = repeatFrom ?? start;
    final duration = end.difference(start);

    DateTime alignWithStartTime(DateTime d) {
      return DateTime(d.year, d.month, d.day, start.hour, start.minute, start.second);
    }

    DateTime alignWithEndTime(DateTime d) {
      return alignWithStartTime(d).add(duration);
    }

    var cursorStart = alignWithStartTime(fromBase);
    var cursorEnd = alignWithEndTime(fromBase);

    if (cursorEnd.isBefore(cursorStart) || !cursorEnd.isAfter(cursorStart)) {
      throw Exception('Rango horario inválido.');
    }

    final until = DateTime(repeatUntil.year, repeatUntil.month, repeatUntil.day, 23, 59, 59);
    if (until.isBefore(cursorStart)) {
      throw Exception('La fecha límite de repetición debe ser posterior al inicio.');
    }

    final selectedWeekdays = repeatWeekdays.toSet().where((d) => d >= 1 && d <= 7).toSet();
    if (mode == 'custom_weekdays' && selectedWeekdays.isEmpty) {
      throw Exception('Selecciona al menos un día de la semana.');
    }

    bool includeDay(DateTime d) {
      switch (mode) {
        case 'all_days':
          return true;
        case 'mon_fri':
          return d.weekday >= DateTime.monday && d.weekday <= DateTime.friday;
        case 'weekly':
          return d.weekday == fromBase.weekday;
        case 'custom_weekdays':
          return selectedWeekdays.contains(d.weekday);
      }
      return false;
    }

    var guard = 0;
    while (!cursorStart.isAfter(until)) {
      if (includeDay(cursorStart)) {
        await _addOneAvailability(
          schoolId: resolvedSchoolId,
          title: title,
          description: description,
          start: cursorStart,
          end: cursorEnd,
          audience: audience,
          createdByUid: user.uid,
          createdByRole: role,
        );
      }

      final stepDays = mode == 'weekly' ? 7 : 1;
      cursorStart = cursorStart.add(Duration(days: stepDays));
      cursorEnd = cursorEnd.add(Duration(days: stepDays));
      guard++;
      if (guard > 1000) {
        throw Exception('Demasiadas repeticiones. Limita el rango.');
      }
    }
  }

  Future<void> _addOneAvailability({
    required String schoolId,
    required String title,
    String? description,
    required DateTime start,
    required DateTime end,
    required AudienceScope audience,
    required String createdByUid,
    required String createdByRole,
  }) async {
    final now = DateTime.now();

    final model = AppointmentModel(
      id: 'new',
      schoolId: schoolId,
      title: title,
      description: description,
      start: start,
      end: end,
      audience: audience,
      createdByUid: createdByUid,
      createdByRole: createdByRole,
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
    final resolvedSchoolId = await _resolveSchoolId(schoolId);
    final ctx = await _loadAccessContext(schoolId: resolvedSchoolId, uid: user.uid);
    final role = (ctx['role'] ?? '').toString();
    final hasAccess = (ctx['hasAccess'] == true);

    if (!hasAccess) {
      throw Exception(
        'No tienes acceso a esta escuela. '
        '(schoolId=$resolvedSchoolId uid=${user.uid})',
      );
    }
    if (!_isAdminRole(role) && !_isTeacherRole(role)) {
      throw Exception('Solo administración y docentes pueden cancelar.');
    }

    await _col(resolvedSchoolId).doc(appointmentId).update({'canceled': true});
  }
}
