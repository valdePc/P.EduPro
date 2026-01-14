import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/admin_escolar/screens/admin_login_escolar.dart';

/// OJO: Este archivo NO es calendario.
/// Es la “puerta” de Administración Escolar.
/// main.dart entra aquí con: admin.AdminDashboard(escuela: args)
class AdminDashboard extends StatelessWidget {
  final Escuela escuela;
  const AdminDashboard({super.key, required this.escuela});

  @override
  Widget build(BuildContext context) {
    return AdminLoginEscolarScreen(escuela: escuela);
  }
}
