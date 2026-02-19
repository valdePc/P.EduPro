// lib/admin_escolar/screens/A_pizarra.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:edupro/models/escuela.dart';

// Pantallas destino
import 'package:edupro/admin_escolar/screens/A_calendarioacademico.dart';
import 'package:edupro/admin_escolar/screens/A_reporteyanalisis.dart';
import 'package:edupro/admin_escolar/screens/A_notificacionesyrecomendacion.dart';
import 'package:edupro/admin_escolar/screens/estudiantes.dart';
import 'package:edupro/admin_escolar/screens/A_planificacionacademica.dart';
import 'package:edupro/admin_escolar/screens/A_evaluaciones.dart';
import 'package:edupro/admin_escolar/screens/A_pagos.dart';
import 'package:edupro/admin_escolar/screens/A_grados.dart';
import 'package:edupro/admin_escolar/screens/A_reuniones.dart';
import 'package:edupro/admin_escolar/screens/A_registro.dart';
import 'package:edupro/admin_escolar/screens/A_MonitoreoDocentes.dart';
import 'package:edupro/admin_escolar/screens/A_calendario_escolar.dart';

// Wrapper de asignaturas (pantalla)
import 'package:edupro/admin_escolar/screens/A_asignaturas.dart';

// Chat admin (solo menú lateral ahora)
import 'package:edupro/admin_escolar/screens/A_chat_administracion_screen.dart';

// Servicio compartido
import 'package:edupro/admin_escolar/widgets/asignaturas.dart'
    show sharedSubjectsService;

class _ActionItem {
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;
  final bool primary;

  const _ActionItem({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.primary = false,
  });
}

class APizarra extends StatelessWidget {
  final Escuela escuela;
  final bool embedded;
  final void Function(int index)? onNavigate;

  const APizarra({
    Key? key,
    required this.escuela,
    this.embedded = false,
    this.onNavigate,
  }) : super(key: key);

  static const _blue = Color(0xFF0D47A1);
  static const _orange = Color(0xFFFFA000);

  Future<T?> _navigate<T>(BuildContext context, Widget page) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  String _formatDate(DateTime d) => DateFormat.yMMMd().format(d);

  Widget _menuTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return ListTile(
      leading: Icon(icon, color: selected ? _orange : _blue),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? _orange : _blue,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      selected: selected,
      selectedTileColor: Colors.blue.shade50,
      onTap: onTap,
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: Colors.grey.shade600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  void _copyLinks(BuildContext context) {
    final links = <String>[];
    if (escuela.adminLink != null) links.add('Admin: ${escuela.adminLink}');
    if (escuela.profLink != null) links.add('Profesores: ${escuela.profLink}');
    if (escuela.alumLink != null) links.add('Alumnos: ${escuela.alumLink}');

    if (links.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: links.join('\n')));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enlaces copiados al portapapeles')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay enlaces disponibles')),
      );
    }
  }

  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    VoidCallback? onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: (color ?? _orange).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color ?? _orange, size: 20),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

Widget _buildStatsGrid(BuildContext context) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 520;
      final crossAxisCount = isNarrow ? 1 : 2;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 2.8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _statCard(
                title: 'Reuniones',
                value: 'Ver',
                icon: Icons.event,
                onTap: () => _navigate(
                  context,
                  AReuniones(escuela: escuela),
                ),
              ),
              _statCard(
                title: 'Calendario Escolar',
                value: 'Abrir',
                icon: Icons.calendar_month,
                onTap: () => _navigate(
                  context,
                  ACalendarioEscolar(escuela: escuela),
                ),
              ),
            ],
          ),
        ],
      );
    },
  );
}

  Widget _buildQuickActionsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt, size: 20, color: _orange),
              const SizedBox(width: 8),
              Text(
                'Acciones rápidas',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => _navigate(
                  context,
                  APlanificacionAcademica(escuela: escuela),
                ),
                icon: const Icon(Icons.event_available),
                label: const Text('Planificación'),
                style: FilledButton.styleFrom(backgroundColor: _blue),
              ),
              FilledButton.icon(
                onPressed: () => _navigate(context, AEvaluaciones(escuela: escuela)),
                icon: const Icon(Icons.assignment),
                label: const Text('Evaluaciones'),
                style: FilledButton.styleFrom(backgroundColor: _blue),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionCard(_ActionItem a) {
    return InkWell(
      onTap: a.onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: a.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(a.icon, color: a.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                a.label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.grey.shade800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryActions(
  BuildContext context, {
  required List<_ActionItem> primary,
}) {
  return LayoutBuilder(
    builder: (context, c) {
      final isNarrow = c.maxWidth < 700;
      final crossAxisCount = isNarrow ? 1 : 2;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Accesos principales',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 3.5,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              ...primary.map(_actionCard),
            ],
          ),
        ],
      );
    },
  );
}


  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 920;

    final nombre =
        (escuela.nombre ?? '—').trim().isEmpty ? '—' : escuela.nombre!.trim();
    final creado = escuela.fecha ?? DateTime.now();

    // Acciones (jerarquizadas)
   final primaryActions = <_ActionItem>[
  _ActionItem(
    label: 'Registro',
    icon: Icons.how_to_reg,
    accent: _blue,
    primary: true,
    onTap: () => _navigate(context, ARegistro(escuela: escuela)),
  ),
  _ActionItem(
    label: 'Grados',
    icon: Icons.view_agenda,
    accent: _orange,
    primary: true,
    onTap: () => _navigate(context, AGrados(escuela: escuela)),
  ),
  _ActionItem(
    label: 'Asignaturas',
    icon: Icons.import_contacts,
    accent: _orange,
    primary: true,
    onTap: () => _navigate(context, AAsignaturas(escuela: escuela)),
  ),
  _ActionItem(
    label: 'Alumnos',
    icon: Icons.person_search,
    accent: _orange,
    primary: true,
    onTap: () => _navigate(context, AEstudiantes(escuela: escuela)),
  ),
];


    final side = Column(
      children: [
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: _blue,
                child: const Icon(Icons.school, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: _blue,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Creada: ${_formatDate(creado)}',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _sectionLabel('Panel'),
              _menuTile(
                context: context,
                icon: Icons.dashboard,
                label: 'Pizarra General',
                selected: true,
                onTap: () {
                  if (onNavigate != null) onNavigate!(0);
                },
              ),

              _sectionLabel('Personal'),
              _menuTile(
                context: context,
                icon: Icons.people,
                label: 'Gestión de Maestros',
                onTap: () {
                  if (onNavigate != null) {
                    onNavigate!(1);
                  } else {
                    Navigator.pushNamed(
                      context,
                      '/admin/gestion-maestros',
                      arguments: escuela,
                    );
                  }
                },
              ),
              _menuTile(
                context: context,
                icon: Icons.track_changes,
                label: 'Monitoreo de Docentes',
                onTap: () {
                  if (onNavigate != null) {
                    onNavigate!(4);
                  } else {
                    _navigate(context, AMonitoreoDocentes(escuela: escuela));
                  }
                },
              ),

              _sectionLabel('Académico'),
              _menuTile(
                context: context,
                icon: Icons.calendar_today,
                label: 'Calendario Académico',
                onTap: () {
                  if (onNavigate != null) {
                    onNavigate!(2);
                  } else {
                    _navigate(context, ACalendarioAcademico(escuela: escuela));
                  }
                },
              ),

              _sectionLabel('Analítica'),
              _menuTile(
                context: context,
                icon: Icons.analytics,
                label: 'Reportes & Análisis',
                onTap: () {
                  if (onNavigate != null) {
                    onNavigate!(3);
                  } else {
                    _navigate(context, AReporteYAnalisis(escuela: escuela));
                  }
                },
              ),

              _sectionLabel('Comunicación'),
              _menuTile(
                context: context,
                icon: Icons.chat_bubble_outline,
                label: 'Chat de administración',
                onTap: () => _navigate(
                  context,
                  AChatAdministracionScreen(escuela: escuela),
                ),
              ),
              _menuTile(
                context: context,
                icon: Icons.notifications,
                label: 'Notificaciones',
                onTap: () {
                  if (onNavigate != null) {
                    onNavigate!(5);
                  } else {
                    _navigate(
                      context,
                      ANotificacionesYRecomendacion(escuela: escuela),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Herramientas',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _copyLinks(context),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copiar enlaces'),
                ),
const SizedBox(height: 8),
OutlinedButton.icon(
  onPressed: () async {
    final changed = await _navigate<bool>(
      context,
      APagos(escuela: escuela), // 👈 aquí navega a A_pagos.dart
    );

    if (changed == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pagos actualizados')),
      );
    }
  },
  icon: const Icon(Icons.payment),
  label: const Text('Pagos'),
),

              ],
            ),
          ),
        ),
      ],
    );

final body = SingleChildScrollView(
  padding: const EdgeInsets.all(24),
  child: Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (sin PopupMenu)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: _blue,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Creada: ${_formatDate(creado)}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Copiar enlaces',
                onPressed: () => _copyLinks(context),
                icon: const Icon(Icons.copy),
              ),
            ],
          ),

          const SizedBox(height: 18),
          Divider(color: Colors.grey.shade300),
          const SizedBox(height: 12),

          // Accesos principales (tarjetas)
          _buildPrimaryActions(
            context,
            primary: primaryActions,
          ),

          const SizedBox(height: 18),
          Divider(color: Colors.grey.shade300),
          const SizedBox(height: 18),

          // Métricas + acciones rápidas
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrowContent = constraints.maxWidth < 800;

              if (isNarrowContent) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatsGrid(context),
                    const SizedBox(height: 18),
                    _buildQuickActionsCard(context),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _buildStatsGrid(context)),
                  const SizedBox(width: 18),
                  Expanded(flex: 2, child: _buildQuickActionsCard(context)),
                ],
              );
            },
          ),

          const SizedBox(height: 40),
        ],
      ),
    ),
  ),
);


    final scaffold = Scaffold(
      drawer: isMobile ? Drawer(child: side) : null,
      appBar: isMobile
          ? AppBar(
              title: Text(nombre, overflow: TextOverflow.ellipsis),
              backgroundColor: _blue,
            )
          : null,
      body: isMobile
          ? body
          : Row(
              children: [
                Container(
                  width: 280,
                  color: _blue.withOpacity(0.04),
                  child: side,
                ),
                Expanded(child: body),
              ],
            ),
    );

    if (embedded) return body;
    return scaffold;
  }
}
