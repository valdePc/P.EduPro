import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:edupro/models/escuela.dart';

const String kSchoolPublicMetaCollection = 'public';
const String kSchoolPublicMetaDocId = 'meta';

String normalizeSchoolIdFromEscuela(Escuela escuela) {
  return escuela.id.trim();
}

Iterable<String> schoolIdCandidates(String schoolId) sync* {
  final sid = schoolId.trim();
  if (sid.isEmpty) return;

  final seen = <String>{};
  final raw = <String>[
    sid,
    sid.toUpperCase(),
    sid.toLowerCase(),
    sid.replaceAll('/', '_'),
  ];

  for (final item in raw) {
    final value = item.trim();
    if (value.isEmpty || !seen.add(value)) continue;
    yield value;
  }
}

DocumentReference<Map<String, dynamic>> schoolPublicMetaRef(
  FirebaseFirestore db,
  String schoolId,
) {
  return db
      .collection('schools')
      .doc(schoolId.trim())
      .collection(kSchoolPublicMetaCollection)
      .doc(kSchoolPublicMetaDocId);
}

List<String> _schoolGradesFromData(Map<String, dynamic> data) {
  final raw = data['grades'] ?? data['grados'];
  if (raw is! List) return const <String>[];
  return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
}

Map<String, dynamic> buildSchoolPublicMeta(
  Map<String, dynamic> schoolData, {
  required String schoolId,
}) {
  final grades = _schoolGradesFromData(schoolData);
  final createdAt = schoolData['createdAt'];
  final updatedAt = schoolData['updatedAt'];

  return <String, dynamic>{
    'schoolId': schoolId.trim(),
    'name': (schoolData['name'] ?? schoolData['nombre'] ?? '').toString().trim(),
    'officialName': (schoolData['officialName'] ?? schoolData['name'] ?? '')
        .toString()
        .trim(),
    'adminLink': (schoolData['adminLink'] ?? '').toString().trim(),
    'profLink': (schoolData['profLink'] ?? '').toString().trim(),
    'alumLink': (schoolData['alumLink'] ?? '').toString().trim(),
    'adminDeepLink': (schoolData['adminDeepLink'] ?? '').toString().trim(),
    'profDeepLink': (schoolData['profDeepLink'] ?? '').toString().trim(),
    'alumDeepLink': (schoolData['alumDeepLink'] ?? '').toString().trim(),
    'code': (schoolData['code'] ?? schoolId).toString().trim(),
    'institutionCode':
        (schoolData['institutionCode'] ?? schoolData['code'] ?? schoolId)
            .toString()
            .trim(),
    'grades': grades,
    'grados': grades,
    'active': (schoolData['active'] ?? true) == true,
    'accountStatus': (schoolData['accountStatus'] ?? schoolData['status'] ?? '')
        .toString()
        .trim(),
    'createdAt': createdAt is Timestamp ? createdAt : Timestamp.now(),
    'updatedAt':
        updatedAt is Timestamp ? updatedAt : FieldValue.serverTimestamp(),
  };
}

Escuela escuelaFromPublicMeta({
  required String schoolId,
  required Map<String, dynamic> data,
}) {
  final createdAt = data['createdAt'];
  return Escuela(
    id: schoolId.trim(),
    nombre: (data['name'] ?? data['officialName'] ?? '').toString().trim(),
    adminLink: (data['adminLink'] ?? '').toString().trim(),
    profLink: (data['profLink'] ?? '').toString().trim(),
    alumLink: (data['alumLink'] ?? '').toString().trim(),
    fecha: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
    grados: _schoolGradesFromData(data),
    activo: (data['active'] ?? true) == true,
  );
}

class SchoolPublicMetaLookup {
  final String schoolId;
  final Map<String, dynamic> data;

  const SchoolPublicMetaLookup({
    required this.schoolId,
    required this.data,
  });
}

Future<SchoolPublicMetaLookup?> lookupSchoolPublicMeta(
  FirebaseFirestore db,
  String schoolId,
) async {
  for (final candidate in schoolIdCandidates(schoolId)) {
    try {
      final snap = await schoolPublicMetaRef(db, candidate).get();
      if (!snap.exists) continue;
      return SchoolPublicMetaLookup(
        schoolId: candidate,
        data: snap.data() ?? <String, dynamic>{},
      );
    } catch (_) {
      continue;
    }
  }
  return null;
}
