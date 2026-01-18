// lib/admin_escolar/screens/admin_home.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/admin_escolar/widgets/admin_shell.dart';

// Pantallas existentes
import 'A_pizarra.dart';
import 'A_calendarioacademico.dart';
import 'A_reporteyanalisis.dart';
import 'package:edupro/admin_escolar/screens/A_MonitoreoDocentes.dart';
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
      AMonitoreoDocentes(escuela: widget.escuela),
      ANotificacionesYRecomendacion(escuela: widget.escuela),
    ];

final pages = [
  APizarra(...),
  AGestionDeMaestros(...),
  ACalendarioAcademico(...),
  AReporteYAnalisis(...),
  AMonitoreoDocentes(escuela: escuela), // <- ESTE ES EL CLAVO
  ANotificacionesYRecomendacion(...),
];


    return AdminShell(
      pages: pages,
      navItems: navItems,
      initialIndex: widget.initialIndex,
      controller: shellIndex,
    );
  }
}
