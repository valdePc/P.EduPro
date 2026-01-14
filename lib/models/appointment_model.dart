// lib/calendario/models/appointment_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum AudienceScope {
  adminOnly,
  adminTeachers,
  adminTeachersStudents,
}

AudienceScope audienceFromString(String s) {
  switch (s) {
    case 'adminOnly':
      return AudienceScope.adminOnly;
    case 'adminTeachers':
      return AudienceScope.adminTeachers;
    case 'adminTeachersStudents':
      return AudienceScope.adminTeachersStudents;
    default:
      return AudienceScope.adminOnly;
  }
}

String audienceToString(AudienceScope a) {
  switch (a) {
    case AudienceScope.adminOnly:
      return 'adminOnly';
    case AudienceScope.adminTeachers:
      return 'adminTeachers';
    case AudienceScope.adminTeachersStudents:
      return 'adminTeachersStudents';
  }
}

class AppointmentModel {
  final String id;
  final String schoolId; // id normalizado de escuela o codigo
  final String title;
  final String? description;

  final DateTime start;
  final DateTime end;

  final AudienceScope audience;

  /// ✅ NUEVO: grupos/audiencias específicas (grado, sección, etc.)
  /// Ej: ["3ro Primaria", "3ro Primaria A", "PRIMARIA|3ro Primaria|A"]
  final List<String> groups;

  // Quién lo creó:
  final String createdByUid;
  final String createdByRole; // 'admin' | 'teacher' | 'student'

  final bool canceled;
  final DateTime createdAt;

  AppointmentModel({
    required this.id,
    required this.schoolId,
    required this.title,
    required this.start,
    required this.end,
    required this.audience,
    required this.createdByUid,
    required this.createdByRole,
    required this.canceled,
    required this.createdAt,
    this.description,
    this.groups = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'schoolId': schoolId,
      'title': title.trim(),
      'description': (description ?? '').trim(),
      'start': Timestamp.fromDate(start),
      'end': Timestamp.fromDate(end),
      'audience': audienceToString(audience),

      // ✅ guarda siempre como array de strings
      'groups': groups
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(),

      'createdByUid': createdByUid,
      'createdByRole': createdByRole,
      'canceled': canceled,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  static AppointmentModel fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final startTs = data['start'] as Timestamp?;
    final endTs = data['end'] as Timestamp?;
    final createdAtTs = data['createdAt'] as Timestamp?;

    // ✅ lee groups de forma tolerante (puede venir null, List<dynamic>, etc.)
    final rawGroups = data['groups'];
    final groups = <String>[];
    if (rawGroups is Iterable) {
      for (final g in rawGroups) {
        final s = (g ?? '').toString().trim();
        if (s.isNotEmpty) groups.add(s);
      }
    }

    return AppointmentModel(
      id: doc.id,
      schoolId: (data['schoolId'] ?? '').toString(),
      title: (data['title'] ?? '').toString(),
      description: (data['description'] ?? '').toString().trim().isEmpty
          ? null
          : (data['description'] ?? '').toString(),
      start: (startTs?.toDate()) ?? DateTime.now(),
      end: (endTs?.toDate()) ?? DateTime.now().add(const Duration(hours: 1)),
      audience:
          audienceFromString((data['audience'] ?? 'adminOnly').toString()),
      groups: groups,

      createdByUid: (data['createdByUid'] ?? '').toString(),
      createdByRole: (data['createdByRole'] ?? '').toString(),
      canceled: (data['canceled'] ?? false) as bool,
      createdAt: (createdAtTs?.toDate()) ?? DateTime.now(),
    );
  }
}
