// lib/admin_escolar/screens/A_calendarioacademico.dart
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/calendario/ui/calendario_screen.dart';
import 'package:edupro/calendario/models/user_role.dart'; // ✅ FALTA ESTE

class ACalendarioAcademico extends StatelessWidget {
  final Escuela escuela;
  const ACalendarioAcademico({Key? key, required this.escuela}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final schoolId = normalizeSchoolId(escuela);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const SizedBox.shrink(),
        backgroundColor: const Color(0xFF0D47A1),
        elevation: 0,
      ),
      body: CalendarioScreen(
        schoolId: schoolId,
        role: UserRole.admin,
        userUid: 'admin-$schoolId',
        userGroups: const [],
        hideAppBar: true,
      ),
    );
  }
}

String normalizeSchoolId(Escuela e) {
  final raw = e.nombre ?? 'school-${e.hashCode}';
  var normalized = raw
      .replaceAll(RegExp(r'https?:\/\/'), '')
      .replaceAll(RegExp(r'\/\/+'), '/');
  normalized = normalized
      .replaceAll('/', '_')
      .replaceAll(RegExp(r'[^A-Za-z0-9\-_]'), '');
  if (normalized.isEmpty) normalized = 'school-${e.hashCode}';
  return normalized;
}
