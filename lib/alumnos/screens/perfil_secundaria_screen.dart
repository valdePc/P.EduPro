// lib/alumnos/screens/perfil_secundaria_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

// ✅ Tus archivos existen con estos nombres (plural)
import 'package:edupro/alumnos/screens/chat_grado_screen.dart';
import '../nav/avisos_alumnos_screen.dart';


// ✅ Tabs
import 'package:edupro/alumnos/tabs/resumen_tab.dart';
import 'package:edupro/alumnos/tabs/academico_tab.dart';
import 'package:edupro/alumnos/tabs/asistencia_tab.dart';
import 'package:edupro/alumnos/tabs/tareas_tab.dart';
import 'package:edupro/alumnos/tabs/documentos_tab.dart';
import 'package:edupro/alumnos/tabs/tutores_tab.dart';
import 'package:edupro/calendario/ui/calendario_screen.dart';
import 'package:edupro/calendario/models/user_role.dart';
import 'package:edupro/alumnos/tabs/calificaciones_tab.dart';
import 'package:edupro/alumnos/shared/student_session.dart';
import 'package:edupro/widgets/app_info_menu.dart';

class PerfilSecundariaScreen extends StatefulWidget {
  final Escuela escuela;
  final String estudianteId;
  final String? nombreAlumno;
  final String? gradoSeleccionado;

  const PerfilSecundariaScreen({
    super.key,
    required this.escuela,
    required this.estudianteId,
    this.nombreAlumno,
    this.gradoSeleccionado,
  });

  @override
  State<PerfilSecundariaScreen> createState() => _PerfilSecundariaScreenState();
}

class _PerfilSecundariaScreenState extends State<PerfilSecundariaScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final String _schoolId;

  static const Color _blue = Color(0xFF1565C0);
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



Future<void> _openCalendarioAlumno() async {
  final snap = await _estRef.get();
  final data = snap.data() ?? {};

  final grado = (data['grado'] ?? widget.gradoSeleccionado ?? 'Secundaria')
      .toString()
      .trim();

  final seccion = (data['seccion'] ?? '').toString().trim();

  final groups = <String>{
    grado,
    if (seccion.isNotEmpty) '$grado $seccion',
    if (seccion.isNotEmpty) '$grado|$seccion',
    'SECUNDARIA|$grado',
    if (seccion.isNotEmpty) 'SECUNDARIA|$grado|$seccion',
  }.toList();

  if (!mounted) return;

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CalendarioScreen(
        schoolId: _schoolId,
        role: UserRole.student,
        userUid: widget.estudianteId,
        userGroups: groups,
      ),
    ),
  );
}


  @override
  void initState() {
    super.initState();
    _schoolId = normalizeSchoolIdFromEscuela(widget.escuela).toString().trim();
  }

  // ✅ OJO: aquí va en SINGULAR (lo más probable en tu proyecto)
Future<void> _openMensajes() async {
  try {
    final snap = await _estRef.get();
    final data = snap.data() ?? <String, dynamic>{};

    final gradeId = (data['gradeId'] ?? data['gradoId'] ?? data['gradoKey'] ?? '')
        .toString()
        .trim();

    if (!mounted) return;

    if (gradeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este alumno no tiene gradeId asignado.')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatGradoScreen(
          escuela: widget.escuela,
          initialAlumnoId: widget.estudianteId,
        ),
      ),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error abriendo chat: $e')),
    );
  }
}

void _openAvisos() => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => AvisosAlumnoScreen(escuela: widget.escuela),
  ),
);

Future<bool> _cerrarSesion() async {
  return await signOutStudentSession(
    context,
    escuela: widget.escuela,
  );
}



  @override
  Widget build(BuildContext context) {
    final nombreFallback = (widget.nombreAlumno ?? 'Alumno').trim();
    final gradoFallback = (widget.gradoSeleccionado ?? 'Secundaria').trim();

    return DefaultTabController(
      length: 7,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
         // title: Text('Secundaria • ${widget.escuela.nombre}'),
          backgroundColor: _blue,
          toolbarHeight: 44,
          leadingWidth: 40,
          titleSpacing: 0,
          actions: [
            StudentLogoutSwitch(
              onToggle: _cerrarSesion,
            ),
            const StudentInfoMenuButton(),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: _orange,
            unselectedLabelColor: Colors.white70,
            indicatorColor: _orange,
            labelPadding: EdgeInsets.symmetric(horizontal: 10),
            dividerColor: Colors.transparent,
            tabs: [
              Tab(height: 62, text: 'Resumen', icon: Icon(Icons.dashboard_outlined, size: 20)),
              Tab(height: 62, text: 'Horario', icon: Icon(Icons.menu_book_outlined, size: 20)),
              Tab(height: 62, text: 'Asistencia', icon: Icon(Icons.fact_check_outlined, size: 20)),
              Tab(height: 62, text: 'Tareas', icon: Icon(Icons.assignment_outlined, size: 20)),
              Tab(height: 62, text: 'Documentos', icon: Icon(Icons.folder_outlined, size: 20)),
              Tab(height: 62, text: 'Notas', icon: Icon(Icons.grade_outlined, size: 20)),
              Tab(height: 62, text: 'Tutores', icon: Icon(Icons.people_outline, size: 20)),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: _SecundariaHeader(
                estRef: _estRef,
                fallbackNombre: nombreFallback,
                fallbackGrado: gradoFallback,
                onMensajes: _openMensajes,
                onAvisos: _openAvisos,
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  ResumenTab(estRef: _estRef),
                  AcademicoTab(estRef: _estRef),
                  AsistenciaTab(estRef: _estRef),
                  TareasTab(estRef: _estRef),
                  DocumentosTab(estRef: _estRef),
                  CalificacionesTab(estRef: _estRef),
                  TutoresTab(estRef: _estRef),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecundariaHeader extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;
  final String fallbackNombre;
  final String fallbackGrado;
  final VoidCallback onMensajes;
  final VoidCallback onAvisos;

  static const Color _blue = Color(0xFF1565C0);
  static const Color _orange = Color(0xFFFFA000);

  const _SecundariaHeader({
    required this.estRef,
    required this.fallbackNombre,
    required this.fallbackGrado,
    required this.onMensajes,
    required this.onAvisos,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: estRef.snapshots(),
      builder: (context, snapEst) {
        final est = snapEst.data?.data() ?? {};

        final nombre = (est['nombre'] ?? est['nombres'] ?? fallbackNombre)
            .toString()
            .trim();
        final apellido =
            (est['apellido'] ?? est['apellidos'] ?? '').toString().trim();
        final fullName = ('$nombre $apellido').trim();

        final grado = (est['grado'] ?? fallbackGrado).toString().trim();
        final tanda = (est['tanda'] ?? '').toString().trim();
        final matricula = (est['matricula'] ?? '').toString().trim();
        final idGlobal = (est['idGlobal'] ?? '').toString().trim();

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: _orange.withOpacity(0.12),
                    child: const Icon(Icons.person, color: _orange, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName.isEmpty ? fallbackNombre : fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _ChipInfo(icon: Icons.school, text: grado),
                            if (tanda.isNotEmpty)
                              _ChipInfo(
                                  icon: Icons.wb_sunny_outlined, text: tanda),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _MiniInfo(
                      label: 'Matrícula',
                      value: matricula.isEmpty ? '—' : matricula,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniInfo(
                      label: 'ID Global',
                      value: idGlobal.isEmpty ? '—' : idGlobal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onAvisos,
                      icon: const Icon(Icons.campaign_outlined),
                      label: const Text('Avisos'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _blue,
                        side: BorderSide(color: _blue.withOpacity(0.35)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onMensajes,
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Mensajes'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChipInfo extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ChipInfo({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.black87),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final String label;
  final String value;
  const _MiniInfo({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

