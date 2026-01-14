// lib/admin_escolar/screens/admin_home.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/admin_escolar/widgets/admin_shell.dart';

// Pantallas existentes
import 'A_pizarra.dart';
import 'A_calendarioacademico.dart';
import 'A_reporteyanalisis.dart';
import 'A_seguimientodecumplimiento.dart';
import 'A_notificacionesyrecomendacion.dart';

// ✅ IMPORTA la pantalla real de Gestión de Maestros
import 'A_gestiondemaestros.dart'; // <-- ajusta el nombre del archivo si es distinto

class AdminHome extends StatefulWidget {
  final Escuela escuela;
  final int initialIndex;
  const AdminHome({Key? key, required this.escuela, this.initialIndex = 0}) : super(key: key);

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  late final ValueNotifier<int> shellIndex;

  @override
  void initState() {
    super.initState();
    shellIndex = ValueNotifier<int>(widget.initialIndex);
  }

  @override
  void dispose() {
    shellIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      APizarra(
        escuela: widget.escuela,
        embedded: true,
        onNavigate: (i) => shellIndex.value = i,
      ),

      // ✅ DIRECTO, sin botón intermedio
      AGestionDeMaestros(escuela: widget.escuela),

      ACalendarioAcademico(escuela: widget.escuela),
      AReporteYAnalisis(escuela: widget.escuela),
      ASeguimientoDeCumplimiento(escuela: widget.escuela),
      ANotificacionesYRecomendacion(escuela: widget.escuela),
    ];

    final navItems = <NavItem>[
      NavItem(label: 'Pizarra General', icon: Icons.dashboard, page: pages[0]),
      NavItem(label: 'Gestión de Maestros', icon: Icons.people, page: pages[1]),
      NavItem(label: 'Calendario Académico', icon: Icons.calendar_today, page: pages[2]),
      NavItem(label: 'Reportes & Análisis', icon: Icons.bar_chart, page: pages[3]),
      NavItem(label: 'Seguimiento', icon: Icons.track_changes, page: pages[4]),
      NavItem(label: 'Notificaciones', icon: Icons.notifications, page: pages[5]),
    ];

    return AdminShell(
      pages: pages,
      navItems: navItems,
      initialIndex: widget.initialIndex,
      controller: shellIndex,
    );
  }
}
