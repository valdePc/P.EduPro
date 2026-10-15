import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/admin_escolar/widgets/admin_back_button.dart';
import 'package:edupro/widgets/school_master_detail_layout.dart';

class AReporteYAnalisis extends StatefulWidget {
  final Escuela escuela;
  final bool embedded;
  final VoidCallback? onBack;
  const AReporteYAnalisis({
    Key? key,
    required this.escuela,
    this.embedded = false,
    this.onBack,
  }) : super(key: key);

  @override
  State<AReporteYAnalisis> createState() => _AReporteYAnalisisState();
}

class _AReporteYAnalisisState extends State<AReporteYAnalisis> {
  late Future<_AnalyticsData> _future;
  late String _schoolIdResolved;

  final _bg = const Color(0xFFF4F7FB);
  final _blue = const Color(0xFF1A237E);
  final _blueSoft = const Color(0xFFE8ECFF);
  final _orange = const Color(0xFFF59E0B);
  final _orangeSoft = const Color(0xFFFFF3DC);
  final _green = const Color(0xFF16A34A);
  final _greenSoft = const Color(0xFFECFDF3);
  final _red = const Color(0xFFDC2626);
  final _redSoft = const Color(0xFFFEECEC);

  @override
  void initState() {
    super.initState();
    _schoolIdResolved = widget.escuela.id.trim();
    _future = _resolveSchoolIdThenLoadAnalytics();
  }

  @override
  void didUpdateWidget(covariant AReporteYAnalisis oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.escuela.id != widget.escuela.id) {
      _schoolIdResolved = widget.escuela.id.trim();
      _future = _resolveSchoolIdThenLoadAnalytics();
    }
  }

  DocumentReference<Map<String, dynamic>> _schoolDoc(String schoolId) =>
      FirebaseFirestore.instance.collection('schools').doc(schoolId);

  Future<void> _refresh() async {
    setState(() {
      _future = _resolveSchoolIdThenLoadAnalytics();
    });
    await _future;
  }

  Future<_AnalyticsData> _resolveSchoolIdThenLoadAnalytics() async {
    final resolved = await _resolveSchoolIdFromUser();
    _schoolIdResolved = resolved;
    return _loadAnalytics(resolved);
  }

  Future<String> _resolveSchoolIdFromUser() async {
    final fallback = widget.escuela.id.trim();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return fallback;

    try {
      DocumentSnapshot<Map<String, dynamic>> userSnap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!userSnap.exists) {
        userSnap =
            await FirebaseFirestore.instance.collection('Users').doc(uid).get();
      }

      final data = userSnap.data();
      if (data == null) return fallback;

      final enabled = data['enabled'] != false;
      final role = (data['role'] ?? '').toString().trim().toLowerCase();
      final schoolId = (data['schoolId'] ?? '').toString().trim();

      if (enabled && schoolId.isNotEmpty && role != 'superadmin') {
        debugPrint('[A_reporteyanalisis] schoolId resuelto desde user: $schoolId');
        return schoolId;
      }
    } catch (e) {
      debugPrint('[A_reporteyanalisis] No pude resolver schoolId desde user: $e');
    }

    return fallback;
  }

  Future<_AnalyticsData> _loadAnalytics(String schoolId) async {
    final schoolRef = _schoolDoc(schoolId);

    final studentsFuture = schoolRef.collection('alumnos').get();
    final teachersFuture = schoolRef.collection('teachers').get();
    final teachersPublicFuture = schoolRef.collection('teachers_public').get();
    final membersFuture = schoolRef.collection('members').get();
    final gradesFuture = schoolRef.collection('grados').get();
    final gradesV2Future = schoolRef.collection('calificaciones_v2').get();
    final plansFuture = schoolRef.collection('planificaciones_anuales').get();
    final attendanceFuture = schoolRef.collection('asistencia').get();
    final tasksFuture = schoolRef.collection('tareas_docentes').get();

    final results = await Future.wait([
      studentsFuture,
      teachersFuture,
      teachersPublicFuture,
      membersFuture,
      gradesFuture,
      gradesV2Future,
      plansFuture,
      attendanceFuture,
      tasksFuture,
    ]);

    final studentsSnap = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final teachersSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final teachersPublicSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;
    final membersSnap = results[3] as QuerySnapshot<Map<String, dynamic>>;
    final gradesSnap = results[4] as QuerySnapshot<Map<String, dynamic>>;
    final gradesV2Snap = results[5] as QuerySnapshot<Map<String, dynamic>>;
    final plansSnap = results[6] as QuerySnapshot<Map<String, dynamic>>;
    final attendanceSnap = results[7] as QuerySnapshot<Map<String, dynamic>>;
    final tasksSnap = results[8] as QuerySnapshot<Map<String, dynamic>>;

    final gradeNameById = <String, String>{};
    for (final doc in gradesSnap.docs) {
      final data = doc.data();
      final label = _firstNonEmpty([
        data['label'],
        data['name'],
        data['nombre'],
        data['grado'],
      ]);
      if (label.isNotEmpty) gradeNameById[doc.id] = label;
    }

    final students = <_StudentLite>[];
    final gradeCounter = <String, int>{};
    int girls = 0, boys = 0, undefinedGender = 0;

    for (final doc in studentsSnap.docs) {
      final data = doc.data();
      final gradeId = _firstNonEmpty([
        data['gradeId'],
        data['gradoId'],
      ]);
      final gradeName = _firstNonEmpty([
        data['gradeName'],
        data['grado'],
        data['gradoNombre'],
        gradeNameById[gradeId],
      ], fallback: 'Sin grado');

      final student = _StudentLite(
        id: doc.id,
        name: _studentName(data),
        gradeId: gradeId,
        gradeName: gradeName,
        gender: _genderBucket(data),
      );
      students.add(student);
      gradeCounter[gradeName] = (gradeCounter[gradeName] ?? 0) + 1;

      switch (student.gender) {
        case _GenderBucket.female:
          girls++;
          break;
        case _GenderBucket.male:
          boys++;
          break;
        case _GenderBucket.unknown:
          undefinedGender++;
          break;
      }
    }

    final studentById = {for (final s in students) s.id: s};
    final teachersById = <String, _TeacherLite>{};

    void absorbTeacher(String teacherId, Map<String, dynamic> data) {
      final teacher = _TeacherLite.fromMap(
        teacherId: teacherId,
        data: data,
        gradeNameById: gradeNameById,
      );
      final current = teachersById[teacher.teacherId];
      if (current == null) {
        teachersById[teacher.teacherId] = teacher;
        return;
      }
      teachersById[teacher.teacherId] = current.merge(teacher);
    }

    for (final doc in teachersSnap.docs) {
      absorbTeacher(doc.id, doc.data());
    }
    for (final doc in teachersPublicSnap.docs) {
      absorbTeacher(doc.id, doc.data());
    }
    for (final doc in membersSnap.docs) {
      final data = doc.data();
      final role = _norm(_firstNonEmpty([data['role'], data['rol']]));
      if (role == 'teacher' || role == 'docente') {
        final teacherDocId = _firstNonEmpty([data['teacherDocId']], fallback: doc.id);
        final map = Map<String, dynamic>.from(data);
        map['authUid'] ??= doc.id;
        map['uid'] ??= doc.id;
        absorbTeacher(teacherDocId, map);
      }
    }

    final teachers = teachersById.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    int activeTeachers = 0;
    int pendingTeachers = 0;
    for (final teacher in teachers) {
      if (teacher.enabled) {
        activeTeachers++;
      } else {
        pendingTeachers++;
      }
    }

    final studentAgg = <String, _StudentScoreAgg>{};
    double schoolScoreSum = 0;
    int schoolScoreCount = 0;

    for (final doc in gradesV2Snap.docs) {
      final data = doc.data();
      final studentId = _firstNonEmpty([data['studentId']]);
      if (studentId.isEmpty) continue;
      final score = _toDouble(
        data['computed'] is Map<String, dynamic> ? (data['computed'] as Map<String, dynamic>)['final'] : data['final'],
      );
      if (score == null) continue;
      schoolScoreSum += score;
      schoolScoreCount++;
      final entry = studentAgg.putIfAbsent(
        studentId,
        () => _StudentScoreAgg(
          student: studentById[studentId] ??
              _StudentLite(
                id: studentId,
                name: 'Estudiante',
                gradeId: '',
                gradeName: 'Sin grado',
                gender: _GenderBucket.unknown,
              ),
        ),
      );
      entry.sum += score;
      entry.count += 1;
      final subject = _firstNonEmpty([data['subjectName'], data['asignatura']], fallback: 'Asignatura');
      if (score > entry.bestScore) {
        entry.bestScore = score;
        entry.bestSubject = subject;
      }
    }

    final overallAverage = schoolScoreCount == 0 ? 0.0 : schoolScoreSum / schoolScoreCount;
    final topStudents = studentAgg.values
        .where((e) => e.count > 0)
        .map(
          (e) => _StudentRanking(
            studentName: e.student.name,
            gradeName: e.student.gradeName,
            average: e.sum / e.count,
            bestSubject: e.bestSubject,
          ),
        )
        .toList()
      ..sort((a, b) => b.average.compareTo(a.average));

    int attendancePresent = 0;
    int attendanceAbsent = 0;
    int attendanceExcused = 0;
    for (final sheet in attendanceSnap.docs) {
      final rows = await sheet.reference.collection('rows').get();
      for (final row in rows.docs) {
        for (final entry in row.data().entries) {
          if (!entry.key.startsWith('m_')) continue;
          switch ((entry.value ?? '').toString().trim().toUpperCase()) {
            case 'P':
              attendancePresent++;
              break;
            case 'A':
              attendanceAbsent++;
              break;
            case 'E':
              attendanceExcused++;
              break;
          }
        }
      }
    }

    int tasksPublished = tasksSnap.docs.length;
    int taskDeliveries = 0;
    for (final task in tasksSnap.docs) {
      final submissions = await task.reference.collection('submissions').get();
      taskDeliveries += submissions.docs.length;
    }

    final plans = plansSnap.docs.map((d) => d.data()).toList();
    final teacherPerformance = <_TeacherPerformance>[];
    for (final teacher in teachers) {
      final teacherStudentCount = students.where((s) {
        if (teacher.gradeIds.contains(s.gradeId)) return true;
        final studentGradeNorm = _norm(s.gradeName);
        return teacher.gradeNames.map(_norm).contains(studentGradeNorm);
      }).length;

      final teacherPlans = plans.where((data) {
        final dataTeacherDocId = _firstNonEmpty([data['teacherDocId']]);
        final dataTeacherUid = _firstNonEmpty([data['teacherUid']]);
        final dataGradeId = _firstNonEmpty([data['gradeId']]);
        final dataGradeName = _norm(_firstNonEmpty([data['grado'], data['grade']]));
        final matchesTeacher = dataTeacherDocId == teacher.teacherId ||
            (teacher.teacherUid.isNotEmpty && dataTeacherUid == teacher.teacherUid);
        final matchesGrade = teacher.gradeIds.contains(dataGradeId) ||
            teacher.gradeNames.map(_norm).contains(dataGradeName);
        return matchesTeacher || matchesGrade;
      }).toList();

      int completedPlans = 0;
      for (final plan in teacherPlans) {
        final units = _extractUnits(plan);
        if (units.isNotEmpty &&
            units.every(
              (u) => _norm(_firstNonEmpty([u['estado'], u['status']])) == 'completed',
            )) {
          completedPlans++;
        }
      }

      final planRate = teacherPlans.isEmpty ? 0.0 : completedPlans / teacherPlans.length;
      final activeScore = teacher.enabled ? 1.0 : 0.35;
      final coverageScore = students.isEmpty ? 0.0 : (teacherStudentCount / students.length).clamp(0.0, 1.0);
      final performance = (planRate * 0.55) + (activeScore * 0.25) + (coverageScore * 0.20);

      teacherPerformance.add(
        _TeacherPerformance(
          name: teacher.name,
          level: teacher.level,
          studentsCount: teacherStudentCount,
          subjectsCount: teacher.subjectNames.length,
          plansCount: teacherPlans.length,
          completedPlans: completedPlans,
          enabled: teacher.enabled,
          score: performance,
        ),
      );
    }

    teacherPerformance.sort((a, b) => b.score.compareTo(a.score));

    final gradeBreakdown = gradeCounter.entries
        .map((e) => _GradeStat(label: e.key, count: e.value))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    final keySubjects = <String, int>{};
    for (final teacher in teachers) {
      for (final subject in teacher.subjectNames) {
        final clean = subject.trim();
        if (clean.isEmpty) continue;
        keySubjects[clean] = (keySubjects[clean] ?? 0) + 1;
      }
    }
    final subjectCoverage = keySubjects.entries
        .map((e) => _SimpleStat(label: e.key, value: e.value))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final insights = <String>[];
    if (overallAverage < 70 && schoolScoreCount > 0) {
      insights.add('El promedio general está por debajo de 70. Conviene revisar acompañamiento académico y refuerzo por asignatura.');
    }
    if (attendanceAbsent > attendancePresent * 0.18 && (attendancePresent + attendanceAbsent + attendanceExcused) > 0) {
      insights.add('La ausencia acumulada es alta. Vale la pena revisar seguimiento familiar y alertas tempranas por grado.');
    }
    if (pendingTeachers > 0) {
      insights.add('Hay docentes pendientes de activación o regularización. Eso puede afectar continuidad y carga docente.');
    }
    if (teacherPerformance.isNotEmpty && teacherPerformance.first.score >= 0.8) {
      insights.add('Hay docentes con buen nivel de cumplimiento. Puede ser útil tomar sus prácticas como referencia interna.');
    }
    if (tasksPublished == 0) {
      insights.add('No hay tareas publicadas registradas. Conviene revisar si el uso del módulo está activo en todos los grados.');
    }
    if (insights.isEmpty) {
      insights.add('La escuela tiene una base estable. El siguiente paso útil es afinar seguimiento por grado y asignatura para detectar oportunidades puntuales.');
    }

    return _AnalyticsData(
      schoolName: widget.escuela.nombre.trim().isEmpty ? 'Escuela' : widget.escuela.nombre.trim(),
      createdAt: widget.escuela.fecha,
      totalStudents: students.length,
      girls: girls,
      boys: boys,
      undefinedGender: undefinedGender,
      totalTeachers: teachers.length,
      activeTeachers: activeTeachers,
      pendingTeachers: pendingTeachers,
      overallAverage: overallAverage,
      gradedRecords: schoolScoreCount,
      attendancePresent: attendancePresent,
      attendanceAbsent: attendanceAbsent,
      attendanceExcused: attendanceExcused,
      tasksPublished: tasksPublished,
      taskDeliveries: taskDeliveries,
      topStudents: topStudents.take(5).toList(),
      topTeachers: teacherPerformance.take(5).toList(),
      gradeBreakdown: gradeBreakdown.take(8).toList(),
      subjectCoverage: subjectCoverage,
      insights: insights,
      planCount: plans.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<_AnalyticsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.query_stats_rounded, size: 56, color: _blue.withOpacity(0.7)),
                    const SizedBox(height: 12),
                    Text(
                      'No pude cargar los reportes.',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.grey.shade900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Intentar otra vez'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data!;
          final attendanceTotal = data.attendancePresent + data.attendanceAbsent + data.attendanceExcused;
          final attendanceRate = attendanceTotal == 0 ? 0.0 : data.attendancePresent / attendanceTotal;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                SchoolAnalysisHeader(
                  title: data.schoolName,
                  subtitle: 'Vista ejecutiva para entender desempeño académico, estructura docente y oportunidades de mejora.',
                  createdAt: data.createdAt,
                  attendanceRate: attendanceRate,
                  totalStudents: data.totalStudents,
                  totalTeachers: data.totalTeachers,
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > 980;
                    final cards = [
                      _StatCard(
                        title: 'Alumnos',
                        value: '${data.totalStudents}',
                        subtitle: '${data.girls} niñas · ${data.boys} niños',
                        icon: Icons.groups_rounded,
                        toneColor: _blue,
                        toneBg: _blueSoft,
                      ),
                      _StatCard(
                        title: 'Docentes',
                        value: '${data.totalTeachers}',
                        subtitle: '${data.activeTeachers} activos · ${data.pendingTeachers} pendientes',
                        icon: Icons.school_rounded,
                        toneColor: _green,
                        toneBg: _greenSoft,
                      ),
                      _StatCard(
                        title: 'Promedio general',
                        value: data.gradedRecords == 0 ? '--' : data.overallAverage.toStringAsFixed(1),
                        subtitle: '${data.gradedRecords} registros de calificación',
                        icon: Icons.auto_graph_rounded,
                        toneColor: _orange,
                        toneBg: _orangeSoft,
                      ),
                      _StatCard(
                        title: 'Planificaciones',
                        value: '${data.planCount}',
                        subtitle: '${data.tasksPublished} tareas publicadas',
                        icon: Icons.fact_check_rounded,
                        toneColor: _red,
                        toneBg: _redSoft,
                      ),
                    ];
                    if (wide) {
                      return Row(
                        children: [
                          for (int i = 0; i < cards.length; i++) ...[
                            Expanded(child: cards[i]),
                            if (i != cards.length - 1) const SizedBox(width: 12),
                          ]
                        ],
                      );
                    }
                    return Column(
                      children: [
                        for (int i = 0; i < cards.length; i++) ...[
                          cards[i],
                          if (i != cards.length - 1) const SizedBox(height: 12),
                        ]
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth > 1120;
                    final left = [
                      _SectionCard(
                        title: 'Panorama de alumnos',
                        subtitle: 'Distribución básica de la matrícula y presencia por grado.',
                        icon: Icons.pie_chart_outline_rounded,
                        child: Column(
                          children: [
                            SchoolMetricGrid(
                              children: [
                                _MetricTile(
                                    label: 'Niñas',
                                    value: '${data.girls}',
                                    helper: _percent(data.girls, data.totalStudents),
                                    color: const Color(0xFFDB2777),
                                  ),

                                _MetricTile(
                                    label: 'Niños',
                                    value: '${data.boys}',
                                    helper: _percent(data.boys, data.totalStudents),
                                    color: _blue,
                                  ),

                                _MetricTile(
                                    label: 'Sin dato',
                                    value: '${data.undefinedGender}',
                                    helper: _percent(data.undefinedGender, data.totalStudents),
                                    color: Colors.grey.shade700,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ...data.gradeBreakdown.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _BarLine(
                                  label: item.label,
                                  value: item.count,
                                  maxValue: data.gradeBreakdown.isEmpty
                                      ? 1
                                      : data.gradeBreakdown.map((e) => e.count).reduce(math.max),
                                  color: _blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: 'Top estudiantes',
                        subtitle: 'Mayor promedio acumulado según calificaciones publicadas.',
                        icon: Icons.emoji_events_outlined,
                        child: data.topStudents.isEmpty
                            ? const _EmptyState(message: 'Aún no hay suficientes calificaciones para rankear estudiantes.')
                            : Column(
                                children: [
                                  for (int i = 0; i < data.topStudents.length; i++) ...[
                                    _StudentRankTile(rank: i + 1, item: data.topStudents[i]),
                                    if (i != data.topStudents.length - 1) const SizedBox(height: 10),
                                  ],
                                ],
                              ),
                      ),
                    ];

                    final right = [
                      _SectionCard(
                        title: 'Desempeño docente',
                        subtitle: 'Ranking interno con peso mayor en planificación y continuidad.',
                        icon: Icons.workspace_premium_outlined,
                        child: data.topTeachers.isEmpty
                            ? const _EmptyState(message: 'No hay suficientes datos de docentes para generar ranking.')
                            : Column(
                                children: [
                                  for (int i = 0; i < data.topTeachers.length; i++) ...[
                                    _TeacherRankTile(rank: i + 1, item: data.topTeachers[i]),
                                    if (i != data.topTeachers.length - 1) const SizedBox(height: 10),
                                  ],
                                ],
                              ),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: 'Operacion escolar',
                        subtitle: 'Lectura rápida de asistencia, tareas y cobertura de asignaturas.',
                        icon: Icons.analytics_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SchoolMetricGrid(
                              children: [
                                _MetricTile(
                                    label: 'Presentes',
                                    value: '${data.attendancePresent}',
                                    helper: _percent(data.attendancePresent, attendanceTotal),
                                    color: _green,
                                  ),

                                _MetricTile(
                                    label: 'Ausentes',
                                    value: '${data.attendanceAbsent}',
                                    helper: _percent(data.attendanceAbsent, attendanceTotal),
                                    color: _red,
                                  ),

                                _MetricTile(
                                    label: 'Excusas',
                                    value: '${data.attendanceExcused}',
                                    helper: _percent(data.attendanceExcused, attendanceTotal),
                                    color: _orange,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SchoolMetricGrid(
                              children: [
                                _MetricTile(
                                    label: 'Tareas publicadas',
                                    value: '${data.tasksPublished}',
                                    helper: '${data.taskDeliveries} entregas registradas',
                                    color: _blue,
                                  ),

                                _MetricTile(
                                    label: 'Asignaturas cubiertas',
                                    value: '${data.subjectCoverage.length}',
                                    helper: 'Según asignaciones docentes',
                                    color: _green,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ...data.subjectCoverage.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _BarLine(
                                  label: item.label,
                                  value: item.value,
                                  maxValue: data.subjectCoverage.isEmpty
                                      ? 1
                                      : data.subjectCoverage.map((e) => e.value).reduce(math.max),
                                  color: _orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ];

                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Column(children: left)),
                          const SizedBox(width: 14),
                          Expanded(child: Column(children: right)),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        ...left,
                        const SizedBox(height: 14),
                        ...right,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'Recomendaciones de gestión',
                  subtitle: 'Sugerencias automáticas para ayudar a la administración a priorizar mejoras.',
                  icon: Icons.tips_and_updates_outlined,
                  child: Column(
                    children: [
                      for (int i = 0; i < data.insights.length; i++) ...[
                        _InsightTile(
                          index: i + 1,
                          message: data.insights[i],
                        ),
                        if (i != data.insights.length - 1) const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );

    if (widget.embedded) {
      return ColoredBox(color: _bg, child: body);
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        leading: AdminBackButton(onBack: widget.onBack),
        title: const Text('Reportes y Analisis'),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
    );
  }

  String _percent(int value, int total) {
    if (total <= 0) return '0%';
    return '${((value / total) * 100).toStringAsFixed(1)}%';
  }

  String _firstNonEmpty(List<dynamic> values, {String fallback = ''}) {
    for (final value in values) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return fallback;
  }

  String _norm(String value) =>
      value
          .toLowerCase()
          .trim()
          .replaceAll('á', 'a')
          .replaceAll('é', 'e')
          .replaceAll('í', 'i')
          .replaceAll('ó', 'o')
          .replaceAll('ú', 'u')
          .replaceAll('ñ', 'n');

  _GenderBucket _genderBucket(Map<String, dynamic> data) {
    final raw = _norm(_firstNonEmpty([data['sexo'], data['genero'], data['gender']]));
    if (raw.contains('femen') || raw.contains('mujer') || raw.contains('nina') || raw == 'f') {
      return _GenderBucket.female;
    }
    if (raw.contains('mascul') || raw.contains('hombre') || raw.contains('nino') || raw == 'm') {
      return _GenderBucket.male;
    }
    return _GenderBucket.unknown;
  }

  String _studentName(Map<String, dynamic> data) {
    final full = _firstNonEmpty([
      data['nombreCompleto'],
      data['fullName'],
      data['displayName'],
      data['name'],
    ]);
    if (full.isNotEmpty) return full;

    final names = _firstNonEmpty([data['nombres'], data['nombre'], data['firstName']]);
    final last = _firstNonEmpty([data['apellidos'], data['apellido'], data['lastName']]);
    final joined = '$names $last'.trim();
    return joined.isEmpty ? 'Estudiante' : joined;
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString());
  }

  List<Map<String, dynamic>> _extractUnits(Map<String, dynamic> data) {
    final raw = data['unidades'] ?? data['units'];
    if (raw is Iterable) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }
}

enum _GenderBucket { female, male, unknown }

class _AnalyticsData {
  final String schoolName;
  final DateTime createdAt;
  final int totalStudents;
  final int girls;
  final int boys;
  final int undefinedGender;
  final int totalTeachers;
  final int activeTeachers;
  final int pendingTeachers;
  final double overallAverage;
  final int gradedRecords;
  final int attendancePresent;
  final int attendanceAbsent;
  final int attendanceExcused;
  final int tasksPublished;
  final int taskDeliveries;
  final int planCount;
  final List<_StudentRanking> topStudents;
  final List<_TeacherPerformance> topTeachers;
  final List<_GradeStat> gradeBreakdown;
  final List<_SimpleStat> subjectCoverage;
  final List<String> insights;

  const _AnalyticsData({
    required this.schoolName,
    required this.createdAt,
    required this.totalStudents,
    required this.girls,
    required this.boys,
    required this.undefinedGender,
    required this.totalTeachers,
    required this.activeTeachers,
    required this.pendingTeachers,
    required this.overallAverage,
    required this.gradedRecords,
    required this.attendancePresent,
    required this.attendanceAbsent,
    required this.attendanceExcused,
    required this.tasksPublished,
    required this.taskDeliveries,
    required this.planCount,
    required this.topStudents,
    required this.topTeachers,
    required this.gradeBreakdown,
    required this.subjectCoverage,
    required this.insights,
  });
}

class _StudentLite {
  final String id;
  final String name;
  final String gradeId;
  final String gradeName;
  final _GenderBucket gender;

  const _StudentLite({
    required this.id,
    required this.name,
    required this.gradeId,
    required this.gradeName,
    required this.gender,
  });
}

class _StudentScoreAgg {
  final _StudentLite student;
  double sum = 0;
  int count = 0;
  double bestScore = 0;
  String bestSubject = 'Sin datos';

  _StudentScoreAgg({required this.student});
}

class _StudentRanking {
  final String studentName;
  final String gradeName;
  final double average;
  final String bestSubject;

  const _StudentRanking({
    required this.studentName,
    required this.gradeName,
    required this.average,
    required this.bestSubject,
  });
}

class _TeacherLite {
  final String teacherId;
  final String teacherUid;
  final String name;
  final String level;
  final bool enabled;
  final List<String> gradeIds;
  final List<String> gradeNames;
  final List<String> subjectIds;
  final List<String> subjectNames;

  const _TeacherLite({
    required this.teacherId,
    required this.teacherUid,
    required this.name,
    required this.level,
    required this.enabled,
    required this.gradeIds,
    required this.gradeNames,
    required this.subjectIds,
    required this.subjectNames,
  });

  factory _TeacherLite.fromMap({
    required String teacherId,
    required Map<String, dynamic> data,
    required Map<String, String> gradeNameById,
  }) {
    List<String> readList(List<dynamic> raws) {
      final out = <String>[];
      for (final raw in raws) {
        if (raw is Iterable) {
          for (final item in raw) {
            final text = (item ?? '').toString().trim();
            if (text.isNotEmpty && !out.contains(text)) out.add(text);
          }
        } else {
          final text = (raw ?? '').toString().trim();
          if (text.isNotEmpty && !out.contains(text)) out.add(text);
        }
      }
      return out;
    }

    String firstText(List<dynamic> raws, {String fallback = ''}) {
      for (final raw in raws) {
        final text = (raw ?? '').toString().trim();
        if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
      }
      return fallback;
    }

    final gradeIds = readList([
      data['gradeIds'],
      data['gradoIds'],
      data['gradosIds'],
    ]);
    final gradeNames = readList([
      data['gradeNames'],
      data['grades'],
      data['grados'],
      data['gradoLabels'],
      gradeIds.map((e) => gradeNameById[e] ?? ''),
    ]);
    final subjectIds = readList([
      data['subjectIds'],
      data['subjectsIds'],
      data['asignaturaIds'],
    ]);
    final subjectNames = readList([
      data['subjectNames'],
      data['subjects'],
      data['asignaturas'],
      data['materias'],
    ]);

    final names = firstText([
      data['nombreCompleto'],
      data['displayName'],
      data['name'],
      data['fullName'],
      data['teacherName'],
    ]);
    final firstName = firstText([data['nombre'], data['nombres'], data['firstName']]);
    final lastName = firstText([data['apellido'], data['apellidos'], data['lastName']]);

    return _TeacherLite(
      teacherId: teacherId,
      teacherUid: firstText([data['authUid'], data['uid'], data['teacherUid']]),
      name: names.isNotEmpty ? names : ('$firstName $lastName'.trim().isEmpty ? 'Docente' : '$firstName $lastName'.trim()),
      level: firstText([data['nivel'], data['level']], fallback: 'Sin nivel'),
      enabled: data['enabled'] == true || data['active'] == true,
      gradeIds: gradeIds,
      gradeNames: gradeNames,
      subjectIds: subjectIds,
      subjectNames: subjectNames,
    );
  }

  _TeacherLite merge(_TeacherLite other) {
    List<String> mergeList(List<String> a, List<String> b) {
      final out = <String>[];
      for (final item in [...a, ...b]) {
        final clean = item.trim();
        if (clean.isNotEmpty && !out.contains(clean)) out.add(clean);
      }
      return out;
    }

    String prefer(String a, String b, {Set<String> generic = const {}}) {
      final av = a.trim();
      final bv = b.trim();
      final aOk = av.isNotEmpty && !generic.contains(av.toLowerCase());
      final bOk = bv.isNotEmpty && !generic.contains(bv.toLowerCase());
      if (aOk && !bOk) return av;
      if (bOk && !aOk) return bv;
      if (aOk && bOk) return bv.length > av.length ? bv : av;
      return bv.isNotEmpty ? bv : av;
    }

    return _TeacherLite(
      teacherId: teacherId,
      teacherUid: prefer(teacherUid, other.teacherUid),
      name: prefer(name, other.name, generic: const {'docente'}),
      level: prefer(level, other.level, generic: const {'sin nivel'}),
      enabled: enabled || other.enabled,
      gradeIds: mergeList(gradeIds, other.gradeIds),
      gradeNames: mergeList(gradeNames, other.gradeNames),
      subjectIds: mergeList(subjectIds, other.subjectIds),
      subjectNames: mergeList(subjectNames, other.subjectNames),
    );
  }
}

class _TeacherPerformance {
  final String name;
  final String level;
  final int studentsCount;
  final int subjectsCount;
  final int plansCount;
  final int completedPlans;
  final bool enabled;
  final double score;

  const _TeacherPerformance({
    required this.name,
    required this.level,
    required this.studentsCount,
    required this.subjectsCount,
    required this.plansCount,
    required this.completedPlans,
    required this.enabled,
    required this.score,
  });
}

class _GradeStat {
  final String label;
  final int count;

  const _GradeStat({required this.label, required this.count});
}

class _SimpleStat {
  final String label;
  final int value;

  const _SimpleStat({required this.label, required this.value});
}

class SchoolAnalysisHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final DateTime createdAt;
  final double attendanceRate;
  final int totalStudents;
  final int totalTeachers;

  const SchoolAnalysisHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    required this.attendanceRate,
    required this.totalStudents,
    required this.totalTeachers,
  });

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF1A237E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A237E).withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 900;
          final identity = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.query_stats_rounded, color: Colors.white, size: 30),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.92),
                              fontSize: 15,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _InfoChip(
                      icon: Icons.calendar_today_rounded,
                      label: 'Creada ${_fmtDate(createdAt)}',
                    ),
                    _InfoChip(
                      icon: Icons.groups_rounded,
                      label: '$totalStudents alumnos',
                    ),
                    _InfoChip(
                      icon: Icons.school_rounded,
                      label: '$totalTeachers docentes',
                    ),
                  ],
                ),
              ],
          );

          final scoreCard = Container(
            width: wide ? 220 : double.infinity,
            margin: EdgeInsets.only(left: wide ? 16 : 0, top: wide ? 0 : 18),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withOpacity(0.10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Asistencia escolar',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.88),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(attendanceRate * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: attendanceRate.clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: Colors.white.withOpacity(0.14),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFC857)),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pulso general de presencia acumulada.',
                  style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13),
                ),
              ],
            ),
          );

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Expanded(child: identity), scoreCard],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [identity, scoreCard],
          );
        },
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Flexible(child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color toneColor;
  final Color toneBg;

  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.toneColor,
    required this.toneBg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: toneBg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: toneColor, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.grey.shade900),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F8FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: const Color(0xFF1A237E)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String helper;
  final Color color;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.helper,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 6),
          Text(helper, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
        ],
      ),
    );
  }
}

class _BarLine extends StatelessWidget {
  final String label;
  final int value;
  final int maxValue;
  final Color color;

  const _BarLine({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 10),
            Text('$value', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 10,
            backgroundColor: color.withOpacity(0.10),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _StudentRankTile extends StatelessWidget {
  final int rank;
  final _StudentRanking item;

  const _StudentRankTile({required this.rank, required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: rank == 1 ? const Color(0xFFFFF3DC) : const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              '$rank',
              style: TextStyle(
                color: rank == 1 ? const Color(0xFFF59E0B) : const Color(0xFF1A237E),
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.studentName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  '${item.gradeName} · Mejor área: ${item.bestSubject}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            item.average.toStringAsFixed(1),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24),
          ),
        ],
      ),
    );
  }
}

class _TeacherRankTile extends StatelessWidget {
  final int rank;
  final _TeacherPerformance item;

  const _TeacherRankTile({required this.rank, required this.item});

  @override
  Widget build(BuildContext context) {
    final plansLabel = item.plansCount == 0 ? 'Sin planes' : '${item.completedPlans}/${item.plansCount} planes completos';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: rank == 1 ? const Color(0xFFECFDF3) : const Color(0xFFEAF2FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: rank == 1 ? const Color(0xFF16A34A) : const Color(0xFF1A237E),
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(
                      item.level,
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    ),
                  ],
                ),
              ),
              _StatusPill(enabled: item.enabled),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _MiniInfo(label: 'Alumnos', value: '${item.studentsCount}')),
              const SizedBox(width: 10),
              Expanded(child: _MiniInfo(label: 'Asignaturas', value: '${item.subjectsCount}')),
              const SizedBox(width: 10),
              Expanded(child: _MiniInfo(label: 'Cumplimiento', value: '${(item.score * 100).toStringAsFixed(0)}%')),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(plansLabel, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool enabled;

  const _StatusPill({required this.enabled});

  @override
  Widget build(BuildContext context) {
    final bg = enabled ? const Color(0xFFECFDF3) : const Color(0xFFFFF3DC);
    final fg = enabled ? const Color(0xFF15803D) : const Color(0xFFB45309);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        enabled ? 'Activo' : 'Pendiente',
        style: TextStyle(color: fg, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  final int index;
  final String message;

  const _InsightTile({required this.index, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: const Color(0xFF1A237E),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 15, height: 1.45, color: Colors.grey.shade900),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FBFF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        message,
        style: TextStyle(color: Colors.grey.shade700),
      ),
    );
  }
}
