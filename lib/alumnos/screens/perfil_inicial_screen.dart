// lib/alumnos/screens/perfil_inicial_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

import '../nav/mensajes_alumnos_screen.dart';
import '../nav/avisos_alumnos_screen.dart';
import 'package:edupro/alumnos/tabs/academico_tab.dart';

class PerfilInicialScreen extends StatefulWidget {
  final Escuela escuela;
  final String estudianteId;
  final String? nombreAlumno;
  final String? gradoSeleccionado;

  const PerfilInicialScreen({
    super.key,
    required this.escuela,
    required this.estudianteId,
    this.nombreAlumno,
    this.gradoSeleccionado,
  });

  @override
  State<PerfilInicialScreen> createState() => _PerfilInicialScreenState();
}

class _PerfilInicialScreenState extends State<PerfilInicialScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final String _schoolId;

  static const Color _blue = Color.fromARGB(255, 21, 101, 192);
  static const Color _orange = Color(0xFFFFA000);
  static const Color _bg = Color(0xFFF6F7FB);

  DocumentReference<Map<String, dynamic>> get _estRef => _db
      .collection('schools')
      .doc(_schoolId)
      .collection('alumnos')
      .doc(widget.estudianteId);

  DocumentReference<Map<String, dynamic>> get _cfgRef => _db
      .collection('schools')
      .doc(_schoolId)
      .collection('config')
      .doc('alumnos');

  @override
  void initState() {
    super.initState();
    _schoolId = normalizeSchoolIdFromEscuela(widget.escuela);
  }

  void _openMensajes() => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MensajesAlumnoScreen(
            escuela: widget.escuela,
            estudianteId: widget.estudianteId,
          ),
        ),
      );

  void _openAvisos() => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AvisosAlumnoScreen(escuela: widget.escuela),
        ),
      );

  /// ✅ AHORA: “Calendario” (o cualquier acceso que llame a esto) debe ir a Académico.
  /// Lo dejamos para no romper llamadas existentes.
  //Future<void> _openCalendarioAlumno() async {
 //   _openAcademico();
  //}

  /// ✅ ÚNICA función para abrir Académico (sin duplicados).
  void _openAcademico() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _InicialAcademicoScreen(
          estRef: _estRef,
          escuelaNombre: (widget.escuela.nombre ?? 'EduPro').toString(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombreFallback = (widget.nombreAlumno ?? 'Alumno').trim();
    final gradoFallback = (widget.gradoSeleccionado ?? 'Inicial').trim();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text('Inicial • ${(widget.escuela.nombre ?? 'EduPro').toString()}'),
        backgroundColor: _blue,
        actions: [
          if (kDebugMode)
            IconButton(
              tooltip: 'DEMO',
              icon: const Icon(Icons.science_outlined),
              onPressed: () async {
                await _cfgRef.set({'allowStudentPhoto': true}, SetOptions(merge: true));
                await _estRef.set({
                  'nombre': 'Peque',
                  'apellido': 'Demo',
                  'grado': gradoFallback,
                  'tanda': 'Mañana',
                  'matricula': 'IN-1001',
                  'idGlobal': 'GLOBAL-IN-0001',
                }, SetOptions(merge: true));
              },
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _estRef.snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data() ?? {};

          final nombre = _pickNombre(data, nombreFallback);
          final grado = (data['grado'] ?? gradoFallback).toString().trim();
          final tanda = (data['tanda'] ?? '').toString().trim();
          final matricula = (data['matricula'] ?? '').toString().trim();
          final idGlobal = (data['idGlobal'] ?? '').toString().trim();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            children: [
              _InicialHeaderCard(
                nombre: nombre,
                grado: grado,
                tanda: tanda,
                matricula: matricula,
                idGlobal: idGlobal,
                onMensajes: _openMensajes,
                onAvisos: _openAvisos,
              ),
              const SizedBox(height: 12),

              _CardShell(
                title: 'Enfoque Inicial',
                icon: const Icon(Icons.auto_awesome, color: _orange),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                ),
              ),
              const SizedBox(height: 12),

              _CardShell(
                title: 'Módulos',
                icon: const Icon(Icons.grid_view_rounded, color: _orange),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    final cross = w >= 900 ? 4 : (w >= 520 ? 3 : 2);
                    final spacing = 10.0;
                    final tileW = (w - (spacing * (cross - 1))) / cross;

                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        _ActionTile(
                          width: tileW,
                          icon: Icons.menu_book_rounded,
                          title: 'Actividades',
                          subtitle: 'Lo que hizo hoy',
                          onTap: () => _pushPlaceholder(context, 'Actividades', 'Inicial'),
                        ),
                        _ActionTile(
                          width: tileW,
                          icon: Icons.fact_check_rounded,
                          title: 'Asistencia',
                          subtitle: 'Entradas / salidas',
                          onTap: () => _pushPlaceholder(context, 'Asistencia', 'Inicial'),
                        ),
                        _ActionTile(
                          width: tileW,
                          icon: Icons.task_alt_rounded,
                          title: 'Tareas',
                          subtitle: 'Pendientes',
                          onTap: () => _pushPlaceholder(context, 'Tareas', 'Inicial'),
                        ),
                        _ActionTile(
                          width: tileW,
                          icon: Icons.emoji_people_rounded,
                          title: 'Conducta',
                          subtitle: 'Notas',
                          onTap: () => _pushPlaceholder(context, 'Conducta', 'Inicial'),
                        ),
                        _ActionTile(
                          width: tileW,
                          icon: Icons.folder_rounded,
                          title: 'Documentos',
                          subtitle: 'Permisos',
                          onTap: () => _pushPlaceholder(context, 'Documentos', 'Inicial'),
                        ),
                        _ActionTile(
                          width: tileW,
                          icon: Icons.family_restroom_rounded,
                          title: 'Tutores',
                          subtitle: 'Contactos',
                          onTap: () => _pushPlaceholder(context, 'Tutores', 'Inicial'),
                        ),
                        _ActionTile(
                          width: tileW,
                          icon: Icons.forum_rounded,
                          title: 'Mensajes',
                          subtitle: 'Chat',
                          onTap: _openMensajes,
                          highlight: true,
                        ),
                        _ActionTile(
                          width: tileW,
                          icon: Icons.campaign_rounded,
                          title: 'Avisos',
                          subtitle: 'Comunicados',
                          onTap: _openAvisos,
                        ),

                        /// ✅ ESTE era el “Calendario”. Ahora abre Académico (horario académico).
                //        _ActionTile(
                 //         width: tileW,
                //          icon: Icons.calendar_month_rounded,
                 //         title: 'Calendario',
                //          subtitle: 'Horario académico',
                 //         onTap: _openAcademico,
                 //       ),

                        /// ✅ Si quieres mantener también “Académico” como tile separado, aquí queda.
                        _ActionTile(
                          width: tileW,
                          icon: Icons.calendar_month_rounded,
                          title: 'Calendario Escolar',
                          subtitle: 'Materias / notas',
                          onTap: _openAcademico,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _pickNombre(Map<String, dynamic> data, String fallback) {
    // Soporta tu registro nuevo (nombres/apellidos) y el demo (nombre/apellido)
    final n1 = (data['nombres'] ?? data['nombre'] ?? '').toString().trim();
    final a1 = (data['apellidos'] ?? data['apellido'] ?? '').toString().trim();
    final full = ('${n1.isEmpty ? '' : n1} ${a1.isEmpty ? '' : a1}').trim();
    return full.isNotEmpty ? full : fallback;
  }

  static void _pushPlaceholder(BuildContext context, String modulo, String nivel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PlaceholderModuloScreen(modulo: modulo, nivel: nivel),
      ),
    );
  }
}

/// Pantalla envolvente para mostrar el Tab Académico como pantalla completa.
class _InicialAcademicoScreen extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;
  final String escuelaNombre;

  static const Color _blue = Color.fromARGB(255, 21, 101, 192);
  static const Color _bg = Color(0xFFF6F7FB);

  const _InicialAcademicoScreen({
    required this.estRef,
    required this.escuelaNombre,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text('Inicial • Académico'),
        backgroundColor: _blue,
      ),
      body: AcademicoTab(estRef: estRef),
    );
  }
}

// ---------------- UI ----------------

class _InicialHeaderCard extends StatelessWidget {
  final String nombre;
  final String grado;
  final String tanda;
  final String matricula;
  final String idGlobal;
  final VoidCallback onMensajes;
  final VoidCallback onAvisos;

  static const Color _blue = Color.fromARGB(255, 21, 101, 192);
  static const Color _orange = Color(0xFFFFA000);

  const _InicialHeaderCard({
    required this.nombre,
    required this.grado,
    required this.tanda,
    required this.matricula,
    required this.idGlobal,
    required this.onMensajes,
    required this.onAvisos,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (grado.trim().isNotEmpty) _InfoChip(label: 'Grado', value: grado),
      if (tanda.trim().isNotEmpty) _InfoChip(label: 'Tanda', value: tanda),
      if (matricula.trim().isNotEmpty) _InfoChip(label: 'Matrícula', value: matricula),
      _InfoChip(label: 'ID Global', value: idGlobal.isEmpty ? '—' : idGlobal, warn: idGlobal.isEmpty),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [_blue, _blue.withOpacity(0.82)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: _orange.withOpacity(0.18),
                child: const Icon(Icons.child_care, color: _orange, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    nombre,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Perfil Inicial',
                    style: TextStyle(color: Colors.white.withOpacity(0.85)),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Mensajes',
                onPressed: onMensajes,
                icon: const Icon(Icons.forum_rounded, color: Colors.white),
              ),
              IconButton(
                tooltip: 'Avisos',
                onPressed: onAvisos,
                icon: const Icon(Icons.campaign_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 8, runSpacing: 8, children: chips),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final bool warn;

  const _InfoChip({required this.label, required this.value, this.warn = false});

  @override
  Widget build(BuildContext context) {
    final bg = warn ? Colors.red.withOpacity(0.18) : Colors.white.withOpacity(0.14);
    final bd = warn ? Colors.red.withOpacity(0.30) : Colors.white.withOpacity(0.20);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: bg,
        border: Border.all(color: bd),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: Colors.white.withOpacity(0.95),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final String title;
  final Widget icon;
  final Widget child;

  const _CardShell({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              icon,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(fontWeight: FontWeight.w900)),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final double width;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlight;

  static const Color _orange = Color(0xFFFFA000);

  const _ActionTile({
    required this.width,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: highlight ? _orange.withOpacity(0.55) : Colors.grey.shade300),
          color: highlight ? _orange.withOpacity(0.08) : Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _orange),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ---------------- Placeholder screen ----------------

class _PlaceholderModuloScreen extends StatelessWidget {
  final String modulo;
  final String nivel;

  const _PlaceholderModuloScreen({
    required this.modulo,
    required this.nivel,
  });

  @override
  Widget build(BuildContext context) {
    const azul = Color.fromARGB(255, 21, 101, 192);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: Text('$nivel • $modulo'),
        backgroundColor: azul,
      ),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Text(
            'Aquí diseñamos y conectamos el módulo "$modulo" para $nivel.\n\n'
            'Listo para reemplazar este placeholder con tu lógica real.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade800),
          ),
        ),
      ),
    );
  }
}
