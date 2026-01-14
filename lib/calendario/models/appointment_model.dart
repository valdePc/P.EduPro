import 'package:cloud_firestore/cloud_firestore.dart';

enum AudienceScope { adminOnly, adminTeachers, adminTeachersStudents }

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
  final String schoolId;
  final String title;
  final String? description;
  final DateTime start;
  final DateTime end;
  final AudienceScope audience;
  final String createdByUid;
  final String createdByRole;
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
  });

  Map<String, dynamic> toMap() {
    return {
      'schoolId': schoolId,
      'title': title.trim(),
      'description': (description ?? '').trim(),
      'start': Timestamp.fromDate(start),
      'end': Timestamp.fromDate(end),
      'audience': audienceToString(audience),
      'createdByUid': createdByUid,
      'createdByRole': createdByRole,
      'canceled': canceled,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  static AppointmentModel fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AppointmentModel(
      id: doc.id,
      schoolId: (data['schoolId'] ?? '').toString(),
      title: (data['title'] ?? '').toString(),
      description: (data['description'] ?? '').toString().trim().isEmpty
          ? null
          : (data['description'] ?? '').toString(),
      start: (data['start'] as Timestamp).toDate(),
      end: (data['end'] as Timestamp).toDate(),
      audience: audienceFromString((data['audience'] ?? 'adminOnly').toString()),
      createdByUid: (data['createdByUid'] ?? '').toString(),
      createdByRole: (data['createdByRole'] ?? '').toString(),
      canceled: (data['canceled'] ?? false) == true,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }
}
