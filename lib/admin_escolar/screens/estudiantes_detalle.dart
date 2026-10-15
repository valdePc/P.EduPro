import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:edupro/alumnos/tabs/asistencia_tab.dart';
import 'package:edupro/alumnos/tabs/calificaciones_tab.dart';
import 'package:edupro/alumnos/tabs/tutores_tab.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class EstudiantesDetalle extends StatelessWidget {
  final Escuela escuela;
  final String studentId;

  const EstudiantesDetalle({
    super.key,
    required this.escuela,
    required this.studentId,
  });

  String get _schoolId => normalizeSchoolIdFromEscuela(escuela);

  CollectionReference<Map<String, dynamic>> get _studentsCol =>
      FirebaseFirestore.instance.collection('schools').doc(_schoolId).collection('alumnos');

  @override
  Widget build(BuildContext context) {
    final studentRef = _studentsCol.doc(studentId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: studentRef.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _scaffold(context, const Center(child: CircularProgressIndicator()));
        }
        if (!snap.hasData || !snap.data!.exists) {
          return _scaffold(context, const Center(child: Text('Alumno no encontrado.')));
        }

        final data = snap.data!.data() ?? <String, dynamic>{};

        return DefaultTabController(
          length: 5,
          child: _scaffold(
            context,
            Column(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                          child: Column(
                            children: [
                              _HeaderCard(data: data),
                              const SizedBox(height: 16),
                              _OverviewCards(
                                schoolId: _schoolId,
                                studentId: studentId,
                                studentData: data,
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: TabBar(
                          isScrollable: true,
                          indicatorColor: const Color(0xFFF59E0B),
                          labelColor: const Color(0xFF0F172A),
                          unselectedLabelColor: const Color(0xFF64748B),
                          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                          tabs: const [
                            Tab(text: 'Resumen'),
                            Tab(text: 'Calificaciones'),
                            Tab(text: 'Asistencia'),
                            Tab(text: 'Tareas'),
                            Tab(text: 'Tutores'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: TabBarView(
                                children: [
                                  _SummaryTab(studentData: data),
                                  CalificacionesTab(estRef: studentRef),
                                  AsistenciaTab(estRef: studentRef),
                                  _TasksTab(
                                    schoolId: _schoolId,
                                    studentId: studentId,
                                    studentData: data,
                                  ),
                                  TutoresTab(estRef: studentRef),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _scaffold(BuildContext context, Widget body) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B4EA2),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Perfil del estudiante', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: body,
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _HeaderCard({required this.data});

  String _pick(List<String> keys, [String fallback = '']) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final fullName = _pick(['nombreCompleto', 'nombre', 'fullName', 'displayName'], 'Alumno');
    final grade = _pick(['grado', 'gradeLabel', 'gradoKey'], 'Sin grado');
    final section = _pick(['seccion', 'section']);
    final tanda = _pick(['tanda', 'shift']);
    final matricula = _pick(['matricula', 'codigo', 'codigoAlumno'], 'Sin matricula');
    final email = _pick(['email', 'correo', 'correoElectronico'], 'Sin correo');
    final phone = _pick(['telefono', 'phone', 'celular'], 'Sin telefono');
    final globalId = _pick(['globalId', 'uid', 'authUid'], 'No disponible');
    final status = (data['status'] ?? data['estado'] ?? 'activo').toString().toLowerCase();
    final statusColor = switch (status) {
      'bloqueado' => const Color(0xFFDC2626),
      'pendiente' => const Color(0xFFF59E0B),
      _ => const Color(0xFF16A34A),
    };
    final statusLabel = switch (status) {
      'bloqueado' => 'Bloqueado',
      'pendiente' => 'Pendiente',
      _ => 'Activo',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B4EA2), Color(0xFF1E64C8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
                ),
                child: const Icon(Icons.school_rounded, color: Colors.white, size: 34),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _TopPill(icon: Icons.groups_rounded, text: grade),
                        if (section.isNotEmpty) _TopPill(icon: Icons.category_rounded, text: section),
                        if (tanda.isNotEmpty) _TopPill(icon: Icons.wb_sunny_outlined, text: tanda),
                        _TopPill(
                          icon: Icons.verified_rounded,
                          text: statusLabel,
                          color: statusColor.withValues(alpha: 0.18),
                          borderColor: statusColor.withValues(alpha: 0.35),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _HeaderStat(label: 'Matricula', value: matricula)),
              const SizedBox(width: 12),
              Expanded(child: _HeaderStat(label: 'Correo', value: email)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _HeaderStat(label: 'Telefono', value: phone)),
              const SizedBox(width: 12),
              Expanded(child: _HeaderStat(label: 'ID Global', value: globalId)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  final Color? borderColor;

  const _TopPill({
    required this.icon,
    required this.text,
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color ?? Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor ?? Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewCards extends StatelessWidget {
  final String schoolId;
  final String studentId;
  final Map<String, dynamic> studentData;

  const _OverviewCards({
    required this.schoolId,
    required this.studentId,
    required this.studentData,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_OverviewData>(
      future: _OverviewData.load(
        schoolId: schoolId,
        studentId: studentId,
        studentData: studentData,
      ),
      builder: (context, snap) {
        final data = snap.data;
        final cards = <_CardData>[
          _CardData(
            title: 'Promedio general',
            value: data == null ? '...' : data.averageLabel,
            subtitle: 'Base de calificaciones publicadas',
            icon: Icons.auto_graph_rounded,
            accent: const Color(0xFF2563EB),
          ),
          _CardData(
            title: 'Asistencia',
            value: data == null ? '...' : data.attendanceLabel,
            subtitle: 'Presentes, ausentes y excusas',
            icon: Icons.fact_check_rounded,
            accent: const Color(0xFF16A34A),
          ),
          _CardData(
            title: 'Tareas entregadas',
            value: data == null ? '...' : '${data.deliveredTasks}/${data.totalTasks}',
            subtitle: data == null ? 'Cargando...' : data.pendingTasksLabel,
            icon: Icons.assignment_turned_in_rounded,
            accent: const Color(0xFFF59E0B),
          ),
          _CardData(
            title: 'Mejor asignatura',
            value: data == null ? '...' : data.bestSubject,
            subtitle: data == null ? 'Cargando...' : 'Puntaje: ${data.bestScoreLabel}',
            icon: Icons.workspace_premium_rounded,
            accent: const Color(0xFF7C3AED),
          ),
        ];

        return LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth > 1350
                ? 4
                : constraints.maxWidth > 900
                    ? 2
                    : 1;
            return GridView.builder(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: cards.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: cols == 1 ? 3.4 : 2.2,
              ),
              itemBuilder: (context, index) => _OverviewCard(data: cards[index]),
            );
          },
        );
      },
    );
  }
}

class _CardData {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accent;

  const _CardData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });
}

class _OverviewCard extends StatelessWidget {
  final _CardData data;

  const _OverviewCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: data.accent.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: data.accent.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: data.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(data.icon, color: data.accent, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  data.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  data.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTab extends StatelessWidget {
  final Map<String, dynamic> studentData;

  const _SummaryTab({required this.studentData});

  String _pick(List<String> keys, [String fallback = 'No disponible']) {
    for (final key in keys) {
      final value = studentData[key];
      final formatted = _formatValue(value);
      if (formatted.isNotEmpty) {
        return formatted;
      }
    }
    return fallback;
  }

  String _fullName() {
    final direct = _pick(['nombreCompleto', 'nombre', 'fullName', 'displayName'], '');
    if (direct.isNotEmpty) return direct;

    final parts = [
      _pick(['nombres', 'firstName'], ''),
      _pick(['apellido', 'apellidos', 'lastName'], ''),
    ].where((e) => e.trim().isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(' ');
    return 'No disponible';
  }

  String _formatValue(dynamic value) {
    if (value == null) return '';
    if (value is Timestamp) {
      final d = value.toDate();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    }
    if (value is DateTime) {
      return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
    }
    return value.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final tutor = (studentData['tutor'] is Map<String, dynamic>)
        ? studentData['tutor'] as Map<String, dynamic>
        : <String, dynamic>{};
    final emergency = (studentData['emergencia'] is Map<String, dynamic>)
        ? studentData['emergencia'] as Map<String, dynamic>
        : <String, dynamic>{};

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _TableSection(
          title: 'Identidad',
          icon: Icons.badge_rounded,
          rows: [
            _Row('Nombre', _fullName()),
            _Row('Matricula', _pick(['matricula', 'codigo', 'codigoAlumno'])),
            _Row('Fecha de nacimiento', _pick(['fechaNacimiento', 'birthDate', 'fechaNac'])),
            _Row('Genero', _pick(['sexo', 'genero'])),
            _Row('Nacionalidad', _pick(['nacionalidad'])),
          ],
        ),
        const SizedBox(height: 14),
        _TableSection(
          title: 'Escolar',
          icon: Icons.school_rounded,
          rows: [
            _Row('Grado', _pick(['grado', 'gradeLabel', 'gradoKey'])),
            _Row('Seccion', _pick(['seccion', 'section'])),
            _Row('Tanda', _pick(['tanda', 'shift'])),
            _Row('Ano escolar', _pick(['anioEscolar', 'schoolYear'])),
            _Row('Estado', _pick(['status', 'estado'], 'activo')),
          ],
        ),
        const SizedBox(height: 14),
        _TableSection(
          title: 'Contacto',
          icon: Icons.contact_phone_rounded,
          rows: [
            _Row('Correo', _pick(['email', 'correo', 'correoElectronico'])),
            _Row('Telefono', _pick(['telefono', 'phone', 'celular'])),
            _Row('Direccion', _pick(['direccion', 'address'])),
            _Row('Nota', _pick(['nota', 'observaciones', 'comentarios'])),
          ],
        ),
        const SizedBox(height: 14),
        _TableSection(
          title: 'Tutor y emergencia',
          icon: Icons.family_restroom_rounded,
          rows: [
            _Row('Tutor', (tutor['nombre'] ?? '').toString().isEmpty ? 'No disponible' : tutor['nombre'].toString()),
            _Row('Parentesco', (tutor['parentesco'] ?? '').toString().isEmpty ? 'No disponible' : tutor['parentesco'].toString()),
            _Row('Telefono tutor', (tutor['telefono'] ?? '').toString().isEmpty ? 'No disponible' : tutor['telefono'].toString()),
            _Row('Correo tutor', (tutor['email'] ?? '').toString().isEmpty ? 'No disponible' : tutor['email'].toString()),
            _Row('Emergencia', (emergency['nombre'] ?? '').toString().isEmpty ? 'No disponible' : emergency['nombre'].toString()),
            _Row('Telefono emergencia', (emergency['telefono'] ?? '').toString().isEmpty ? 'No disponible' : emergency['telefono'].toString()),
          ],
        ),
      ],
    );
  }
}

class _TableSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_Row> rows;

  const _TableSection({
    required this.title,
    required this.icon,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF0B4EA2), size: 20),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(1.3),
              1: FlexColumnWidth(2.4),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: rows
                .map(
                  (row) => TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Text(
                          row.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Text(
                          row.value,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _Row {
  final String label;
  final String value;

  const _Row(this.label, this.value);
}

class _TasksTab extends StatelessWidget {
  final String schoolId;
  final String studentId;
  final Map<String, dynamic> studentData;

  const _TasksTab({
    required this.schoolId,
    required this.studentId,
    required this.studentData,
  });

  String _gradeId() {
    final value = studentData['gradeId'] ?? studentData['gradoId'];
    return (value ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    final gradeId = _gradeId();
    if (gradeId.isEmpty) {
      return const Center(child: Text('El estudiante no tiene grado asignado.'));
    }

    final tasksQuery = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('tareas_docentes')
        .where('gradeId', isEqualTo: gradeId);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: tasksQuery.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error cargando tareas: ${snap.error}'));
        }

        final docs = [...?snap.data?.docs];
        docs.sort((a, b) {
          final aTs = a.data()['createdAt'];
          final bTs = b.data()['createdAt'];
          final aMs = aTs is Timestamp ? aTs.millisecondsSinceEpoch : 0;
          final bMs = bTs is Timestamp ? bTs.millisecondsSinceEpoch : 0;
          return bMs.compareTo(aMs);
        });
        if (docs.isEmpty) {
          return const Center(child: Text('No hay tareas para este grado.'));
        }

        return FutureBuilder<List<_TaskItem>>(
          future: Future.wait(
            docs.map((doc) async {
              final task = doc.data();
              final sub = await doc.reference.collection('submissions').doc(studentId).get();
              final subData = sub.data() ?? <String, dynamic>{};
              final status = (subData['status'] ?? '').toString().toLowerCase();
              final title = (task['title'] ?? task['titulo'] ?? 'Tarea').toString();
              final due = task['dueAt'] ?? task['fechaEntrega'];
              final subject = (task['subjectName'] ?? task['asignatura'] ?? '').toString();
              final teacher = (task['teacherName'] ?? task['docente'] ?? '').toString();
              final summary = (task['description'] ?? task['descripcion'] ?? '').toString();
              final normalizedStatus = switch (status) {
                'submitted' => 'Entregada',
                'completed' => 'Completada',
                'reviewed' => 'Completada',
                _ => sub.exists ? 'Entregada' : 'No entregada',
              };
              return _TaskItem(
                title: title,
                subject: subject,
                teacher: teacher,
                summary: summary,
                dueLabel: _formatDate(due),
                status: normalizedStatus,
              );
            }),
          ),
          builder: (context, tasksSnap) {
            final items = tasksSnap.data ?? const <_TaskItem>[];
            final total = items.length;
            final delivered = items.where((e) => e.status != 'No entregada').length;
            final pending = items.where((e) => e.status == 'No entregada').length;

            return ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _MiniStat(
                        label: 'Total',
                        value: '$total',
                        accent: const Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MiniStat(
                        label: 'Entregadas',
                        value: '$delivered',
                        accent: const Color(0xFF16A34A),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MiniStat(
                        label: 'Pendientes',
                        value: '$pending',
                        accent: const Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...items.map((task) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _TaskCard(task: task),
                    )),
              ],
            );
          },
        );
      },
    );
  }

  static String _formatDate(dynamic value) {
    if (value is Timestamp) {
      final d = value.toDate();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    }
    return 'Sin fecha';
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final _TaskItem task;

  const _TaskCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final isPending = task.status == 'No entregada';
    final chipColor = isPending ? const Color(0xFFDC2626) : const Color(0xFF16A34A);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              _TaskChip(label: task.status, color: chipColor),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (task.subject.isNotEmpty) _TaskChip(label: task.subject, color: const Color(0xFF2563EB)),
              if (task.teacher.isNotEmpty) _TaskChip(label: task.teacher, color: const Color(0xFF7C3AED)),
              _TaskChip(label: 'Entrega: ${task.dueLabel}', color: const Color(0xFFF59E0B)),
            ],
          ),
          if (task.summary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              task.summary,
              style: const TextStyle(color: Color(0xFF475569), height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskChip extends StatelessWidget {
  final String label;
  final Color color;

  const _TaskChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

class _TaskItem {
  final String title;
  final String subject;
  final String teacher;
  final String summary;
  final String dueLabel;
  final String status;

  const _TaskItem({
    required this.title,
    required this.subject,
    required this.teacher,
    required this.summary,
    required this.dueLabel,
    required this.status,
  });
}

class _OverviewData {
  final double average;
  final int present;
  final int absent;
  final int excused;
  final int totalTasks;
  final int deliveredTasks;
  final String bestSubject;
  final double bestScore;

  const _OverviewData({
    required this.average,
    required this.present,
    required this.absent,
    required this.excused,
    required this.totalTasks,
    required this.deliveredTasks,
    required this.bestSubject,
    required this.bestScore,
  });

  String get averageLabel => average == 0 ? 'Sin datos' : average.toStringAsFixed(1);
  String get attendanceLabel => '$present P / $absent A / $excused E';
  String get pendingTasksLabel =>
      totalTasks == 0 ? 'Sin tareas registradas' : '${totalTasks - deliveredTasks} pendientes';
  String get bestScoreLabel => bestScore == 0 ? '--' : bestScore.toStringAsFixed(1);

  static Future<_OverviewData> load({
    required String schoolId,
    required String studentId,
    required Map<String, dynamic> studentData,
  }) async {
    final db = FirebaseFirestore.instance;

    double avg = 0;
    String bestSubject = 'Sin datos';
    double bestScore = 0;
    final cali = await db
        .collection('schools')
        .doc(schoolId)
        .collection('calificaciones_v2')
        .where('studentId', isEqualTo: studentId)
        .get();
    if (cali.docs.isNotEmpty) {
      double sum = 0;
      int count = 0;
      for (final doc in cali.docs) {
        final data = doc.data();
        final score = _toDouble(data['computed'] is Map ? data['computed']['final'] : data['final']);
        if (score != null) {
          sum += score;
          count++;
          if (score > bestScore) {
            bestScore = score;
            bestSubject = (data['subjectName'] ?? data['asignatura'] ?? 'Sin datos').toString();
          }
        }
      }
      if (count > 0) avg = sum / count;
    }

    int present = 0;
    int absent = 0;
    int excused = 0;
    final attendanceMonths = await db.collection('schools').doc(schoolId).collection('asistencia').get();
    for (final month in attendanceMonths.docs) {
      final row = await month.reference.collection('rows').doc(studentId).get();
      final rowData = row.data() ?? <String, dynamic>{};
      rowData.forEach((key, value) {
        if (!key.startsWith('m_')) return;
        switch ((value ?? '').toString().trim().toUpperCase()) {
          case 'P':
            present++;
            break;
          case 'A':
            absent++;
            break;
          case 'E':
            excused++;
            break;
        }
      });
    }

    int totalTasks = 0;
    int deliveredTasks = 0;
    final gradeId = (studentData['gradeId'] ?? studentData['gradoId'] ?? '').toString();
    if (gradeId.isNotEmpty) {
      final tasks = await db
          .collection('schools')
          .doc(schoolId)
          .collection('tareas_docentes')
          .where('gradeId', isEqualTo: gradeId)
          .get();
      totalTasks = tasks.docs.length;
      for (final task in tasks.docs) {
        final sub = await task.reference.collection('submissions').doc(studentId).get();
        if (sub.exists) deliveredTasks++;
      }
    }

    return _OverviewData(
      average: avg,
      present: present,
      absent: absent,
      excused: excused,
      totalTasks: totalTasks,
      deliveredTasks: deliveredTasks,
      bestSubject: bestSubject,
      bestScore: bestScore,
    );
  }
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse((value ?? '').toString());
}

@Deprecated('Usa EstudiantesDetalle')
class AUsuarioDetalle extends EstudiantesDetalle {
  const AUsuarioDetalle({
    super.key,
    required super.escuela,
    required String rol,
    required String userId,
  }) : super(studentId: userId);
}
