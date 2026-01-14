import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

import '../shared/alumno_common.dart';
import 'package:edupro/alumnos/nav/mensajes_alumnos_screen.dart';
import 'package:edupro/alumnos/nav/avisos_alumnos_screen.dart';

import '../tabs/resumen_tab.dart';
import '../tabs/academico_tab.dart';
import '../tabs/asistencia_tab.dart';
import '../tabs/tareas_tab.dart';
import '../tabs/tutores_tab.dart';
import '../tabs/salud_tab.dart';
import '../tabs/documentos_tab.dart';
import 'package:edupro/calendario/ui/calendario_screen.dart';

import 'package:edupro/calendario/ui/calendario_screen.dart';
import 'package:edupro/calendario/models/user_role.dart'; // ✅ ESTE FALTA
import 'package:edupro/calendario/models/user_role.dart';

class PerfilPrimariaScreen extends StatefulWidget {
  final Escuela escuela;
  final String estudianteId;
  final String? nombreAlumno;
  final String? gradoSeleccionado;

  const PerfilPrimariaScreen({
    super.key,
    required this.escuela,
    required this.estudianteId,
    this.nombreAlumno,
    this.gradoSeleccionado,
  });

  @override
  State<PerfilPrimariaScreen> createState() => _PerfilPrimariaScreenState();
}

class _PerfilPrimariaScreenState extends State<PerfilPrimariaScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final String _schoolId;

  DocumentReference<Map<String, dynamic>> get _estRef => _db
      .collection('escuelas')
      .doc(_schoolId)
      .collection('estudiantes')
      .doc(widget.estudianteId);

  DocumentReference<Map<String, dynamic>> get _cfgRef =>
      _db.collection('escuelas').doc(_schoolId).collection('config').doc('alumnos');

Future<void> _openCalendarioAlumno() async {
  // Lee el doc real del alumno para agarrar grado/sección correctos
  final snap = await _estRef.get();
  final data = snap.data() ?? {};

  final grado = (data['grado'] ?? widget.gradoSeleccionado ?? 'Primaria')
      .toString()
      .trim();

  final seccion = (data['seccion'] ?? '').toString().trim();

  // Grupos que cubren: grado completo + aula (grado+sección)
  // (incluyo varias formas para que “matchee” aunque tus eventos estén guardados distinto)
  final groups = <String>{
    grado,
    if (seccion.isNotEmpty) '$grado $seccion',          // ej: "3ro Primaria A"
    if (seccion.isNotEmpty) '$grado|$seccion',          // ej: "3ro Primaria|A"
    'PRIMARIA|$grado',                                  // ej: "PRIMARIA|3ro Primaria"
    if (seccion.isNotEmpty) 'PRIMARIA|$grado|$seccion', // ej: "PRIMARIA|3ro Primaria|A"
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

  Future<void> _seedDemoData() async {
    if (!kDebugMode) return;
    try {
      await _estRef.set({
        'nombre': 'Juan',
        'apellido': 'Pérez',
        'grado': widget.gradoSeleccionado ?? '3ro Primaria',
        'seccion': 'A',
        'tanda': 'Mañana',
        'matricula': 'PR-2031',
        'fotoUrl': '',
        'idGlobal': 'GLOBAL-DEMO-0001',
        'fechaNacimiento': Timestamp.fromDate(DateTime(DateTime.now().year - 9, 3, 10)),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _cfgRef.set({
        'allowStudentPhoto': true, // escuela permite foto por defecto
      }, SetOptions(merge: true));

      await _estRef.collection('tutores').doc('principal').set({
        'nombre': 'María Pérez',
        'relacion': 'Madre',
        'telefono': '8090000000',
        'whatsapp': '8090000000',
        'email': 'maria@email.com',
        'esPrincipal': true,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _estRef.collection('asistencia').add({
        'fecha': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 1))),
        'estado': 'Presente',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _estRef.collection('tareas').add({
        'titulo': 'Práctica de multiplicación',
        'descripcion': 'Resolver páginas 12-13 del cuaderno.',
        'fechaEntrega': Timestamp.fromDate(DateTime.now().add(const Duration(days: 2))),
        'estado': 'Pendiente',
        'adjuntos': [],
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _estRef.collection('calificaciones').add({
        'materia': 'Matemáticas',
        'tipo': 'Prueba corta',
        'titulo': 'Multiplicación',
        'puntuacion': 18,
        'max': 20,
        'periodo': '1er trimestre',
        'fecha': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 6))),
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _estRef.collection('documentos').add({
        'tipo': 'Boletín',
        'nombre': 'Boletín 1er Trimestre',
        'url': '',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _db.collection('escuelas').doc(_schoolId).collection('avisos').add({
        'titulo': 'Reunión de padres',
        'mensaje': 'Viernes 5:00pm en el aula.',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos DEMO creados (DEBUG)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creando demo: $e')),
        );
      }
    }
  }

  void _openMensajes() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MensajesAlumnoScreen(
          escuela: widget.escuela,
          estudianteId: widget.estudianteId,
        ),
      ),
    );
  }

  void _openAvisos() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AvisosAlumnoScreen(escuela: widget.escuela),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombreFallback = (widget.nombreAlumno ?? 'Alumno').trim();
    final gradoFallback = (widget.gradoSeleccionado ?? 'Primaria').trim();

    return DefaultTabController(
      length: 7,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7FB),
        appBar: AppBar(
          title: Text('Primaria • ${widget.escuela.nombre}'),
          backgroundColor: const Color.fromARGB(255, 21, 101, 192),
          actions: [
            if (kDebugMode)
              IconButton(
                tooltip: 'Crear datos DEMO (DEBUG)',
                icon: const Icon(Icons.science_outlined),
                onPressed: _seedDemoData,
              ),

              IconButton(
  tooltip: 'Calendario',
  icon: const Icon(Icons.calendar_month),
  onPressed: _openCalendarioAlumno,
),

          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.orange,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.orange,
            tabs: [
              Tab(text: 'Resumen'),
              Tab(text: 'Académico'),
              Tab(text: 'Asistencia'),
              Tab(text: 'Tareas'),
              Tab(text: 'Tutores'),
              Tab(text: 'Salud'),
              Tab(text: 'Documentos'),
            ],
          ),
        ),
        body: Column(
          children: [
            // HEADER FIJO (siempre visible)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: AlumnoHeader(
                estRef: _estRef,
                configRef: _cfgRef,
                fallbackNombre: nombreFallback,
                fallbackGrado: gradoFallback,
                onMensajes: _openMensajes,
                onAvisos: _openAvisos,
              ),
            ),

            // CONTADORES (siempre visibles)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: MiniCounter(
                      label: 'Tareas pendientes',
                      stream: _estRef
                          .collection('tareas')
                          .where('estado', isEqualTo: 'Pendiente')
                          .snapshots(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MiniCounter(
                      label: 'Ausencias',
                      stream: _estRef
                          .collection('asistencia')
                          .where('estado', isEqualTo: 'Ausente')
                          .snapshots(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MiniCounter(
                      label: 'Calificaciones',
                      stream: _estRef.collection('calificaciones').snapshots(),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // TABS (cada una en su archivo)
            Expanded(
              child: TabBarView(
                children: [
                  ResumenTab(estRef: _estRef),
                  AcademicoTab(estRef: _estRef),
                  AsistenciaTab(estRef: _estRef),
                  TareasTab(estRef: _estRef),
                  TutoresTab(estRef: _estRef),
                  SaludTab(estRef: _estRef),
                  DocumentosTab(estRef: _estRef),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
