// lib/admin_escolar/screens/A_asignaturas.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

import 'package:edupro/admin_escolar/widgets/asignaturas.dart'
    show SubjectsAdminScreen, sharedSubjectsService, SubjectsService;

class AAsignaturas extends StatelessWidget {
  final Escuela escuela;
  final SubjectsService? service;

  const AAsignaturas({
    Key? key,
    required this.escuela,
    this.service,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final svc = service ?? sharedSubjectsService;

    // ✅ ahora sí existe bindSchool en el contrato
    final sid = normalizeSchoolIdFromEscuela(escuela);
    svc.bindSchool(sid);

    return SubjectsAdminScreen(service: svc);
  }
}
