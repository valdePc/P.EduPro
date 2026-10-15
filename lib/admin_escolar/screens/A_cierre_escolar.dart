import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart';

class ACierreEscolarScreen extends StatefulWidget {
  final Escuela escuela;

  const ACierreEscolarScreen({super.key, required this.escuela});

  @override
  State<ACierreEscolarScreen> createState() => _ACierreEscolarScreenState();
}

class _ACierreEscolarScreenState extends State<ACierreEscolarScreen> {
  static const Color _blue = Color(0xFF1A237E);
  static const Color _orange = Color(0xFFFFA000);
  static const Color _ink = Color(0xFF17243A);
  static const Color _muted = Color(0xFF5C687A);
  static const Color _page = Color(0xFFF4F6FB);
  static const double _approvalThreshold = 70;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late final String _schoolId;
  late final List<_SchoolYearOption> _years;
  String? _selectedSchoolYear;
  List<_GradeOption> _grades = const [];
  String? _selectedGradeId;
  bool _bootLoading = true;
  bool _rowsLoading = true;
  bool _saving = false;
  bool _savingAll = false;
  List<_ClosureRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    _schoolId = normalizeSchoolIdFromEscuela(widget.escuela);
    _years = _buildSchoolYears();
    _selectedSchoolYear = _years.first.id;
    _bootstrap();
  }

  List<_SchoolYearOption> _buildSchoolYears() {
    final now = DateTime.now();
    final start = now.month >= 8 ? now.year : now.year - 1;
    final startYears = <int>[start, start + 1, start - 1, start - 2];
    return startYears
        .toSet()
        .map(
          (year) => _SchoolYearOption(id: '$year-${year + 1}', startYear: year),
        )
        .toList();
  }

  CollectionReference<Map<String, dynamic>> _schoolRef(String path) {
    return _db.collection('schools').doc(_schoolId).collection(path);
  }

  bool _matchesSchoolYearValue(dynamic value, _SchoolYearOption year) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return false;
    final endYear = year.startYear + 1;
    return raw == year.id ||
        raw == year.startYear.toString() ||
        raw == endYear.toString();
  }

  Future<void> _bootstrap() async {
    setState(() => _bootLoading = true);
    try {
      final gradesSnap = await _schoolRef('grados').get();
      final grades =
          gradesSnap.docs
              .map((d) => _GradeOption.fromDoc(d))
              .where((g) => g.id.isNotEmpty && g.label.isNotEmpty)
              .toList()
            ..sort(_compareGrades);

      if (!mounted) return;
      setState(() {
        _grades = grades;
        _selectedGradeId = grades.isNotEmpty ? grades.first.id : null;
      });
      await _loadRows();
    } finally {
      if (mounted) setState(() => _bootLoading = false);
    }
  }

  int _compareGrades(_GradeOption a, _GradeOption b) {
    int nivelRank(String nivel) {
      switch (nivel.trim().toLowerCase()) {
        case 'inicial':
          return 0;
        case 'primaria':
          return 1;
        case 'secundaria':
          return 2;
        default:
          return 3;
      }
    }

    int extractNumber(String text) {
      final match = RegExp(r'(\d+)').firstMatch(text);
      return int.tryParse(match?.group(1) ?? '') ?? 999;
    }

    final byNivel = nivelRank(a.nivel).compareTo(nivelRank(b.nivel));
    if (byNivel != 0) return byNivel;
    final byNumber = extractNumber(a.label).compareTo(extractNumber(b.label));
    if (byNumber != 0) return byNumber;
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  }

  _GradeOption? _gradeById(String? id) {
    if (id == null) return null;
    for (final g in _grades) {
      if (g.id == id) return g;
    }
    return null;
  }

  _GradeOption? _nextGradeFor(String gradeId) {
    final index = _grades.indexWhere((g) => g.id == gradeId);
    if (index < 0 || index + 1 >= _grades.length) return null;
    return _grades[index + 1];
  }

  Future<void> _loadRows() async {
    final selectedGrade = _selectedGradeId;
    final selectedYear =
        _years.where((y) => y.id == _selectedSchoolYear).firstOrNull;
    if (selectedGrade == null || selectedYear == null) {
      if (mounted) setState(() => _rows = []);
      return;
    }

    setState(() => _rowsLoading = true);
    try {
      final rows = await _buildRowsForGrade(
        gradeId: selectedGrade,
        year: selectedYear.startYear,
      );
      if (!mounted) return;
      setState(() => _rows = rows);
    } finally {
      if (mounted) setState(() => _rowsLoading = false);
    }
  }

  Future<List<_ClosureRow>> _buildRowsForGrade({
    required String gradeId,
    required int year,
  }) async {
    final studentsSnap = await _schoolRef('alumnos').get();
    final grade = _gradeById(gradeId);
    final currentStudents =
        studentsSnap.docs.where((d) {
          final data = d.data();
          final currentGradeId =
              (data['gradeId'] ?? data['gradoId'] ?? '').toString().trim();
          final gradeName =
              (data['grado'] ??
                      data['gradeName'] ??
                      data['gradeLabel'] ??
                      data['gradoKey'] ??
                      '')
                  .toString()
                  .trim();
          return currentGradeId == gradeId ||
              (grade != null &&
                  gradeName.toLowerCase() == grade.label.toLowerCase());
        }).toList();

    final gradesV2Snap = await _schoolRef('calificaciones_v2').get();
    final proposalsSnap =
        await _schoolRef('promocion_propuestas')
            .where('schoolYear', isEqualTo: _selectedSchoolYear)
            .where('gradeId', isEqualTo: gradeId)
            .get();

    final byStudent = <String, List<Map<String, dynamic>>>{};
    for (final d in gradesV2Snap.docs) {
      final data = d.data();
      final sid = (data['studentId'] ?? '').toString().trim();
      final gid = (data['gradeId'] ?? '').toString().trim();
      final yearOption = _years.where((y) => y.startYear == year).firstOrNull;
      if (sid.isEmpty ||
          gid != gradeId ||
          (yearOption != null &&
              !_matchesSchoolYearValue(data['year'], yearOption))) {
        continue;
      }
      byStudent.putIfAbsent(sid, () => <Map<String, dynamic>>[]).add(data);
    }

    final proposalByStudent = <String, Map<String, dynamic>>{};
    for (final d in proposalsSnap.docs) {
      final data = d.data();
      final sid = (data['studentId'] ?? '').toString().trim();
      if (sid.isNotEmpty) {
        proposalByStudent[sid] = data;
      }
    }

    final nextGrade = _nextGradeFor(gradeId);

    final rows =
        currentStudents.map((d) {
            final data = d.data();
            final studentId = d.id;
            final studentGrades =
                byStudent[studentId] ?? const <Map<String, dynamic>>[];
            final subjectAverages = _buildSubjectAverages(studentGrades);
            final finals = subjectAverages.map((s) => s.average).toList();
            final hasAnySubjectBelowThreshold = subjectAverages.any(
              (s) => s.average < _approvalThreshold,
            );

            final average =
                finals.isEmpty
                    ? null
                    : finals.reduce((a, b) => a + b) / finals.length;

            final recommendation =
                average == null
                    ? _PromotionDecision.pendiente
                    : !hasAnySubjectBelowThreshold &&
                        average >= _approvalThreshold
                    ? (nextGrade == null
                        ? _PromotionDecision.egresado
                        : _PromotionDecision.aprobado)
                    : _PromotionDecision.reprobado;

            final proposal = proposalByStudent[studentId];
            final teacherSuggestedDecision =
                _PromotionDecisionX.fromValue(
                  (proposal?['suggestedStatus'] ?? '').toString(),
                ) ??
                recommendation;
            final teacherProposedDecision =
                proposal == null
                    ? null
                    : average == null
                    ? _PromotionDecision.pendiente
                    : (_PromotionDecisionX.fromValue(
                          (proposal['proposedStatus'] ?? '').toString(),
                        ) ??
                        recommendation);

            final effectiveDecision =
                teacherProposedDecision ?? _PromotionDecision.pendiente;

            final targetGradeId =
                effectiveDecision == _PromotionDecision.aprobado
                    ? (nextGrade?.id ?? gradeId)
                    : gradeId;

            return _ClosureRow(
              alumnoId: studentId,
              alumnoNombre: _studentName(data, studentId),
              matricula:
                  (data['matricula'] ?? data['codigo'] ?? '').toString().trim(),
              average: average,
              subjectCount: subjectAverages.length,
              subjectAverages: subjectAverages,
              decision: effectiveDecision,
              targetGradeId:
                  effectiveDecision == _PromotionDecision.egresado
                      ? null
                      : targetGradeId,
              recommendation: recommendation,
              teacherSuggestedDecision: teacherSuggestedDecision,
              teacherProposedDecision: teacherProposedDecision,
              teacherComment:
                  (proposal?['teacherComment'] ?? '').toString().trim(),
              hasTeacherOverride:
                  proposal != null &&
                  teacherProposedDecision != teacherSuggestedDecision,
              readyForAdmin: average != null && proposal != null,
            );
          }).toList()
          ..sort(
            (a, b) => a.alumnoNombre.toLowerCase().compareTo(
              b.alumnoNombre.toLowerCase(),
            ),
          );

    return rows;
  }

  List<_SubjectAverage> _buildSubjectAverages(
    List<Map<String, dynamic>> grades,
  ) {
    final bySubject = <String, List<double>>{};
    final subjectNames = <String, String>{};

    for (final grade in grades) {
      final computed = grade['computed'];
      final finalValue = computed is Map ? computed['final'] : null;
      final finalNumber = finalValue is num ? finalValue.toDouble() : null;
      if (finalNumber == null) continue;

      final subjectId =
          (grade['subjectId'] ??
                  grade['subjectDocId'] ??
                  grade['asignaturaId'] ??
                  grade['materiaId'] ??
                  '')
              .toString()
              .trim();
      final subjectName =
          (grade['subjectName'] ??
                  grade['asignatura'] ??
                  grade['materia'] ??
                  subjectId)
              .toString()
              .trim();
      final key = subjectId.isNotEmpty ? subjectId : subjectName.toLowerCase();
      if (key.isEmpty) continue;

      bySubject.putIfAbsent(key, () => <double>[]).add(finalNumber);
      if (subjectName.isNotEmpty) {
        subjectNames[key] = subjectName;
      }
    }

    final items =
        bySubject.entries
            .map((entry) {
              final values = entry.value;
              if (values.isEmpty) return null;
              final avg = values.reduce((a, b) => a + b) / values.length;
              return _SubjectAverage(
                subjectKey: entry.key,
                subjectName: subjectNames[entry.key] ?? entry.key,
                average: avg,
              );
            })
            .whereType<_SubjectAverage>()
            .toList()
          ..sort(
            (a, b) => a.subjectName.toLowerCase().compareTo(
              b.subjectName.toLowerCase(),
            ),
          );

    return items;
  }

  String _studentName(Map<String, dynamic> data, String id) {
    final nombre = (data['nombre'] ?? data['nombres'] ?? '').toString().trim();
    final apellido =
        (data['apellido'] ?? data['apellidos'] ?? '').toString().trim();
    final full = '$nombre $apellido'.trim();
    if (full.isNotEmpty) return full;
    return 'Alumno $id';
  }

  Future<void> _saveClosure() async {
    if (_selectedGradeId == null ||
        _selectedSchoolYear == null ||
        _rows.isEmpty)
      return;
    if (_rows.any((r) => !r.readyForAdmin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hay alumnos sin nota final o sin confirmacion del docente. No se puede cerrar todavia.',
          ),
        ),
      );
      return;
    }
    final currentYear =
        _years.where((y) => y.id == _selectedSchoolYear).firstOrNull;
    final grade = _gradeById(_selectedGradeId);
    if (currentYear == null || grade == null) return;

    setState(() => _saving = true);

    try {
      await _saveClosureForGrade(
        schoolYearId: _selectedSchoolYear!,
        currentYear: currentYear,
        grade: grade,
        rows: _rows,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cierre escolar guardado correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el cierre: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveClosureForGrade({
    required String schoolYearId,
    required _SchoolYearOption currentYear,
    required _GradeOption grade,
    required List<_ClosureRow> rows,
  }) async {
    final batch = _db.batch();
    final closedAt = Timestamp.now();
    final nextYearLabel =
        '${currentYear.startYear + 1}-${currentYear.startYear + 2}';
    final authUser = _auth.currentUser;
    final actorUid = authUser?.uid;
    final actorEmail = authUser?.email?.trim();

    for (final row in rows) {
      final studentRef = _schoolRef('alumnos').doc(row.alumnoId);
      final historyRef = studentRef
          .collection('historial_academico')
          .doc(schoolYearId);
      final targetGrade = _gradeById(row.targetGradeId);

      batch.set(historyRef, {
        'schoolYear': schoolYearId,
        'startYear': currentYear.startYear,
        'gradeId': grade.id,
        'gradeName': grade.label,
        'decision': row.decision.value,
        'finalAverage': row.average,
        'evaluatedSubjects': row.subjectCount,
        'subjectAverages':
            row.subjectAverages
                .map(
                  (s) => {
                    'subjectKey': s.subjectKey,
                    'subjectName': s.subjectName,
                    'average': s.average,
                    'belowThreshold': s.average < _approvalThreshold,
                  },
                )
                .toList(),
        'targetGradeId': targetGrade?.id,
        'targetGradeName': targetGrade?.label,
        'teacherSuggestedDecision': row.teacherSuggestedDecision?.value,
        'teacherProposedDecision': row.teacherProposedDecision?.value,
        'teacherComment': row.teacherComment,
        'teacherOverride': row.hasTeacherOverride,
        'closedAt': closedAt,
        'closedByUid': actorUid,
        'closedByEmail': actorEmail,
        'source': 'admin_cierre_escolar',
      }, SetOptions(merge: true));

      final update = <String, dynamic>{
        'promotionStatus': row.decision.value,
        'promotionClosedAt': closedAt,
        'lastClosedSchoolYear': schoolYearId,
        'finalAverage': row.average,
      };

      if (row.decision == _PromotionDecision.egresado) {
        update.addAll({'academicStatus': 'egresado', 'egresado': true});
      } else {
        update.addAll({
          'academicStatus':
              row.decision == _PromotionDecision.reprobado
                  ? 'repite'
                  : 'activo',
          'schoolYear': nextYearLabel,
          'anioEscolar': nextYearLabel,
          'gradeId': targetGrade?.id ?? grade.id,
          'gradoId': targetGrade?.id ?? grade.id,
          'gradeName': targetGrade?.label ?? grade.label,
          'gradeLabel': targetGrade?.label ?? grade.label,
          'grado': targetGrade?.label ?? grade.label,
          'gradoKey': targetGrade?.label ?? grade.label,
          'egresado': false,
        });
      }

      batch.update(studentRef, update);
    }

    final closureRef = _schoolRef(
      'cierres_escolares',
    ).doc('${schoolYearId}_${grade.id}');
    batch.set(closureRef, {
      'schoolYear': schoolYearId,
      'startYear': currentYear.startYear,
      'gradeId': grade.id,
      'gradeName': grade.label,
      'totalStudents': rows.length,
      'approved':
          rows.where((r) => r.decision == _PromotionDecision.aprobado).length,
      'repeated':
          rows.where((r) => r.decision == _PromotionDecision.reprobado).length,
      'graduated':
          rows.where((r) => r.decision == _PromotionDecision.egresado).length,
      'pending':
          rows.where((r) => r.decision == _PromotionDecision.pendiente).length,
      'updatedAt': closedAt,
      'closedByUid': actorUid,
      'closedByEmail': actorEmail,
      'source': 'admin_cierre_escolar',
    }, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> _saveAllGrades() async {
    final currentYear =
        _years.where((y) => y.id == _selectedSchoolYear).firstOrNull;
    if (currentYear == null || _grades.isEmpty) return;

    setState(() => _savingAll = true);
    int processed = 0;
    final incompleteGrades = <String>[];
    try {
      for (final grade in _grades) {
        final rows = await _buildRowsForGrade(
          gradeId: grade.id,
          year: currentYear.startYear,
        );
        if (rows.isEmpty) continue;
        if (rows.any((r) => !r.readyForAdmin)) {
          incompleteGrades.add(grade.label);
          continue;
        }
        await _saveClosureForGrade(
          schoolYearId: _selectedSchoolYear!,
          currentYear: currentYear,
          grade: grade,
          rows: rows,
        );
        processed++;
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      if (incompleteGrades.isNotEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Faltan notas finales en: ${incompleteGrades.join(', ')}.',
            ),
          ),
        );
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            processed == 0
                ? 'No habia grados listos para cerrar.'
                : 'Cierre masivo completado en $processed grado(s).',
          ),
        ),
      );
      await _loadRows();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo completar el cierre masivo: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingAll = false);
    }
  }

  void _setDecision(String alumnoId, _PromotionDecision decision) {
    final currentGradeId = _selectedGradeId;
    if (currentGradeId == null) return;
    final nextGrade = _nextGradeFor(currentGradeId);
    setState(() {
      _rows =
          _rows.map((row) {
            if (row.alumnoId != alumnoId) return row;
            return row.copyWith(
              decision: decision,
              targetGradeId:
                  decision == _PromotionDecision.egresado
                      ? null
                      : decision == _PromotionDecision.aprobado
                      ? (nextGrade?.id ?? currentGradeId)
                      : currentGradeId,
            );
          }).toList();
    });
  }

  void _setTargetGrade(String alumnoId, String? gradeId) {
    setState(() {
      _rows =
          _rows.map((row) {
            if (row.alumnoId != alumnoId) return row;
            return row.copyWith(targetGradeId: gradeId);
          }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasIncomplete = _rows.any((r) => !r.readyForAdmin);
    final approved =
        _rows.where((r) => r.decision == _PromotionDecision.aprobado).length;
    final repeated =
        _rows.where((r) => r.decision == _PromotionDecision.reprobado).length;
    final graduated =
        _rows.where((r) => r.decision == _PromotionDecision.egresado).length;
    final pending =
        _rows.where((r) => r.decision == _PromotionDecision.pendiente).length;
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    final selectorWidth = isCompact ? double.infinity : 320.0;

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: const Text('Cierre del año escolar'),
      ),
      body:
          _bootLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 14 : 28,
                  vertical: isCompact ? 16 : 24,
                ),
                children: [
                  Container(
                    padding: EdgeInsets.all(isCompact ? 20 : 26),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_blue, Color(0xFF303F9F)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: _blue.withOpacity(0.16),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: isCompact ? 48 : 58,
                          height: isCompact ? 48 : 58,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: Icon(
                            Icons.event_available_rounded,
                            color: Colors.white,
                            size: isCompact ? 26 : 30,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cierre del año escolar',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Revisa resultados, confirma promociones y conserva el historial académico.',
                                style: TextStyle(
                                  color: Color(0xFFE8EAF6),
                                  fontSize: 14,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _panel(
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _dropdownCard(
                          width: selectorWidth,
                          label: 'Año escolar a cerrar',
                          child: DropdownButtonFormField<String>(
                            value: _selectedSchoolYear,
                            isExpanded: true,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            items:
                                _years
                                    .map(
                                      (y) => DropdownMenuItem(
                                        value: y.id,
                                        child: Text(y.id),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (value) async {
                              setState(() => _selectedSchoolYear = value);
                              await _loadRows();
                            },
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFFF8F9FC),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(13),
                                borderSide: const BorderSide(
                                  color: Color(0xFFDCE3EE),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(13),
                                borderSide: const BorderSide(
                                  color: Color(0xFFDCE3EE),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(13),
                                borderSide: const BorderSide(
                                  color: _blue,
                                  width: 1.5,
                                ),
                              ),
                              isDense: true,
                            ),
                          ),
                        ),
                        _dropdownCard(
                          width: selectorWidth,
                          label: 'Grado',
                          child: DropdownButtonFormField<String>(
                            value: _selectedGradeId,
                            isExpanded: true,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            items:
                                _grades
                                    .map(
                                      (g) => DropdownMenuItem(
                                        value: g.id,
                                        child: Text(g.label),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (value) async {
                              setState(() => _selectedGradeId = value);
                              await _loadRows();
                            },
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFFF8F9FC),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(13),
                                borderSide: const BorderSide(
                                  color: Color(0xFFDCE3EE),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(13),
                                borderSide: const BorderSide(
                                  color: Color(0xFFDCE3EE),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(13),
                                borderSide: const BorderSide(
                                  color: _blue,
                                  width: 1.5,
                                ),
                              ),
                              isDense: true,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: selectorWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Cierre masivo',
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed:
                                    _savingAll ||
                                            _saving ||
                                            _grades.isEmpty ||
                                            hasIncomplete
                                        ? null
                                        : _saveAllGrades,
                                icon:
                                    _savingAll
                                        ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                        : const Icon(
                                          Icons.auto_fix_high_rounded,
                                        ),
                                label: const Text('Cerrar todos los grados'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _orange,
                                  foregroundColor: _ink,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 10),
                    child: Text(
                      'Resumen del grado',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _summaryCard(
                        'Total',
                        _rows.length.toString(),
                        Icons.groups_rounded,
                        Colors.blue,
                      ),
                      _summaryCard(
                        'Aprobados',
                        approved.toString(),
                        Icons.trending_up_rounded,
                        Colors.green,
                      ),
                      _summaryCard(
                        'Reprueban',
                        repeated.toString(),
                        Icons.replay_circle_filled_rounded,
                        Colors.deepOrange,
                      ),
                      _summaryCard(
                        'Egresan',
                        graduated.toString(),
                        Icons.school_rounded,
                        Colors.purple,
                      ),
                      _summaryCard(
                        'Pendientes',
                        pending.toString(),
                        Icons.pending_actions_rounded,
                        Colors.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (hasIncomplete)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Text(
                          'Hay alumnos sin nota final o sin confirmacion del docente. Administracion no podra cerrar este grado ni hacer el cierre masivo hasta que ese paso quede completo.',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  _panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Decisión académica por estudiante',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Aqui cerramos el año, guardamos historial y preparamos el siguiente periodo sin perder el registro anterior.',
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_rowsLoading)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_rows.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No hay estudiantes en este grado para el año seleccionado.',
                              style: TextStyle(color: _muted, fontSize: 15),
                            ),
                          )
                        else
                          ..._rows.map(
                            (row) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _studentCard(row),
                            ),
                          ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: isCompact ? double.infinity : null,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed:
                                  _saving || _rows.isEmpty || hasIncomplete
                                      ? null
                                      : _saveClosure,
                              icon:
                                  _saving
                                      ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                      : const Icon(Icons.save_rounded),
                              label: const Text('Guardar cierre escolar'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5EAF2)),
        boxShadow: [
          BoxShadow(
            color: _blue.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _dropdownCard({
    required double width,
    required String label,
    required Widget child,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _ink,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 9),
          child,
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _studentCard(_ClosureRow row) {
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    final formWidth = isCompact ? double.infinity : 280.0;
    return Container(
      padding: EdgeInsets.all(isCompact ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5EAF2)),
        boxShadow: [
          BoxShadow(
            color: _blue.withOpacity(0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.alumnoNombre,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (row.matricula.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Matrícula ${row.matricula}',
                        style: const TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Chip(
                label: Text('${row.subjectCount} asignaturas'),
                backgroundColor: Colors.blue.shade50,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              SizedBox(
                width: formWidth,
                child: DropdownButtonFormField<_PromotionDecision>(
                  value: row.decision,
                  items:
                      _PromotionDecision.values
                          .map(
                            (d) => DropdownMenuItem(
                              value: d,
                              child: Text(d.label),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value != null && row.readyForAdmin) {
                      _setDecision(row.alumnoId, value);
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: 'Decisión administrativa final',
                    filled: true,
                    fillColor: Color(0xFFF8F9FC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: formWidth,
                child: DropdownButtonFormField<String?>(
                  value: row.targetGradeId,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Sin siguiente grado'),
                    ),
                    ..._grades.map(
                      (g) => DropdownMenuItem<String?>(
                        value: g.id,
                        child: Text(g.label),
                      ),
                    ),
                  ],
                  onChanged:
                      row.decision == _PromotionDecision.egresado ||
                              !row.readyForAdmin
                          ? null
                          : (value) => _setTargetGrade(row.alumnoId, value),
                  decoration: const InputDecoration(
                    labelText: 'Siguiente grado',
                    filled: true,
                    fillColor: Color(0xFFF8F9FC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              Chip(
                label: Text('Sistema: ${row.recommendation.label}'),
                backgroundColor: Colors.purple.shade50,
              ),
              Chip(
                label: Text(
                  row.readyForAdmin
                      ? 'Docente: ${row.teacherProposedDecision?.label ?? row.recommendation.label}'
                      : 'Docente: falta completar',
                ),
                backgroundColor: Colors.teal.shade50,
              ),
              if (row.hasTeacherOverride)
                Chip(
                  label: const Text('El docente cambio la sugerencia'),
                  backgroundColor: Colors.amber.shade50,
                ),
            ],
          ),
          if (row.subjectAverages.isNotEmpty) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Promedios finales por asignatura',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade900,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children:
                  row.subjectAverages.map((subject) {
                    final isLow = subject.average < _approvalThreshold;
                    return Container(
                      constraints: const BoxConstraints(
                        minWidth: 220,
                        maxWidth: 320,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isLow ? const Color(0xFFFFF1F1) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color:
                              isLow
                                  ? const Color(0xFFE57373)
                                  : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  subject.subjectName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color:
                                        isLow
                                            ? Colors.red.shade800
                                            : Colors.grey.shade900,
                                  ),
                                ),
                                if (isLow)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Debajo de 70',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.red.shade700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            subject.average.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color:
                                  isLow
                                      ? Colors.red.shade800
                                      : Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
            ),
          ],
          if (row.teacherComment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                'Comentario del docente: ${row.teacherComment}',
                style: TextStyle(color: Colors.grey.shade800),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SchoolYearOption {
  final String id;
  final int startYear;

  const _SchoolYearOption({required this.id, required this.startYear});
}

class _GradeOption {
  final String id;
  final String label;
  final String nivel;

  const _GradeOption({
    required this.id,
    required this.label,
    required this.nivel,
  });

  factory _GradeOption.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return _GradeOption(
      id: (data['gradeId'] ?? doc.id).toString().trim(),
      label: (data['name'] ?? data['grado'] ?? doc.id).toString().trim(),
      nivel: (data['nivel'] ?? '').toString().trim(),
    );
  }
}

class _ClosureRow {
  final String alumnoId;
  final String alumnoNombre;
  final String matricula;
  final double? average;
  final int subjectCount;
  final List<_SubjectAverage> subjectAverages;
  final _PromotionDecision decision;
  final String? targetGradeId;
  final _PromotionDecision recommendation;
  final _PromotionDecision? teacherSuggestedDecision;
  final _PromotionDecision? teacherProposedDecision;
  final String teacherComment;
  final bool hasTeacherOverride;
  final bool readyForAdmin;

  const _ClosureRow({
    required this.alumnoId,
    required this.alumnoNombre,
    required this.matricula,
    required this.average,
    required this.subjectCount,
    required this.subjectAverages,
    required this.decision,
    required this.targetGradeId,
    required this.recommendation,
    required this.teacherSuggestedDecision,
    required this.teacherProposedDecision,
    required this.teacherComment,
    required this.hasTeacherOverride,
    required this.readyForAdmin,
  });

  _ClosureRow copyWith({_PromotionDecision? decision, String? targetGradeId}) {
    return _ClosureRow(
      alumnoId: alumnoId,
      alumnoNombre: alumnoNombre,
      matricula: matricula,
      average: average,
      subjectCount: subjectCount,
      subjectAverages: subjectAverages,
      decision: decision ?? this.decision,
      targetGradeId: targetGradeId,
      recommendation: recommendation,
      teacherSuggestedDecision: teacherSuggestedDecision,
      teacherProposedDecision: teacherProposedDecision,
      teacherComment: teacherComment,
      hasTeacherOverride: hasTeacherOverride,
      readyForAdmin: readyForAdmin,
    );
  }
}

class _SubjectAverage {
  final String subjectKey;
  final String subjectName;
  final double average;

  const _SubjectAverage({
    required this.subjectKey,
    required this.subjectName,
    required this.average,
  });
}

enum _PromotionDecision {
  aprobado('Aprobado'),
  reprobado('Reprobado'),
  egresado('Egresado'),
  pendiente('Pendiente');

  const _PromotionDecision(this.label);
  final String label;

  String get value {
    switch (this) {
      case _PromotionDecision.aprobado:
        return 'aprobado';
      case _PromotionDecision.reprobado:
        return 'reprobado';
      case _PromotionDecision.egresado:
        return 'egresado';
      case _PromotionDecision.pendiente:
        return 'pendiente';
    }
  }
}

extension _PromotionDecisionX on _PromotionDecision {
  static _PromotionDecision? fromValue(String value) {
    switch (value.trim().toLowerCase()) {
      case 'aprobado':
        return _PromotionDecision.aprobado;
      case 'reprobado':
        return _PromotionDecision.reprobado;
      case 'egresado':
        return _PromotionDecision.egresado;
      case 'pendiente':
        return _PromotionDecision.pendiente;
      default:
        return null;
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
