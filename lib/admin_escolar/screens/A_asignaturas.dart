// lib/admin_escolar/screens/A_asignaturas.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/admin_escolar/widgets/admin_back_button.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

import 'package:edupro/admin_escolar/widgets/asignaturas.dart'
    show SubjectsAdminScreen, sharedSubjectsService, SubjectsService;

import 'package:edupro/admin_escolar/services/subjects_seed.dart';

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

    final sid = normalizeSchoolIdFromEscuela(escuela).toString().trim();

    if (sid.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Asignaturas'),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          leading: const AdminBackButton(),
        ),
        body: const Center(
          child: Text('Error: schoolId vacío. No se pudo enlazar la escuela.'),
        ),
      );
    }

    // ✅ Bind primero SIEMPRE
    svc.bindSchool(sid);

    // ✅ Seed después del bind
  WidgetsBinding.instance.addPostFrameCallback((_) {
  SubjectsSeed.ensureDefaultSubjects(sid);
});

    return SubjectsAdminScreen(service: svc);
  }
}
