// lib/admin_escolar/screens/A_pizarra.dart

import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

// Importa todas tus pantallas destino:
import 'package:edupro/admin_escolar/screens/A_gestiondemaestros.dart';
import 'package:edupro/admin_escolar/screens/A_calendarioacademico.dart';
import 'package:edupro/admin_escolar/screens/A_reporteyanalisis.dart';
import 'package:edupro/admin_escolar/screens/A_seguimientodecumplimiento.dart';
import 'package:edupro/admin_escolar/screens/A_notificacionesyrecomendacion.dart';
import 'package:edupro/admin_escolar/screens/A_usuarios.dart';
import 'package:edupro/admin_escolar/screens/A_asignaturas.dart';
import 'package:edupro/admin_escolar/screens/A_planificacionacademica.dart';
import 'package:edupro/admin_escolar/screens/A_evaluaciones.dart';
import 'package:edupro/admin_escolar/screens/A_pagos.dart';

class APizarra extends StatelessWidget {
  final Escuela escuela;
  const APizarra({Key? key, required this.escuela}) : super(key: key);

  static const _blue = Color(0xFF0D47A1);    // Azul principal EduPro
  static const _orange = Color(0xFFFFA000);  // Naranja secundario EduPro

  void _navigate(BuildContext context, Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  ListTile _buildMenuTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: selected ? _orange : Colors.blue),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? _orange : Colors.blue,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: selected,
      selectedTileColor: Colors.blue.shade50,
      onTap: onTap,
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.blue.shade100),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: _orange),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    // Menú lateral
    final sideMenu = ListView(
      padding: const EdgeInsets.symmetric(vertical: 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'EduPro',
            style: TextStyle(
              color: _blue,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 30),
        _buildMenuTile(
          context,
          icon: Icons.dashboard,
          label: 'Pizarra General',
          selected: true,
          onTap: () {}, // No hacer nada si ya estás en esta pantalla

        ),
        _buildMenuTile(
          context,
          icon: Icons.school,
          label: 'Gestión de Maestros',
          selected: false,
          onTap: () => _navigate(context, AGestionDeMaestros(escuela: escuela)),
        ),
        _buildMenuTile(
          context,
          icon: Icons.calendar_today,
          label: 'Calendario Académico',
          selected: false,
          onTap: () => _navigate(context, ACalendarioAcademico(escuela: escuela)),
        ),
        _buildMenuTile(
          context,
          icon: Icons.analytics,
          label: 'Reporte y Análisis',
          selected: false,
          onTap: () => _navigate(context, AReporteYAnalisis(escuela: escuela)),
        ),
        _buildMenuTile(
          context,
          icon: Icons.track_changes,
          label: 'Seguimiento de Cumplimiento',
          selected: false,
          onTap: () => _navigate(context, ASeguimientoDeCumplimiento(escuela: escuela)),
        ),
        _buildMenuTile(
          context,
          icon: Icons.notifications,
          label: 'Notificaciones y Recomendación',
          selected: false,
          onTap: () => _navigate(context, ANotificacionesYRecomendacion(escuela: escuela)),
        ),
        _buildMenuTile(
          context,
          icon: Icons.bar_chart,
          label: 'Reportes y Análisis (otra)',
          selected: false,
          onTap: () => _navigate(context,  AReporteYAnalisis(escuela: escuela)),
        ),
      ],
    );

    // Cuerpo principal: las “cards”
    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título con el nombre de la escuela
          Text(
            'Pizarra General — ${escuela.nombre}',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _blue,
            ),
          ),
          const SizedBox(height: 30),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _buildCard(
                context,
                icon: Icons.person,
                label: 'Usuarios',
                onTap: () => _navigate(context, AUsuarios(escuela: escuela)),
              ),
              _buildCard(
                context,
                icon: Icons.grid_view,
                label: 'Asignaturas',
                onTap: () => _navigate(context, AAsignaturas(escuela: escuela)),
              ),
              _buildCard(
                context,
                icon: Icons.event_note,
                label: 'Planificación Académica',
                onTap: () => _navigate(context, APlanificacionAcademica(escuela: escuela)),
              ),
              _buildCard(
                context,
                icon: Icons.pie_chart,
                label: 'Evaluaciones',
                onTap: () => _navigate(context, AEvaluaciones(escuela: escuela)),
              ),
              _buildCard(
                context,
                icon: Icons.payment,
                label: 'Pagos',
                onTap: () => _navigate(context, APagos(escuela: escuela)),
              ),
            ],
          ),
        ],
      ),
    );

    return Scaffold(
      drawer: isMobile ? Drawer(child: sideMenu) : null,
      appBar: isMobile
          ? AppBar(
              title: const Text('Pizarra General'),
              backgroundColor: _blue,
            )
          : null,
      body: isMobile
          ? body
          : Row(
              children: [
                Container(width: 240, color: _blue.withOpacity(0.1), child: sideMenu),
                Expanded(child: body),
              ],
            ),
    );
  }
}
