// lib/alumnos/screens/perfil_secundaria_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

// ✅ Tus archivos existen con estos nombres (plural)
import '../nav/mensajes_alumnos_screen.dart';
import '../nav/avisos_alumnos_screen.dart';


// ✅ Tabs
import 'package:edupro/alumnos/tabs/resumen_tab.dart';
import 'package:edupro/alumnos/tabs/academico_tab.dart';
import 'package:edupro/alumnos/tabs/asistencia_tab.dart';
import 'package:edupro/alumnos/tabs/tareas_tab.dart';
import 'package:edupro/alumnos/tabs/nacionales_tab.dart';
import 'package:edupro/alumnos/tabs/documentos_tab.dart';
import 'package:edupro/alumnos/tabs/tutores_tab.dart';
import 'package:edupro/calendario/ui/calendario_screen.dart';
import 'package:edupro/calendario/models/user_role.dart';

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
    _schoolId = normalizeSchoolIdFromEscuela(widget.escuela);
  }

  // ✅ OJO: aquí va en SINGULAR (lo más probable en tu proyecto)
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



  @override
  Widget build(BuildContext context) {
    final nombreFallback = (widget.nombreAlumno ?? 'Alumno').trim();
    final gradoFallback = (widget.gradoSeleccionado ?? 'Secundaria').trim();

    return DefaultTabController(
      length: 7,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: Text('Secundaria • ${widget.escuela.nombre}'),
          backgroundColor: _blue,
          actions: [
            IconButton(
              tooltip: 'Avisos',
              icon: const Icon(Icons.campaign_outlined),
              onPressed: _openAvisos,
            ),
            IconButton(
  tooltip: 'Calendario',
  icon: const Icon(Icons.calendar_month),
  onPressed: _openCalendarioAlumno,
),

            IconButton(
              tooltip: 'Mensajes',
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: _openMensajes,
            ),
            if (kDebugMode)
              IconButton(
                tooltip: 'DEMO',
                icon: const Icon(Icons.science_outlined),
                onPressed: () async {
                  await _cfgRef.set(
                    {'allowStudentPhoto': true},
                    SetOptions(merge: true),
                  );

                  await _estRef.set({
                    'nombre': 'Alumno',
                    'apellido': 'Secundaria',
                    'grado': gradoFallback,
                    'tanda': 'Tarde',
                    'matricula': 'SC-2001',
                    'idGlobal': 'GLOBAL-SC-0001',
                    'fechaNacimiento': Timestamp.fromDate(
                      DateTime(DateTime.now().year - 15, 2, 1),
                    ),
                  }, SetOptions(merge: true));
                },
              ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: _orange,
            unselectedLabelColor: Colors.white70,
            indicatorColor: _orange,
            tabs: [
              Tab(text: 'Resumen', icon: Icon(Icons.dashboard_outlined)),
              Tab(text: 'Académico', icon: Icon(Icons.menu_book_outlined)),
              Tab(text: 'Asistencia', icon: Icon(Icons.fact_check_outlined)),
              Tab(text: 'Tareas', icon: Icon(Icons.assignment_outlined)),
              Tab(text: 'Nacionales', icon: Icon(Icons.flag_outlined)),
              Tab(text: 'Documentos', icon: Icon(Icons.folder_outlined)),
              Tab(text: 'Tutores', icon: Icon(Icons.people_outline)),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
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
                  NacionalesTab(estRef: _estRef),
                  DocumentosTab(estRef: _estRef),
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
          padding: const EdgeInsets.all(14),
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
                    radius: 26,
                    backgroundColor: _orange.withOpacity(0.12),
                    child: const Icon(Icons.person, color: _orange),
                  ),
                  const SizedBox(width: 12),
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
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
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
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _MiniInfo(
                      label: 'Matrícula',
                      value: matricula.isEmpty ? '—' : matricula,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniInfo(
                      label: 'ID Global',
                      value: idGlobal.isEmpty ? '—' : idGlobal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
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
                        padding: const EdgeInsets.symmetric(vertical: 12),
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
          Icon(icon, size: 16, color: Colors.black87),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
