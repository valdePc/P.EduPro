import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';

class PromocionDocenteScreen extends StatefulWidget {
  final Escuela escuela;
  final String schoolId;
  final String teacherDocId;
  final String teacherName;
  final List<String> gradeIds;
  final List<String> gradeLabels;
  final List<String> teacherTandas;
  final String? initialGradeId;
  final String? initialTanda;

  const PromocionDocenteScreen({
    super.key,
    required this.escuela,
    required this.schoolId,
    required this.teacherDocId,
    required this.teacherName,
    required this.gradeIds,
    required this.gradeLabels,
    required this.teacherTandas,
    this.initialGradeId,
    this.initialTanda,
  });

  @override
  State<PromocionDocenteScreen> createState() => _PromocionDocenteScreenState();
}

class _PromocionDocenteScreenState extends State<PromocionDocenteScreen> {
  static const Color _blue = Color(0xFF0D47A1);
  static const double _approvalThreshold = 70;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<_YearOption> _years = const [];
  List<_GradeLite> _grades = const [];
  String? _selectedYear;
  String? _selectedGradeId;
  List<String> _tandas = const ['Todas'];
  String _selectedTanda = 'Todas';
  bool _loading = true;
  bool _saving = false;
  List<_TeacherProposalRow> _rows = const [];
  int _incompleteStudents = 0;
  int _expectedSubjectCount = 0;

  @override
  void initState() {
    super.initState();
    _years = _defaultYearOptions();
    _selectedYear = _years.first.id;
    _selectedGradeId = widget.initialGradeId?.trim().isNotEmpty == true
        ? widget.initialGradeId!.trim()
        : (widget.gradeIds.isNotEmpty ? widget.gradeIds.first.trim() : null);
    _tandas = _buildTeacherTandas();
    final desiredTanda = _normalizeTanda(widget.initialTanda ?? '');
    _selectedTanda = _tandas.contains(desiredTanda) ? desiredTanda : _tandas.first;
    _bootstrap();
  }

  List<_YearOption> _defaultYearOptions() {
    final now = DateTime.now();
    final start = now.month >= 8 ? now.year : now.year - 1;
    return <_YearOption>[
      _YearOption(
        id: '$start-${start + 1}',
        startYear: start,
      ),
    ];
  }

  CollectionReference<Map<String, dynamic>> _schoolCol(String path) {
    return _db.collection('schools').doc(widget.schoolId).collection(path);
  }

  Future<String> _resolveTeacherDocIdForWrite() async {
    final direct = widget.teacherDocId.trim();
    if (direct.isNotEmpty) return direct;
    final uid = _auth.currentUser?.uid?.trim() ?? '';
    if (uid.isEmpty) return '';

    final candidates = <DocumentReference<Map<String, dynamic>>>[
      _schoolCol('teachers_uid').doc(uid),
      _schoolCol('teachers_public').doc(uid),
      _db.collection('users').doc(uid),
      _db.collection('Users').doc(uid),
    ];

    for (final ref in candidates) {
      try {
        final snap = await ref.get();
        if (!snap.exists) continue;
        final data = snap.data() ?? const <String, dynamic>{};
        final id = (data['teacherDocId'] ?? data['teacherId'] ?? '').toString().trim();
        if (id.isNotEmpty) return id;
      } catch (_) {
        // Silently continue; the caller still gets a clean failure if nothing resolves.
      }
    }
    return '';
  }

  List<String> _buildTeacherTandas() {
    final out = <String>{'Todas'};
    for (final raw in widget.teacherTandas) {
      final normalized = _normalizeTanda(raw);
      if (normalized.isNotEmpty) out.add(normalized);
    }
    return out.toList();
  }

  String _normalizeTanda(String value) {
    final raw = value.trim().toLowerCase();
    if (raw.isEmpty) return '';
    if (raw == 'mañana' || raw == 'mañana') return 'Mañana';
    if (raw == 'tarde') return 'Tarde';
    if (raw == 'noche') return 'Noche';
    return value.trim();
  }

  bool _matchesSchoolYearValue(dynamic value, _YearOption year) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return false;
    final endYear = year.startYear + 1;
    return raw == year.id || raw == year.startYear.toString() || raw == endYear.toString();
  }

  int? _schoolYearStartFromRaw(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    final match = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(raw);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    final year = int.tryParse(raw);
    if (year == null) return null;
    if (year >= 2000 && year <= 2100) {
      return year >= 2050 ? year - 1 : year;
    }
    return null;
  }

  Future<void> _refreshVisibleYearsForGrade(String? gradeId) async {
    if (gradeId == null || gradeId.trim().isEmpty) {
      final defaults = _defaultYearOptions();
      if (!mounted) return;
      setState(() {
        _years = defaults;
        _selectedYear = defaults.first.id;
      });
      return;
    }

    final grade = _gradeById(gradeId);
    final studentsSnap = await _schoolCol('alumnos').get();
    int? latestStartYear;
    for (final d in studentsSnap.docs) {
      final data = d.data();
      if (!_studentMatchesGrade(data, grade, gradeId)) continue;
      final startYear = _schoolYearStartFromRaw(data['schoolYear'] ?? data['anioEscolar']);
      if (startYear == null) continue;
      if (latestStartYear == null || startYear > latestStartYear) {
        latestStartYear = startYear;
      }
    }

    final year = latestStartYear != null
        ? _YearOption(
            id: '$latestStartYear-${latestStartYear + 1}',
            startYear: latestStartYear,
          )
        : _defaultYearOptions().first;

    if (!mounted) return;
    setState(() {
      _years = <_YearOption>[year];
      _selectedYear = year.id;
    });
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final gradesSnap = await _schoolCol('grados').get();
      final gradeMap = <String, _GradeLite>{};

      for (final d in gradesSnap.docs) {
        final data = d.data();
        final id = (data['gradeId'] ?? d.id).toString().trim();
        final label = (data['name'] ?? data['grado'] ?? d.id).toString().trim();
        final nivel = (data['nivel'] ?? '').toString().trim();
        if (id.isEmpty || label.isEmpty) continue;
        if (widget.gradeIds.contains(id)) {
          gradeMap[id] = _GradeLite(id: id, label: label, nivel: nivel);
        }
      }

      if (gradeMap.isEmpty) {
        for (int i = 0; i < widget.gradeIds.length; i++) {
          final id = widget.gradeIds[i].trim();
          if (id.isEmpty) continue;
          final label = i < widget.gradeLabels.length ? widget.gradeLabels[i].trim() : id;
          gradeMap[id] = _GradeLite(id: id, label: label.isEmpty ? id : label, nivel: '');
        }
      }

      final grades = gradeMap.values.toList()
        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _grades = grades;
        _selectedGradeId = grades.any((g) => g.id == _selectedGradeId)
            ? _selectedGradeId
            : (grades.isNotEmpty ? grades.first.id : null);
      });

      await _refreshVisibleYearsForGrade(_selectedGradeId);
      await _loadRows();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  _GradeLite? _gradeById(String? id) {
    if (id == null) return null;
    for (final g in _grades) {
      if (g.id == id) return g;
    }
    return null;
  }

  bool _studentMatchesGrade(Map<String, dynamic> data, _GradeLite? grade, String gradeId) {
    final currentGradeId = (data['gradeId'] ?? data['gradoId'] ?? '').toString().trim();
    final gradeName = (data['grado'] ??
            data['gradeName'] ??
            data['gradeLabel'] ??
            data['gradoKey'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    return currentGradeId == gradeId ||
        (grade != null && gradeName == grade.label.toLowerCase());
  }

  bool _studentMatchesTanda(Map<String, dynamic> data) {
    if (_selectedTanda == 'Todas') return true;
    final tanda = _normalizeTanda(
      (data['tanda'] ?? data['tandaLower'] ?? '').toString(),
    );
    if (tanda.isEmpty) return true;
    return tanda == _selectedTanda;
  }

  bool _studentMatchesSelectedYear(Map<String, dynamic> data, _YearOption year) {
    final raw = data['schoolYear'] ?? data['anioEscolar'];
    if ((raw?.toString().trim() ?? '').isEmpty) return true;
    return _matchesSchoolYearValue(raw, year);
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[PROMOCION_DOCENTE] $message');
    }
  }

  Future<void> _loadRows() async {
    final year = _years.where((y) => y.id == _selectedYear).isEmpty
        ? null
        : _years.firstWhere((y) => y.id == _selectedYear);
    final gradeId = _selectedGradeId;
    final grade = _gradeById(gradeId);
    if (year == null || gradeId == null || gradeId.isEmpty) {
      if (mounted) {
        setState(() {
          _rows = [];
          _incompleteStudents = 0;
          _expectedSubjectCount = 0;
        });
      }
      return;
    }

    setState(() => _loading = true);
    try {
      final currentUid = _auth.currentUser?.uid?.trim() ?? '';
      _log(
        'loadRows year=${year.id} gradeId=$gradeId gradeLabel=${grade?.label} tanda=$_selectedTanda uid=$currentUid',
      );
      final studentsSnap = await _schoolCol('alumnos').get();
      final gradesV2Snap = await _schoolCol('calificaciones_v2').get();
      final proposalByStudent = <String, Map<String, dynamic>>{};
      try {
        final proposalsSnap = await _schoolCol('promocion_propuestas')
            .where('schoolYear', isEqualTo: _selectedYear)
            .where('gradeId', isEqualTo: gradeId)
            .get();
        for (final d in proposalsSnap.docs) {
          final data = d.data();
          final sid = (data['studentId'] ?? '').toString().trim();
          if (sid.isNotEmpty) proposalByStudent[sid] = data;
        }
      } catch (e) {
        _log('promocion_propuestas fallback por error: $e');
      }

      final gradesByStudent = <String, List<Map<String, dynamic>>>{};
      final teacherSubjectIdsForGrade = <String>{};
      for (final d in gradesV2Snap.docs) {
        final data = d.data();
        final sid = (data['studentId'] ?? '').toString().trim();
        final gid = (data['gradeId'] ?? '').toString().trim();
        if (sid.isEmpty || gid != gradeId || !_matchesSchoolYearValue(data['year'], year)) continue;
        final subjectId = (data['subjectId'] ?? '').toString().trim();
        final finalScore = ((data['computed'] as Map?)?['final']);
        final updatedByUid = (data['updatedByUid'] ?? '').toString().trim();
        final belongsToTeacher = currentUid.isNotEmpty && updatedByUid == currentUid;
        if (subjectId.isNotEmpty && finalScore is num && belongsToTeacher) {
          teacherSubjectIdsForGrade.add(subjectId);
        }
        gradesByStudent.putIfAbsent(sid, () => <Map<String, dynamic>>[]).add(data);
      }
      _log(
        'teacherSubjectIdsForGrade=${teacherSubjectIdsForGrade.toList()} currentStudentsRaw=${studentsSnap.docs.length}',
      );

      final studentIdsWithGrades = gradesByStudent.keys.toSet();
      final currentStudents = studentsSnap.docs.where((d) {
        final data = d.data();
        final matchedByStudentDoc = _studentMatchesGrade(data, grade, gradeId);
        final matchedByGrades = studentIdsWithGrades.contains(d.id);
        return (matchedByStudentDoc || matchedByGrades)
            && _studentMatchesTanda(data)
            && _studentMatchesSelectedYear(data, year);
      }).toList();
      _log('currentStudentsFiltered=${currentStudents.length}');

      int incompleteStudents = 0;
      final rows = currentStudents.map((d) {
        final data = d.data();
        final sid = d.id;
        final studentGrades = gradesByStudent[sid] ?? const <Map<String, dynamic>>[];
        final finals = studentGrades
            .map((m) => ((m['computed'] as Map?)?['final']))
            .map((v) => v is num ? v.toDouble() : null)
            .whereType<double>()
            .toList();
        final finalizedSubjectIds = studentGrades
            .where((m) {
              final finalOk = ((m['computed'] as Map?)?['final']) is num;
              final updatedByUid = (m['updatedByUid'] ?? '').toString().trim();
              final belongsToTeacher = currentUid.isEmpty || updatedByUid == currentUid;
              return finalOk && belongsToTeacher;
            })
            .map((m) => (m['subjectId'] ?? '').toString().trim())
            .where((id) => id.isNotEmpty)
            .toSet();
        final average = finals.isEmpty ? null : finals.reduce((a, b) => a + b) / finals.length;
        final hasAnySubjectBelowThreshold =
            finals.any((value) => value < _approvalThreshold);
        final isComplete = average != null &&
            (teacherSubjectIdsForGrade.isEmpty ||
                finalizedSubjectIds.length >= teacherSubjectIdsForGrade.length);
        _log(
          'student=$sid name=${_studentName(data, sid)} tanda=${_normalizeTanda((data['tanda'] ?? data['tandaLower'] ?? '').toString())} finals=${finals.length} finalizedSubjects=${finalizedSubjectIds.toList()} average=$average hasAnyBelow=$hasAnySubjectBelowThreshold complete=$isComplete',
        );
        if (!isComplete) {
          incompleteStudents++;
          return null;
        }
        final suggested = average == null
            ? _ProposalStatus.pendiente
            : !hasAnySubjectBelowThreshold
                ? _ProposalStatus.aprobado
                : _ProposalStatus.reprobado;
        final existing = proposalByStudent[sid];
        final proposed = _ProposalStatusX.fromValue(
          (existing?['proposedStatus'] ?? '').toString(),
        );
        return _TeacherProposalRow(
          studentId: sid,
          studentName: _studentName(data, sid),
          matricula: (data['matricula'] ?? data['codigo'] ?? '').toString().trim(),
          average: average,
          subjectCount: finalizedSubjectIds.isEmpty ? finals.length : finalizedSubjectIds.length,
          suggestedStatus: suggested,
          proposedStatus: proposed ?? suggested,
          hasOverride: proposed != null && proposed != suggested,
          teacherComment: (existing?['teacherComment'] ?? '').toString(),
        );
      }).whereType<_TeacherProposalRow>().toList()
        ..sort((a, b) => a.studentName.toLowerCase().compareTo(b.studentName.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _incompleteStudents = incompleteStudents;
        _expectedSubjectCount = teacherSubjectIdsForGrade.length;
      });
      _log(
        'rowsVisible=${rows.length} incompleteStudents=$incompleteStudents expectedSubjectCount=$_expectedSubjectCount',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _studentName(Map<String, dynamic> data, String id) {
    final nombre = (data['nombre'] ?? data['nombres'] ?? '').toString().trim();
    final apellido = (data['apellido'] ?? data['apellidos'] ?? '').toString().trim();
    final full = '$nombre $apellido'.trim();
    return full.isEmpty ? 'Alumno $id' : full;
  }

  void _setProposal(String studentId, _ProposalStatus value) {
    setState(() {
      _rows = _rows.map((row) {
        if (row.studentId != studentId) return row;
        return row.copyWith(
          proposedStatus: value,
          hasOverride: value != row.suggestedStatus,
        );
      }).toList();
    });
  }

  void _setComment(String studentId, String value) {
    setState(() {
      _rows = _rows.map((row) {
        if (row.studentId != studentId) return row;
        return row.copyWith(teacherComment: value);
      }).toList();
    });
  }

  Future<void> _saveProposals() async {
    final gradeId = _selectedGradeId;
    final yearId = _selectedYear;
    final year = _years.where((y) => y.id == yearId).isEmpty
        ? null
        : _years.firstWhere((y) => y.id == yearId);
    final grade = _gradeById(gradeId);
    if (gradeId == null || yearId == null || year == null || grade == null) return;

    setState(() => _saving = true);
    try {
      final authUser = _auth.currentUser;
      final resolvedTeacherDocId = await _resolveTeacherDocIdForWrite();
      _log(
        'saveProposals teacherDocId(widget)=${widget.teacherDocId} teacherDocId(resolved)=$resolvedTeacherDocId uid=${authUser?.uid}',
      );
      final batch = _db.batch();
      for (final row in _rows) {
        final ref = _schoolCol('promocion_propuestas')
            .doc('${yearId}_${gradeId}_${row.studentId}');
        batch.set(ref, {
          'schoolYear': yearId,
          'year': year.startYear,
          'schoolId': widget.schoolId,
          'gradeId': gradeId,
          'gradeName': grade.label,
          'studentId': row.studentId,
          'studentName': row.studentName,
          'teacherDocId': resolvedTeacherDocId,
          'teacherUid': authUser?.uid,
          'teacherEmail': authUser?.email?.trim(),
          'teacherName': widget.teacherName,
          'finalAverage': row.average,
          'subjectCount': row.subjectCount,
          'suggestedStatus': row.suggestedStatus.value,
          'proposedStatus': row.proposedStatus.value,
          'hasOverride': row.proposedStatus != row.suggestedStatus,
          'teacherComment': row.teacherComment.trim(),
          'readyForAdmin': row.average != null,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Propuestas enviadas a administraciÃ³n.')),
      );
      await _loadRows();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron guardar las propuestas: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: const Text(''),
      ),
      body: _loading && _grades.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<String>(
                          value: _selectedYear,
                          items: _years
                              .map((y) => DropdownMenuItem(value: y.id, child: Text(y.id)))
                              .toList(),
                          onChanged: (value) async {
                            setState(() => _selectedYear = value);
                            await _loadRows();
                          },
                          decoration: const InputDecoration(
                            labelText: 'Año escolar',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 300,
                        child: DropdownButtonFormField<String>(
                          value: _selectedGradeId,
                           items: _grades
                               .map((g) => DropdownMenuItem(value: g.id, child: Text(g.label)))
                               .toList(),
                           onChanged: (value) async {
                             setState(() => _selectedGradeId = value);
                             await _refreshVisibleYearsForGrade(value);
                             await _loadRows();
                           },
                          decoration: const InputDecoration(
                            labelText: 'Grado',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          value: _selectedTanda,
                          items: _tandas
                              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                              .toList(),
                          onChanged: (value) async {
                            if (value == null) return;
                            setState(() => _selectedTanda = value);
                            await _loadRows();
                          },
                          decoration: const InputDecoration(
                            labelText: 'Tanda',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_incompleteStudents > 0)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text(
                      _expectedSubjectCount > 0
                          ? 'Hay $_incompleteStudents alumno(s) que aun no tienen nota final en todas sus asignaturas. No apareceran aqui hasta completar las $_expectedSubjectCount asignaturas del grado.'
                          : 'Hay $_incompleteStudents alumno(s) con calificaciones finales incompletas. No apareceran aqui hasta completar sus notas.',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                ..._rows.map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildStudentCard(row),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    ),
                    onPressed: _saving ? null : _saveProposals,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded),
                    label: const Text('Enviar a administración'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStudentCard(_TeacherProposalRow row) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: row.hasOverride ? Colors.deepPurple.shade200 : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.studentName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    if (row.matricula.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Matricula ${row.matricula}',
                        style: TextStyle(color: Colors.grey.shade800),
                      ),
                    ],
                  ],
                ),
              ),
              Chip(
                label: Text('Sistema: ${row.suggestedStatus.label}'),
                backgroundColor: row.suggestedStatus.color.withOpacity(0.12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<_ProposalStatus>(
                  value: row.proposedStatus,
                  items: _ProposalStatus.values
                      .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                      .toList(),
                  onChanged: row.average == null
                      ? null
                      : (value) {
                          if (value != null) _setProposal(row.studentId, value);
                        },
                  decoration: const InputDecoration(
                    labelText: 'Propuesta del docente',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: 420,
                child: TextFormField(
                  initialValue: row.teacherComment,
                  onChanged: (value) => _setComment(row.studentId, value),
                  decoration: const InputDecoration(
                    labelText: 'Comentario para administraciÃ³n',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          if (row.hasOverride) ...[
            const SizedBox(height: 10),
            Chip(
              label: const Text('El docente cambiÃ³ la sugerencia automÃ¡tica'),
              backgroundColor: Colors.deepPurple.shade50,
            ),
          ],
        ],
      ),
    );
  }
}

class _YearOption {
  final String id;
  final int startYear;

  const _YearOption({
    required this.id,
    required this.startYear,
  });
}

class _GradeLite {
  final String id;
  final String label;
  final String nivel;

  const _GradeLite({
    required this.id,
    required this.label,
    required this.nivel,
  });
}

class _TeacherProposalRow {
  final String studentId;
  final String studentName;
  final String matricula;
  final double? average;
  final int subjectCount;
  final _ProposalStatus suggestedStatus;
  final _ProposalStatus proposedStatus;
  final bool hasOverride;
  final String teacherComment;

  const _TeacherProposalRow({
    required this.studentId,
    required this.studentName,
    required this.matricula,
    required this.average,
    required this.subjectCount,
    required this.suggestedStatus,
    required this.proposedStatus,
    required this.hasOverride,
    required this.teacherComment,
  });

  _TeacherProposalRow copyWith({
    _ProposalStatus? proposedStatus,
    bool? hasOverride,
    String? teacherComment,
  }) {
    return _TeacherProposalRow(
      studentId: studentId,
      studentName: studentName,
      matricula: matricula,
      average: average,
      subjectCount: subjectCount,
      suggestedStatus: suggestedStatus,
      proposedStatus: proposedStatus ?? this.proposedStatus,
      hasOverride: hasOverride ?? this.hasOverride,
      teacherComment: teacherComment ?? this.teacherComment,
    );
  }
}

enum _ProposalStatus {
  aprobado('Aprobado', Colors.green),
  reprobado('Reprobado', Colors.deepOrange),
  pendiente('Pendiente', Colors.orange);

  const _ProposalStatus(this.label, this.color);
  final String label;
  final Color color;

  String get value {
    switch (this) {
      case _ProposalStatus.aprobado:
        return 'aprobado';
      case _ProposalStatus.reprobado:
        return 'reprobado';
      case _ProposalStatus.pendiente:
        return 'pendiente';
    }
  }
}

extension _ProposalStatusX on _ProposalStatus {
  static _ProposalStatus? fromValue(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'aprobado':
        return _ProposalStatus.aprobado;
      case 'reprobado':
        return _ProposalStatus.reprobado;
      case 'pendiente':
        return _ProposalStatus.pendiente;
      default:
        return null;
    }
  }
}
