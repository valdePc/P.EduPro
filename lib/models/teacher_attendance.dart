import 'package:cloud_firestore/cloud_firestore.dart';

/// Estados básicos de asistencia.
enum AttendanceStatus { present, absent, tardy, excused, unknown }

AttendanceStatus attendanceStatusFromString(String? s) {
  final v = (s ?? '').toLowerCase().trim();
  switch (v) {
    case 'present':
    case 'presente':
      return AttendanceStatus.present;
    case 'absent':
    case 'ausente':
      return AttendanceStatus.absent;
    case 'tardy':
    case 'tarde':
    case 'late':
      return AttendanceStatus.tardy;
    case 'excused':
    case 'justificado':
      return AttendanceStatus.excused;
    default:
      return AttendanceStatus.unknown;
  }
}

String attendanceStatusToString(AttendanceStatus s) {
  switch (s) {
    case AttendanceStatus.present:
      return 'present';
    case AttendanceStatus.absent:
      return 'absent';
    case AttendanceStatus.tardy:
      return 'tardy';
    case AttendanceStatus.excused:
      return 'excused';
    case AttendanceStatus.unknown:
    default:
      return 'unknown';
  }
}

/// Asistencia del docente por día.
/// Colección sugerida:
/// schools/{schoolId}/teachers/{teacherId}/attendance/{attendanceId}
/// o schools/{schoolId}/teacher_attendance/{attendanceId}
class TeacherAttendance {
  final String id;

  final String schoolId;
  final String teacherId;

  /// Día de la asistencia (recomendado: guardarlo como DateTime normal)
  final DateTime date;

  final AttendanceStatus status;
  final String note;

  /// Quién marcó (opcional)
  final String markedByUid;
  final String markedByName;

  final DateTime createdAt;
  final DateTime updatedAt;

  TeacherAttendance({
    required this.id,
    required this.schoolId,
    required this.teacherId,
    required this.date,
    this.status = AttendanceStatus.unknown,
    this.note = '',
    this.markedByUid = '',
    this.markedByName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  // -------------------------
  // Firestore mapping
  // -------------------------
  Map<String, dynamic> toMap() {
    return {
      'schoolId': schoolId,
      'teacherId': teacherId,
      'date': Timestamp.fromDate(date),
      'status': attendanceStatusToString(status),
      'note': note,
      'markedByUid': markedByUid,
      'markedByName': markedByName,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Map<String, dynamic> toMapForCreate() {
    return {
      'schoolId': schoolId,
      'teacherId': teacherId,
      'date': Timestamp.fromDate(date),
      'status': attendanceStatusToString(status),
      'note': note,
      'markedByUid': markedByUid,
      'markedByName': markedByName,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMapForUpdate() {
    return {
      'date': Timestamp.fromDate(date),
      'status': attendanceStatusToString(status),
      'note': note,
      'markedByUid': markedByUid,
      'markedByName': markedByName,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static DateTime _readDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.now();
  }

  factory TeacherAttendance.fromMap(String id, Map<String, dynamic> map) {
    return TeacherAttendance(
      id: id,
      schoolId: (map['schoolId'] ?? '').toString().trim(),
      teacherId: (map['teacherId'] ?? '').toString().trim(),
      date: _readDate(map['date']),
      status: attendanceStatusFromString(map['status']?.toString()),
      note: (map['note'] ?? '').toString(),
      markedByUid: (map['markedByUid'] ?? '').toString().trim(),
      markedByName: (map['markedByName'] ?? '').toString().trim(),
      createdAt: _readDate(map['createdAt']),
      updatedAt: _readDate(map['updatedAt']),
    );
  }

  factory TeacherAttendance.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return TeacherAttendance.fromMap(doc.id, data);
  }
}
