import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

import '../shared/alumno_common.dart';
import '../shared/student_session.dart';
import 'package:edupro/alumnos/screens/chat_grado_screen.dart';
import 'package:edupro/alumnos/nav/avisos_alumnos_screen.dart';

import '../tabs/resumen_tab.dart';
import '../tabs/academico_tab.dart';
import '../tabs/asistencia_tab.dart';
import '../tabs/tareas_tab.dart';
import '../tabs/tutores_tab.dart';
import '../tabs/salud_tab.dart';
import '../tabs/documentos_tab.dart';
import '../tabs/calificaciones_tab.dart';
import 'package:edupro/widgets/app_info_menu.dart';


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

class _PerfilPrimariaScreenState extends State<PerfilPrimariaScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final String _schoolId;

  late final TabController _tabController;

  static const int _tabResumen = 0;

  DocumentReference<Map<String, dynamic>> get _estRef => _db
      .collection('schools')
      .doc(_schoolId)
      .collection('alumnos')
      .doc(widget.estudianteId);

  DocumentReference<Map<String, dynamic>> get _cfgRef =>
      _db.collection('schools').doc(_schoolId).collection('config').doc('alumnos');

  @override
  void initState() {
    super.initState();
    final raw = normalizeSchoolIdFromEscuela(widget.escuela).toString().trim();
    _schoolId = raw;

    _tabController = TabController(length: 8, vsync: this);
    _tabController.addListener(() {
      if (!mounted) return;
      // Forzamos rebuild al cambiar de tab para mostrar/ocultar el bloque superior.
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildActiveTab() {
    switch (_tabController.index) {
      case 0:
        return ResumenTab(estRef: _estRef);
      case 1:
        return AcademicoTab(estRef: _estRef);
      case 2:
        return AsistenciaTab(estRef: _estRef);
      case 3:
        return TareasTab(estRef: _estRef);
      case 4:
        return TutoresTab(estRef: _estRef);
      case 5:
        return SaludTab(estRef: _estRef);
      case 6:
        return DocumentosTab(estRef: _estRef);
      case 7:
        return CalificacionesTab(estRef: _estRef);
      default:
        return ResumenTab(estRef: _estRef);
    }
  }

  Future<void> _openMensajes() async {
    try {
      final snap = await _estRef.get();
      final data = snap.data() ?? {};

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

  void _openAvisos() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AvisosAlumnoScreen(escuela: widget.escuela),
      ),
    );
  }

  Future<bool> _cerrarSesion() async {
    return await signOutStudentSession(
      context,
      escuela: widget.escuela,
    );
  }

  void _openDatos() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _estRef.snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? {};

                final nombre = (data['nombre'] ?? widget.nombreAlumno ?? 'Alumno')
                    .toString()
                    .trim();
                final apellido = (data['apellido'] ?? '').toString().trim();
                final fullName = (apellido.isEmpty) ? nombre : '$nombre $apellido';

                final grado = (data['gradeName'] ??
                        data['grado'] ??
                        widget.gradoSeleccionado ??
                        '—')
                    .toString()
                    .trim();

                final seccion = (data['seccion'] ?? '').toString().trim();
                final tanda = (data['tanda'] ?? '—').toString().trim();
                final matricula = (data['matricula'] ?? '—').toString().trim();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.badge_rounded),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Datos del estudiante',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            _DatoRow(label: 'Nombre', value: fullName),
                            _DatoRow(
                              label: 'Grado',
                              value: seccion.isNotEmpty ? '$grado • $seccion' : grado,
                            ),
                            _DatoRow(label: 'Tanda', value: tanda),
                            _DatoRow(label: 'Matrícula', value: matricula),
                            const Divider(height: 18),
                            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: _estRef.collection('calificaciones').snapshots(),
                              builder: (context, s2) {
                                final docs = s2.data?.docs ?? [];
                                double sumPct = 0;
                                int nPct = 0;

                                for (final d in docs) {
                                  final m = d.data();
                                  final p = m['puntuacion'];
                                  final mx = m['max'];
                                  if (p is num && mx is num && mx > 0) {
                                    sumPct += (p.toDouble() / mx.toDouble()) * 100.0;
                                    nPct++;
                                  }
                                }

                                final avg = (nPct == 0) ? null : (sumPct / nPct);

                                return Column(
                                  children: [
                                    _DatoRow(label: 'Notas', value: '${docs.length}'),
                                    _DatoRow(
                                      label: 'Prom.',
                                      value: avg == null ? '—' : '${avg.toStringAsFixed(1)}%',
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  bool get _showTopBlock => _tabController.index == _tabResumen;

  @override
  Widget build(BuildContext context) {
    final nombreFallback = (widget.nombreAlumno ?? 'Alumno').trim();
    final gradoFallback = (widget.gradoSeleccionado ?? 'Primaria').trim();

    const azul = Color.fromARGB(255, 21, 101, 192);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: azul,
        elevation: 0,
        toolbarHeight: 44, // ✅ compacto
        title: const SizedBox.shrink(), // ✅ sin "Primaria" ni nombre escuela
        actions: [
          StudentLogoutSwitch(
            onToggle: _cerrarSesion,
          ),
          const StudentInfoMenuButton(),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.orange,
          labelPadding: const EdgeInsets.symmetric(horizontal: 10),
          labelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
          unselectedLabelStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_rounded, size: 20), text: 'Resumen'),
            Tab(icon: Icon(Icons.view_week_rounded, size: 20), text: 'Horario'),
            Tab(icon: Icon(Icons.fact_check_rounded, size: 20), text: 'Asistencia'),
            Tab(icon: Icon(Icons.assignment_turned_in_rounded, size: 20), text: 'Tareas'),
            Tab(icon: Icon(Icons.family_restroom_rounded, size: 20), text: 'Tutores'),
            Tab(icon: Icon(Icons.health_and_safety_rounded, size: 20), text: 'Salud'),
            Tab(icon: Icon(Icons.folder_rounded, size: 20), text: 'Documentos'),
            Tab(icon: Icon(Icons.grade_rounded, size: 20), text: 'Notas'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ✅ SOLO en Resumen (para no matar el espacio en Tareas/Asistencia/etc)
          if (_showTopBlock) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Card(
                elevation: 2,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    children: [
                      AlumnoHeader(
                        estRef: _estRef,
                        configRef: _cfgRef,
                        fallbackNombre: nombreFallback,
                        fallbackGrado: gradoFallback,
                        onMensajes: _openMensajes,
                        onAvisos: _openAvisos,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _QuickKidButton(
                              icon: Icons.forum_rounded,
                              label: 'Mensajes',
                              onTap: _openMensajes,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _QuickKidButton(
                              icon: Icons.campaign_rounded,
                              label: 'Avisos',
                              onTap: _openAvisos,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
              Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                elevation: 1,
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      Expanded(
child: _PendingTasksCard(estRef: _estRef),

                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // ✅ Contenido de tabs ahora tiene TODA la altura cuando no estás en Resumen
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: KeyedSubtree(
                key: ValueKey(_tabController.index),
                child: _buildActiveTab(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickKidButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickKidButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFFF2F6FF),
          border: Border.all(color: const Color(0xFFE1E8FF)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: theme.colorScheme.primary),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _KidCounterCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;

  const _KidCounterCard({
    required this.icon,
    required this.title,
    required this.stream,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        final count = (snap.hasData) ? snap.data!.docs.length : 0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white,
            border: Border.all(color: const Color(0xFFEAECEF)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(height: 6),
              Text(
                '$count',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KidActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _KidActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFFF2F6FF),
          border: Border.all(color: const Color(0xFFE1E8FF)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: theme.colorScheme.primary),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatoRow extends StatelessWidget {
  final String label;
  final String value;

  const _DatoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black54,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalificacionesTabPlaceholder extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;
  const _CalificacionesTabPlaceholder({required this.estRef});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: estRef.collection('calificaciones').orderBy('createdAt', descending: true).limit(100).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('Aún no hay calificaciones.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final titulo = (d['titulo'] ?? d['asignatura'] ?? d['materia'] ?? 'Calificación').toString();
            final p = d['puntuacion'];
            final mx = d['max'];

            String nota = '—';
            if (p is num && mx is num && mx > 0) {
              final pct = (p.toDouble() / mx.toDouble()) * 100.0;
              nota = '${pct.toStringAsFixed(1)}%';
            } else if (p != null) {
              nota = p.toString();
            }

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.grade_rounded, color: Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    nota,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _PendingTasksCard extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;

  const _PendingTasksCard({required this.estRef});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final schoolId = estRef.parent.parent?.id ?? '';
    final studentId = estRef.id;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: estRef.snapshots(),
      builder: (context, estSnap) {
        if (!estSnap.hasData) {
          return _pendingCardUi(context, 0);
        }

        final est = estSnap.data!.data() ?? <String, dynamic>{};

        String pickPrimaryGradeId(Map<String, dynamic> d) {
          final candidates = [
            d['gradeId'],
            d['gradoId'],
            d['gradeKey'],
            d['gradoKey'],
          ];
          for (final c in candidates) {
            final v = (c ?? '').toString().trim();
            if (v.isNotEmpty) return v;
          }
          return '';
        }

        final gradeId = pickPrimaryGradeId(est);
        if (gradeId.isEmpty || schoolId.isEmpty) {
          return _pendingCardUi(context, 0);
        }

        final tasksCol = db
            .collection('schools')
            .doc(schoolId)
            .collection('tareas_docentes');

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: tasksCol.where('gradeId', isEqualTo: gradeId).limit(300).snapshots(),
          builder: (context, taskSnap) {
            if (!taskSnap.hasData) {
              return _pendingCardUi(context, 0);
            }

            final now = DateTime.now();
            final tasks = taskSnap.data!.docs.where((d) {
              final x = d.data();
              final scheduleAt = x['scheduleAt'];
              if (scheduleAt is Timestamp) {
                return !now.isBefore(scheduleAt.toDate());
              }
              return true;
            }).toList();

            if (tasks.isEmpty) {
              return _pendingCardUi(context, 0);
            }

            return StreamBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
              stream: Stream.fromFuture(Future.wait(
                tasks.map((t) => t.reference.collection('submissions').doc(studentId).get()),
              )),
              builder: (context, subSnap) {
                if (!subSnap.hasData) {
                  return _pendingCardUi(context, 0);
                }

                final submissions = subSnap.data!;
                final pending = submissions.where((s) => !s.exists).length;

                return _pendingCardUi(context, pending);
              },
            );
          },
        );
      },
    );
  }

  Widget _pendingCardUi(BuildContext context, int count) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEAECEF)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_late_rounded, color: const Color(0xFF6E56CF), size: 28),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: Colors.black.withOpacity(0.85),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Pendientes',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.black.withOpacity(0.65),
            ),
          ),
        ],
      ),
    );
  }
}
