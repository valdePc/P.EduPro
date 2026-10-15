// lib/admin_escolar/screens/admin_home.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/admin_escolar/widgets/admin_shell.dart';

// Pantallas existentes
import 'A_pizarra.dart';
import 'A_calendarioacademico.dart';
import 'A_reporteyanalisis.dart';
import 'package:edupro/admin_escolar/screens/A_MonitoreoDocentes.dart';
import 'notificaciones_admin.dart';

import 'A_gestiondemaestros.dart';

class AdminHome extends StatefulWidget {
  final Escuela escuela;
  final int initialIndex;
  const AdminHome({super.key, required this.escuela, this.initialIndex = 0});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  late final ValueNotifier<int> shellIndex;

  @override
  void initState() {
    super.initState();
    shellIndex = ValueNotifier<int>(widget.initialIndex.clamp(0, 5).toInt());
  }

  @override
  void dispose() {
    shellIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navItems = <NavItem>[
      NavItem(
        label: 'Inicio',
        icon: Icons.dashboard_outlined,
        page: APizarra(
          escuela: widget.escuela,
          embedded: true,
          onNavigate: (i) => shellIndex.value = i,
        ),
      ),
      NavItem(
        label: 'Gestión de maestros',
        icon: Icons.people_outline,
        page: AGestionDeMaestros(
          escuela: widget.escuela,
          onBack: () => shellIndex.value = 0,
        ),
      ),
      NavItem(
        label: 'Calendario académico',
        icon: Icons.calendar_month_outlined,
        page: ACalendarioAcademico(
          escuela: widget.escuela,
          onBack: () => shellIndex.value = 0,
        ),
      ),
      NavItem(
        label: 'Reportes y análisis',
        icon: Icons.assessment_outlined,
        page: AReporteYAnalisis(
          escuela: widget.escuela,
          onBack: () => shellIndex.value = 0,
        ),
      ),
      NavItem(
        label: 'Monitoreo docente',
        icon: Icons.fact_check_outlined,
        page: AMonitoreoDocentes(
          escuela: widget.escuela,
          onBack: () => shellIndex.value = 0,
        ),
      ),
      NavItem(
        label: 'Notificaciones',
        icon: Icons.notifications_outlined,
        page: NotificacionesAdminScreen(
          escuela: widget.escuela,
          onBack: () => shellIndex.value = 0,
        ),
      ),
    ];

    return AdminShell(
      pages: navItems.map((item) => item.page).toList(growable: false),
      navItems: navItems,
      initialIndex: shellIndex.value,
      controller: shellIndex,
    );
  }
}
