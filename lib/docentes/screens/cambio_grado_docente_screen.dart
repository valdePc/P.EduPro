import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';

class CambioGradoDocenteScreen extends StatefulWidget {
  final Escuela escuela;
  final String schoolId;
  final String teacherDocId;
  final String teacherName;
  final List<String> gradeIds;
  final List<String> gradeLabels;
  final List<String> teacherTandas;
  final String? initialGradeId;
  final String? initialTanda;

  const CambioGradoDocenteScreen({
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
  State<CambioGradoDocenteScreen> createState() => _CambioGradoDocenteScreenState();
}

class _CambioGradoDocenteScreenState extends State<CambioGradoDocenteScreen> {
  static const Color _blue = Color(0xFF0D47A1);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<_GradeLite> _grades = const [];
  List<String> _tandas = const ['Todas'];
  List<String> _availableSchoolYears = const [];
  String? _selectedGradeId;
  String _selectedTanda = 'Todas';
  String _activeSchoolYear = '';
  bool _loading = true;
  bool _submitting = false;
  List<_StudentMoveDraft> _rows = const [];

  @override
  void initState() {
    super.initState();
    _selectedGradeId = widget.initialGradeId?.trim().isNotEmpty == true
        ? widget.initialGradeId!.trim()
        : (widget.gradeIds.isNotEmpty ? widget.gradeIds.first.trim() : null);
    _tandas = _buildTeacherTandas();
    final desiredTanda = _normalizeTanda(widget.initialTanda ?? '');
    _selectedTanda = _tandas.contains(desiredTanda) ? desiredTanda : _tandas.first;
    _bootstrap();
  }

  CollectionReference<Map<String, dynamic>> _schoolCol(String path) {
    return _db.collection('schools').doc(widget.schoolId).collection(path);
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[CAMBIO_GRADO_DOCENTE] $message');
    }
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
    if (
        raw == 'mañana' ||
        raw == 'maÃ±ana' ||
        raw == 'maã±ana' ||
        raw == 'maÃ£Â±ana' ||
        raw == 'maã£â±ana' ||
        raw == 'manana') {
      return 'Manana';
    }
    if (raw == 'tarde') return 'Tarde';
    if (raw == 'noche') return 'Noche';
    return value.trim();
  }

  int? _schoolYearStartFromRaw(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    final match = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(raw);
    if (match != null) return int.tryParse(match.group(1)!);
    final year = int.tryParse(raw);
    if (year == null) return null;
    if (year >= 2000 && year <= 2100) {
      return year >= 2050 ? year - 1 : year;
    }
    return null;
  }

  List<String> _schoolYearsFromStudents(
    List<_StudentDocLite> studentDocs,
    _GradeLite? grade,
    String? gradeId,
  ) {
    final startYears = <int>{};
    for (final doc in studentDocs) {
      final data = doc.data;
      if (!_studentMatchesGrade(data, grade, gradeId ?? '')) continue;
      if (!_studentMatchesTanda(data)) continue;
      final start = _schoolYearStartFromRaw(data['schoolYear'] ?? data['anioEscolar']);
      if (start == null) continue;
      startYears.add(start);
    }
    if (startYears.isEmpty) {
      final now = DateTime.now();
      final currentStart = now.month >= 8 ? now.year : now.year - 1;
      return <String>['$currentStart-${currentStart + 1}'];
    }
    final sorted = startYears.toList()..sort((a, b) => b.compareTo(a));
    return sorted.map((start) => '$start-${start + 1}').toList();
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
        gradeMap[id] = _GradeLite(id: id, label: label, nivel: nivel);
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
    final tanda = _normalizeTanda((data['tanda'] ?? data['tandaLower'] ?? '').toString());
    if (tanda.isEmpty) return true;
    return tanda == _selectedTanda;
  }

  String _studentDisplayName(Map<String, dynamic> data) {
    final nombres = (data['nombres'] ?? '').toString().trim();
    final apellidos = (data['apellidos'] ?? '').toString().trim();
    final fullFromParts = ('$apellidos, $nombres').trim().replaceAll(RegExp(r'^,\s*'), '');
    final fallback = (data['nombre'] ??
            data['name'] ??
            data['displayName'] ??
            data['fullName'] ??
            '')
        .toString()
        .trim();
    return fullFromParts.isNotEmpty ? fullFromParts : fallback;
  }

  Future<void> _loadRows() async {
    final gradeId = _selectedGradeId?.trim() ?? '';
    final grade = _gradeById(gradeId);
    if (gradeId.isEmpty || grade == null) {
      if (!mounted) return;
      setState(() {
        _activeSchoolYear = '';
        _rows = const [];
      });
      return;
    }

    setState(() => _loading = true);
    try {
      final studentDataById = <String, Map<String, dynamic>>{};

      Future<void> loadStudentsByField(String field) async {
        final snap = await _schoolCol('alumnos').where(field, isEqualTo: gradeId).get();
        for (final doc in snap.docs) {
          studentDataById[doc.id] = doc.data();
        }
      }

      await loadStudentsByField('gradeId');
      if (studentDataById.isEmpty) {
        await loadStudentsByField('gradoId');
      }

      final calificacionesSnap = await _schoolCol('calificaciones_v2').get();
      final availableYears = _schoolYearsFromStudents(
        studentDataById.entries
            .map((e) => _StudentDocLite(id: e.key, data: e.value))
            .toList(),
        grade,
        gradeId,
      );
      final selectedYear = availableYears.contains(_activeSchoolYear)
          ? _activeSchoolYear
          : availableYears.first;
      final gradeStudentIdsFromCalificaciones = <String>{};
      for (final doc in calificacionesSnap.docs) {
        final data = doc.data();
        final calGradeId = (data['gradeId'] ?? data['gradoId'] ?? '').toString().trim();
        final calStudentId = (data['studentId'] ?? data['alumnoId'] ?? '').toString().trim();
        final yearRaw = (data['year'] ?? data['schoolYear'] ?? data['anioEscolar'] ?? '').toString().trim();
        if (calStudentId.isEmpty || calGradeId.isEmpty || yearRaw.isEmpty) continue;
        if (calGradeId != gradeId) continue;
        final calStartYear = _schoolYearStartFromRaw(yearRaw);
        final selectedStartYear = _schoolYearStartFromRaw(selectedYear);
        if (calStartYear == null || selectedStartYear == null || calStartYear != selectedStartYear) {
          continue;
        }
        gradeStudentIdsFromCalificaciones.add(calStudentId);
      }
      for (final studentId in gradeStudentIdsFromCalificaciones) {
        if (studentDataById.containsKey(studentId)) continue;
        final studentSnap = await _schoolCol('alumnos').doc(studentId).get();
        final data = studentSnap.data();
        if (studentSnap.exists && data != null) {
          studentDataById[studentId] = data;
        }
      }
      final rows = <_StudentMoveDraft>[];

      for (final entry in studentDataById.entries) {
        final studentId = entry.key;
        final data = entry.value;
        final matchedByCalificaciones = gradeStudentIdsFromCalificaciones.contains(studentId);
        final matchesGrade = _studentMatchesGrade(data, grade, gradeId) || matchedByCalificaciones;
        if (!matchesGrade) {
          _log(
            'skip student=$studentId reason=gradeMismatch '
            'gradeId=${data['gradeId'] ?? data['gradoId']} grade=${data['grado'] ?? data['gradeName']}',
          );
          continue;
        }
        if (!_studentMatchesTanda(data) && !matchedByCalificaciones) {
          _log(
            'skip student=$studentId reason=tandaMismatch tanda=${data['tanda'] ?? data['tandaLower']} selected=$_selectedTanda',
          );
          continue;
        }

        final schoolYear = (data['schoolYear'] ?? data['anioEscolar'] ?? '').toString().trim();
        if (schoolYear.isNotEmpty && schoolYear != selectedYear && !matchedByCalificaciones) {
          _log(
            'skip student=$studentId reason=schoolYearMismatch schoolYear=$schoolYear selected=$selectedYear',
          );
          continue;
        }

        final name = _studentDisplayName(data);
        if (name.isEmpty) continue;

        rows.add(
          _StudentMoveDraft(
            studentId: studentId,
            studentName: name,
            matricula: (data['matricula'] ?? data['numero'] ?? '').toString().trim(),
            currentGradeId: gradeId,
            currentGradeName: grade.label,
            currentTanda: _normalizeTanda((data['tanda'] ?? '').toString()),
            schoolYear: selectedYear,
            currentTargetGradeId: null,
            currentTargetTanda: _selectedTanda == 'Todas'
                ? _normalizeTanda((data['tanda'] ?? '').toString())
                : _selectedTanda,
            requestType: 'reubicacion',
            reason: '',
            pendingLabel: '',
          ),
        );
      }

      rows.sort((a, b) => a.studentName.toLowerCase().compareTo(b.studentName.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _availableSchoolYears = availableYears;
        _activeSchoolYear = selectedYear;
        _rows = rows;
      });
      _log(
        'loadRows schoolYear=$selectedYear gradeId=$gradeId gradeLabel=${grade.label} tanda=$_selectedTanda '
        'availableYears=${availableYears.join("|")} calStudentIds=${gradeStudentIdsFromCalificaciones.join("|")} rows=${rows.length}',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _updateRow(
    int index, {
    String? targetGradeId,
    String? targetTanda,
    String? requestType,
    String? reason,
  }) {
    final next = [..._rows];
    final row = next[index];
    next[index] = row.copyWith(
      currentTargetGradeId: targetGradeId ?? row.currentTargetGradeId,
      currentTargetTanda: targetTanda ?? row.currentTargetTanda,
      requestType: requestType ?? row.requestType,
      reason: reason ?? row.reason,
    );
    setState(() => _rows = next);
  }

  Future<void> _submitRow(int index) async {
    final row = _rows[index];
    final targetGradeId = row.currentTargetGradeId?.trim() ?? '';
    final targetGrade = _gradeById(targetGradeId);
    final targetTanda = row.currentTargetTanda.trim();
    final reason = row.reason.trim();
    final uid = _auth.currentUser?.uid.trim() ?? '';

    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Necesitas sesiÃ³n activa para enviar la solicitud.')),
      );
      return;
    }
    if (targetGradeId.isEmpty || targetGrade == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona el grado destino.')),
      );
      return;
    }
    if (reason.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Describe el motivo del cambio con un poco mÃ¡s de detalle.')),
      );
      return;
    }
    if (targetTanda.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona la tanda destino.')),
      );
      return;
    }

    final normalizedCurrentTanda = _normalizeTanda(row.currentTanda);
    final normalizedTargetTanda = _normalizeTanda(targetTanda);
    if (targetGradeId == row.currentGradeId &&
        normalizedCurrentTanda == normalizedTargetTanda) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El destino debe ser distinto al grado o tanda actual.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final pendingSnap =
          await _schoolCol('solicitudes_cambio_grado').where('studentId', isEqualTo: row.studentId).get();
      final hasPending = pendingSnap.docs.any((d) {
        final data = d.data();
        return (data['status'] ?? '').toString().trim().toLowerCase() == 'pending' &&
            (data['schoolYear'] ?? '').toString().trim() == row.schoolYear;
      });
      if (hasPending) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ese alumno ya tiene una solicitud pendiente en este periodo.')),
        );
        return;
      }

      final ref = _schoolCol('solicitudes_cambio_grado').doc();
      final now = FieldValue.serverTimestamp();
      await ref.set({
        'schoolId': widget.schoolId,
        'schoolYear': row.schoolYear,
        'studentId': row.studentId,
        'studentName': row.studentName,
        'matricula': row.matricula,
        'fromGradeId': row.currentGradeId,
        'fromGradeName': row.currentGradeName,
        'fromTanda': row.currentTanda,
        'toGradeId': targetGradeId,
        'toGradeName': targetGrade.label,
        'toTanda': targetTanda,
        'requestType': row.requestType,
        'reason': reason,
        'teacherUid': uid,
        'teacherDocId': widget.teacherDocId,
        'teacherName': widget.teacherName.trim().isNotEmpty ? widget.teacherName.trim() : 'Docente',
        'status': 'pending',
        'createdAt': now,
        'updatedAt': now,
      });

      if (!mounted) return;
      final next = [..._rows];
      next[index] = row.copyWith(
        pendingLabel: 'Pendiente de administraciÃ³n',
        currentTargetGradeId: targetGradeId,
      );
      setState(() => _rows = next);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Solicitud enviada para ${row.studentName}.')),
      );
    } catch (e) {
      _log('submit error studentId=${row.studentId} value=$e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar la solicitud: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _activeSchoolYear.isEmpty ? null : _activeSchoolYear,
                  decoration: const InputDecoration(labelText: 'Periodo escolar'),
                  items: _availableSchoolYears
                      .map((year) => DropdownMenuItem<String>(value: year, child: Text(year)))
                      .toList(),
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => _activeSchoolYear = value);
                    await _loadRows();
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedGradeId,
                  decoration: const InputDecoration(labelText: 'Grado'),
                  isExpanded: true,
                  items: _grades
                      .where((grade) => widget.gradeIds.contains(grade.id))
                      .map((grade) => DropdownMenuItem<String>(
                            value: grade.id,
                            child: Text(grade.label, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => _selectedGradeId = value);
                    await _loadRows();
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedTanda,
                  decoration: const InputDecoration(labelText: 'Tanda'),
                  items: _tandas
                      .map((t) => DropdownMenuItem<String>(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => _selectedTanda = value);
                    await _loadRows();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Text(
              'El cambio se solicita dentro del periodo activo. AdministraciÃ³n revisa y decide si lo ejecuta.',
              style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowCard(int index, _StudentMoveDraft row) {
    final selectedGradeValue = row.currentTargetGradeId != null &&
            _grades.any((g) => g.id == row.currentTargetGradeId)
        ? row.currentTargetGradeId
        : null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.studentName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (row.matricula.isNotEmpty) 'Matricula ${row.matricula}',
                        '${row.currentGradeName} Â· ${row.currentTanda.isEmpty ? 'Sin tanda' : row.currentTanda}',
                      ].join(' Â· '),
                      style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              if (row.pendingLabel.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Text(
                    row.pendingLabel,
                    style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: selectedGradeValue,
                  decoration: const InputDecoration(labelText: 'Grado destino'),
                  isExpanded: true,
                  items: _grades
                      .where((g) => g.id != row.currentGradeId)
                      .map((grade) => DropdownMenuItem<String>(
                            value: grade.id,
                            child: Text(grade.label, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: row.pendingLabel.isNotEmpty
                      ? null
                      : (value) => _updateRow(index, targetGradeId: value),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: row.currentTargetTanda.isEmpty ? null : row.currentTargetTanda,
                  decoration: const InputDecoration(labelText: 'Tanda destino'),
                  items: _tandas
                      .where((t) => t != 'Todas')
                      .map((t) => DropdownMenuItem<String>(value: t, child: Text(t)))
                      .toList(),
                  onChanged: row.pendingLabel.isNotEmpty
                      ? null
                      : (value) => _updateRow(index, targetTanda: value),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: row.requestType,
                  decoration: const InputDecoration(labelText: 'Tipo de cambio'),
                  items: const [
                    DropdownMenuItem(value: 'reubicacion', child: Text('Reubicacion')),
                    DropdownMenuItem(value: 'promocion_anticipada', child: Text('Promocion anticipada')),
                    DropdownMenuItem(value: 'descenso_grado', child: Text('Descenso de grado')),
                    DropdownMenuItem(value: 'cambio_administrativo', child: Text('Cambio administrativo')),
                  ],
                  onChanged: row.pendingLabel.isNotEmpty
                      ? null
                      : (value) => _updateRow(index, requestType: value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextFormField(
            initialValue: row.reason,
            enabled: row.pendingLabel.isEmpty,
            minLines: 2,
            maxLines: 4,
            onChanged: (value) => _updateRow(index, reason: value),
            decoration: const InputDecoration(
              labelText: 'Motivo pedagÃ³gico o administrativo',
              hintText: 'Explica por quÃ© propones mover al alumno y desde cuÃ¡ndo deberÃ­a aplicarse.',
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: (_submitting || row.pendingLabel.isNotEmpty) ? null : () => _submitRow(index),
              icon: const Icon(Icons.send_outlined),
              label: const Text('Enviar solicitud'),
              style: FilledButton.styleFrom(backgroundColor: _blue),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: const Color(0xFFF6FAFC),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      _buildFilters(),
                      const SizedBox(height: 18),
                      Expanded(
                        child: _rows.isEmpty
                            ? Center(
                                child: Text(
                                  'No hay alumnos disponibles para solicitar cambio en este grado.',
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _rows.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 14),
                                itemBuilder: (context, index) => _buildRowCard(index, _rows[index]),
                              ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
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

class _StudentDocLite {
  final String id;
  final Map<String, dynamic> data;

  const _StudentDocLite({
    required this.id,
    required this.data,
  });
}

class _StudentMoveDraft {
  final String studentId;
  final String studentName;
  final String matricula;
  final String currentGradeId;
  final String currentGradeName;
  final String currentTanda;
  final String schoolYear;
  final String? currentTargetGradeId;
  final String currentTargetTanda;
  final String requestType;
  final String reason;
  final String pendingLabel;

  const _StudentMoveDraft({
    required this.studentId,
    required this.studentName,
    required this.matricula,
    required this.currentGradeId,
    required this.currentGradeName,
    required this.currentTanda,
    required this.schoolYear,
    required this.currentTargetGradeId,
    required this.currentTargetTanda,
    required this.requestType,
    required this.reason,
    required this.pendingLabel,
  });

  _StudentMoveDraft copyWith({
    String? currentTargetGradeId,
    String? currentTargetTanda,
    String? requestType,
    String? reason,
    String? pendingLabel,
  }) {
    return _StudentMoveDraft(
      studentId: studentId,
      studentName: studentName,
      matricula: matricula,
      currentGradeId: currentGradeId,
      currentGradeName: currentGradeName,
      currentTanda: currentTanda,
      schoolYear: schoolYear,
      currentTargetGradeId: currentTargetGradeId ?? this.currentTargetGradeId,
      currentTargetTanda: currentTargetTanda ?? this.currentTargetTanda,
      requestType: requestType ?? this.requestType,
      reason: reason ?? this.reason,
      pendingLabel: pendingLabel ?? this.pendingLabel,
    );
  }
}
