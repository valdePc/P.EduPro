// lib/admin_escolar/screens/A_pizarra.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:edupro/models/escuela.dart';

// Pantallas destino
import 'package:edupro/admin_escolar/screens/A_calendarioacademico.dart';
import 'package:edupro/admin_escolar/screens/A_reporteyanalisis.dart';
import 'package:edupro/admin_escolar/screens/A_seguimientodecumplimiento.dart';
import 'package:edupro/admin_escolar/screens/A_notificacionesyrecomendacion.dart';
import 'package:edupro/admin_escolar/screens/A_usuarios.dart';
import 'package:edupro/admin_escolar/screens/A_planificacionacademica.dart';
import 'package:edupro/admin_escolar/screens/A_evaluaciones.dart';
import 'package:edupro/admin_escolar/screens/A_pagos.dart';
import 'package:edupro/admin_escolar/screens/A_grados.dart';
import 'package:edupro/admin_escolar/screens/A_reuniones.dart';
import 'package:edupro/admin_escolar/screens/A_registro.dart';
import 'package:edupro/admin_escolar/screens/A_chat_administracion_screen.dart';

// Wrapper de asignaturas (pantalla)
import 'package:edupro/admin_escolar/screens/A_asignaturas.dart';

// NUEVO: chat admin
import 'package:edupro/admin_escolar/screens/A_chat_administracion_screen.dart';

// Servicio compartido
import 'package:edupro/admin_escolar/widgets/asignaturas.dart'
    show sharedSubjectsService;

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

        return GridView.count(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 2.8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _statCard(
              title: 'Reuniones',
              value: 'Abrir',
              icon: Icons.groups,
              onTap: () => _navigate(context, AReuniones(escuela: escuela)),
            ),
            _statCard(
              title: 'Pagos',
              value: 'Ver',
              icon: Icons.payment,
              onTap: () => _navigate(context, APagos(escuela: escuela)),
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
                onPressed: () => _navigate(context, APlanificacionAcademica(escuela: escuela)),
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
              OutlinedButton.icon(
                onPressed: () => _navigate(context, AReporteYAnalisis(escuela: escuela)),
                icon: const Icon(Icons.analytics),
                label: const Text('Reportes'),
              ),
              OutlinedButton.icon(
                onPressed: () => _navigate(context, ACalendarioAcademico(escuela: escuela)),
                icon: const Icon(Icons.calendar_today),
                label: const Text('Calendario'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChatPreviewCard(BuildContext context) {
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
              const Icon(Icons.chat_bubble_outline, color: _orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Chat de administración',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _navigate(
                  context,
                  AChatAdministracionScreen(escuela: escuela),
                ),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Abrir'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Canales para comunicarte con docentes: todos, uno a uno, o grupos seleccionados.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),

          // Botones rápidos que abren el chat ya “parado” en el modo.
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _navigate(
                  context,
                  AChatAdministracionScreen(
                    escuela: escuela,
                    initialMode: AdminChatMode.todosDocentes,
                  ),
                ),
                icon: const Icon(Icons.groups),
                label: const Text('Todos los docentes'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _navigate(
                  context,
                  AChatAdministracionScreen(
                    escuela: escuela,
                    initialMode: AdminChatMode.unDocente,
                  ),
                ),
                icon: const Icon(Icons.person),
                label: const Text('A un docente'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _navigate(
                  context,
                  AChatAdministracionScreen(
                    escuela: escuela,
                    initialMode: AdminChatMode.grupoSeleccionado,
                  ),
                ),
                icon: const Icon(Icons.group_add),
                label: const Text('Grupo'),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Preview de conversaciones (las últimas 3) sin index compuesto
          AdminRecentThreadsPreview(escuela: escuela, maxItems: 3),
        ],
      ),
    );
  }

  Widget _buildNotificacionesCard() {
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
              const Icon(Icons.notifications, color: _orange, size: 20),
              const SizedBox(width: 8),
              Text(
                'Últimas notificaciones',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_add),
            title: const Text('Nuevo estudiante registrado'),
            subtitle: Text('Hoy • ${DateFormat.Hm().format(DateTime.now())}'),
            trailing: TextButton(onPressed: () {}, child: const Text('Ver')),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: const Text('Recordatorio: entrega de notas'),
            subtitle: Text(
              'Mañana • ${DateFormat.Hm().format(DateTime.now().add(const Duration(days: 1)))}',
            ),
            trailing: TextButton(onPressed: () {}, child: const Text('Ver')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 920;

    final nombre = (escuela.nombre ?? '—').trim().isEmpty ? '—' : escuela.nombre!.trim();
    final creado = escuela.fecha ?? DateTime.now();

    final side = Column(
      children: [
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: _orange,
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
                        fontSize: 18,
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
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _menuTile(
                context: context,
                icon: Icons.dashboard,
                label: 'Pizarra General',
                selected: true,
                onTap: () {
                  if (onNavigate != null) onNavigate!(0);
                },
              ),
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
              _menuTile(
                context: context,
                icon: Icons.track_changes,
                label: 'Seguimiento de Cumplimiento',
                onTap: () {
                  if (onNavigate != null) {
                    onNavigate!(4);
                  } else {
                    _navigate(context, ASeguimientoDeCumplimiento(escuela: escuela));
                  }
                },
              ),
              _menuTile(
                context: context,
                icon: Icons.notifications,
                label: 'Notificaciones y Reportes',
                onTap: () {
                  if (onNavigate != null) {
                    onNavigate!(5);
                  } else {
                    _navigate(context, ANotificacionesYRecomendacion(escuela: escuela));
                  }
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                onPressed: () {
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
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copiar enlaces'),
                style: ElevatedButton.styleFrom(backgroundColor: _blue),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final changed = await _navigate<bool>(
                    context,
                    AAsignaturas(escuela: escuela, service: sharedSubjectsService),
                  );
                  if (changed == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Asignaturas actualizadas')),
                    );
                  }
                },
                icon: const Icon(Icons.import_contacts),
                label: const Text('Asignaturas'),
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
              // Header + accesos principales
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
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _navigate(context, ARegistro(escuela: escuela)),
                        icon: const Icon(Icons.how_to_reg),
                        label: const Text('Registro'),
                        style: FilledButton.styleFrom(backgroundColor: _orange),
                      ),
                      FilledButton.icon(
                        onPressed: () => _navigate(context, AUsuarios(escuela: escuela)),
                        icon: const Icon(Icons.person_search),
                        label: const Text('Usuarios'),
                        style: FilledButton.styleFrom(backgroundColor: _orange),
                      ),
                      FilledButton.icon(
                        onPressed: () => _navigate(context, AGrados(escuela: escuela)),
                        icon: const Icon(Icons.view_agenda),
                        label: const Text('Grados'),
                        style: FilledButton.styleFrom(backgroundColor: _orange),
                      ),
                      FilledButton.icon(
                        onPressed: () async {
                          final changed = await _navigate<bool>(
                            context,
                            AAsignaturas(escuela: escuela, service: sharedSubjectsService),
                          );
                          if (changed == true) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Asignaturas actualizadas')),
                            );
                          }
                        },
                        icon: const Icon(Icons.import_contacts),
                        label: const Text('Asignaturas'),
                        style: FilledButton.styleFrom(backgroundColor: _orange),
                      ),
                    ],
                  ),
                ],
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

              const SizedBox(height: 22),

              // Chat (mejor ubicado y funcional)
              _buildChatPreviewCard(context),

              const SizedBox(height: 22),

              // Notificaciones
              _buildNotificacionesCard(),

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
                  width: 260,
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
