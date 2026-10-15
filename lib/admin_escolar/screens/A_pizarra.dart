// lib/admin_escolar/screens/A_pizarra.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:edupro/models/escuela.dart';

// Pantallas destino
import 'package:edupro/admin_escolar/screens/A_calendarioacademico.dart';
import 'package:edupro/admin_escolar/screens/A_reporteyanalisis.dart';
import 'package:edupro/admin_escolar/screens/estudiantes.dart';
import 'package:edupro/admin_escolar/screens/A_grados.dart';
import 'package:edupro/admin_escolar/screens/nota_competencias.dart';
import 'package:edupro/admin_escolar/screens/A_registro.dart';
import 'package:edupro/admin_escolar/screens/A_MonitoreoDocentes.dart';
import 'package:edupro/admin_escolar/screens/A_calendario_escolar.dart';
import 'package:edupro/admin_escolar/screens/notificaciones_admin.dart';
import 'package:edupro/admin_escolar/screens/A_cierre_escolar.dart';
import 'package:edupro/admin_escolar/screens/A_cambios_grado.dart';
import 'package:edupro/admin_escolar/screens/A_gestiondemaestros.dart';
// Wrapper de asignaturas (pantalla)
import 'package:edupro/admin_escolar/screens/A_asignaturas.dart';

import 'package:edupro/admin_escolar/screens/chat_admin_docentes_screen.dart';
import 'package:edupro/widgets/app_info_menu.dart';

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
  final String? schoolIdOverride;
  final bool embedded;
  final void Function(int index)? onNavigate;

  const APizarra({
    Key? key,
    required this.escuela,
    this.schoolIdOverride,
    this.embedded = false,
    this.onNavigate,
  }) : super(key: key);      //Color.fromARGB(255, 252, 154, 19)

  static const _blue = Color(0xFF1A237E);
  static const _orange = Color(0xFFFFA000);

  String get _schoolId => (schoolIdOverride ?? escuela.id).trim();

  Route<T> _buildSoftRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final fade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(opacity: fade, child: child);
      },
    );
  }

  Future<T?> _navigate<T>(BuildContext context, Widget page) {
    return Navigator.of(context).push<T>(_buildSoftRoute<T>(page));
  }

  Future<T?> _navigateMenu<T>(
    BuildContext context,
    Widget page,
  ) async {
    final nav = Navigator.of(context);
    if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
      nav.pop();
      await Future<void>.delayed(const Duration(milliseconds: 70));
    }
    if (!nav.mounted) return null;
    return nav.push<T>(_buildSoftRoute<T>(page));
  }

  String _formatDate(DateTime d) => DateFormat.yMMMd().format(d);

  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/admincole',
      (route) => false,
      arguments: escuela,
    );
  }

  Widget _menuTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
    Color? color,
  }) {
    final tileColor = color ?? (selected ? _orange : _blue);

    return ListTile(
      leading: Icon(icon, color: tileColor),
      title: Text(
        label,
        style: TextStyle(
          color: tileColor,
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

  Future<void> _copySingleLink(
    BuildContext context, {
    required String label,
    required String? link,
  }) async {
    final value = link?.trim();
    if (value == null || value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No hay enlace disponible para $label')),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiado al portapapeles')),
    );
  }

  String _roleLinkFor(Escuela escuela, String module) {
    final schoolId = escuela.id.trim();
    if (schoolId.isEmpty) {
      return '';
    }
    return 'https://edupro-8c4fd.web.app/#/eduproapp/$schoolId/$module';
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
            'Configuración Académica',
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
                title: 'Competencias',
                value: 'Ver',
                icon: Icons.event,
                onTap: () => _navigate(
                  context,
                  NotaCompetenciasScreen(escuela: escuela),
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
              _statCard(
                title: 'Cierre escolar',
                value: 'Gestionar',
                icon: Icons.assignment_turned_in_rounded,
                onTap: () => _navigate(
                  context,
                  ACierreEscolarScreen(escuela: escuela),
                ),
              ),
              _statCard(
                title: 'Cambios de grado',
                value: 'Revisar',
                icon: Icons.swap_horiz_rounded,
                onTap: () => _navigate(
                  context,
                  ACambiosGradoScreen(escuela: escuela),
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
                onPressed: () => _copySingleLink(
                  context,
                  label: 'Link Admin',
                  link: _roleLinkFor(escuela, 'admin'),
                ),
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Link Admin'),
                style: FilledButton.styleFrom(backgroundColor: _blue),
              ),
              FilledButton.icon(
                onPressed: () => _copySingleLink(
                  context,
                  label: 'Link Docentes',
                  link: _roleLinkFor(escuela, 'docentes'),
                ),
                icon: const Icon(Icons.groups_2_outlined),
                label: const Text('Link Docentes'),
                style: FilledButton.styleFrom(backgroundColor: _blue),
              ),
              FilledButton.icon(
                onPressed: () => _copySingleLink(
                  context,
                  label: 'Link Alumno',
                  link: _roleLinkFor(escuela, 'alumnos'),
                ),
                icon: const Icon(Icons.school_outlined),
                label: const Text('Link Alumno'),
                style: FilledButton.styleFrom(backgroundColor: _orange),
              ),
              OutlinedButton.icon(
                onPressed: () => showAppInfoMenuSheet(
                  context,
                  title: 'Ayuda y legal para administracion escolar',
                ),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Ayuda y legal'),
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
            'Gestión Escolar',
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
    onTap: () => _navigate(
      context,
      ARegistro(
        escuela: escuela,
        schoolIdOverride: _schoolId,
      ),
    ),
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
    accent: _blue,
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
                    _navigateMenu(
                      context,
                      AGestionDeMaestros(escuela: escuela),
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
                    _navigateMenu(
                      context,
                      AMonitoreoDocentes(escuela: escuela),
                    );
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
                    _navigateMenu(context, ACalendarioAcademico(escuela: escuela));
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
                    _navigateMenu(context, AReporteYAnalisis(escuela: escuela));
                  }
                },
              ),
              _sectionLabel('Comunicación'),
              _menuTile(
                context: context,
                icon: Icons.chat_bubble_outline,
                label: 'Chat de administración',
                onTap: () => _navigateMenu(
                  context,
                  ChatAdminDocentesScreen(escuela: escuela),
                ),
              ),
              _menuTile(
                context: context,
                icon: Icons.notifications,
                label: 'Notificaciones',
                onTap: () => _navigateMenu(
                  context,
                  NotificacionesAdminScreen(escuela: escuela),
                ),
              ),
              _sectionLabel('Cuenta'),
              _menuTile(
                context: context,
                icon: Icons.logout_rounded,
                label: 'Cerrar sesión',
                color: Colors.red.shade700,
                onTap: () => _logout(context),
              ),

            ],
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_blue, _blue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: _blue.withOpacity(0.16),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  'Creada: ${_formatDate(creado)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Accesos principales (tarjetas)
          _buildPrimaryActions(
            context,
            primary: primaryActions,
          ),

          const SizedBox(height: 18),
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
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  tooltip: 'Cerrar sesión',
                  onPressed: () => _logout(context),
                  icon: const Icon(Icons.logout_rounded),
                ),
                const AppInfoMenuButton(),
              ],
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
