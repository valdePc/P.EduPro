import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/calendario/models/user_role.dart';
import 'package:edupro/calendario/ui/calendario_screen.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class DocentesCalendarioScreen extends StatelessWidget {
  final Escuela escuela;
  final String userUid;

  const DocentesCalendarioScreen({
    super.key,
    required this.escuela,
    required this.userUid,
  });

  @override
  Widget build(BuildContext context) {
    final schoolId = normalizeSchoolIdFromEscuela(escuela);

    return Scaffold(
      appBar: AppBar(
        title: Text('Calendario • ${escuela.nombre}'),
      ),
      body: CalendarioScreen(
        schoolId: schoolId,
        role: UserRole.teacher,
        userUid: userUid,
        hideAppBar: true,
      ),
    );
  }
}
