import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:edupro/docentes/widgets/docente_app_bar.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class AsistenciaScreen extends StatefulWidget {
  static const String routeName = '/asistencia';

  /// Si abres con MaterialPageRoute, puedes pasarla aquí.
  /// Si abres con pushNamed, llegará por arguments.
  final Escuela? escuela;

  const AsistenciaScreen({super.key, this.escuela});

  @override
  State<AsistenciaScreen> createState() => _AsistenciaScreenState();
}

class _AsistenciaScreenState extends State<AsistenciaScreen> {
  // Colores (mantengo tu estilo típico)
  static const Color primaryColor = Color.fromARGB(255, 255, 193, 7); // naranja
  static const Color secondaryColor = Color.fromARGB(255, 21, 101, 192); // azul

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Multi-tenant root (si tu proyecto a veces usa 'escuelas')
  String _rootCol = 'schools';

  Escuela? _escuela;
  String _schoolId = '';

  bool _loading = true;
  String? _error;

  // Mes visible dentro del ciclo escolar actual
  late int _month;
  late int _schoolYearStart;
  late int _year;

  // Catálogos
  List<String> _grades = [];
  List<String> _subjects = [];

  // Selección
  String? _selectedGrade;
  String? _selectedSubject;

  // Días laborables del mes (L-V)
  List<DateTime> _workDays = [];

  // Alumnos
  List<_StudentRow> _students = [];

  // Marcas por alumno y por día: studentId -> (dateKey -> 'P'/'A'/'E')
  final Map<String, Map<String, String>> _marks = {};
  final Map<String, Map<String, String>> _excuseReasons = {};

  // Mapping label -> docId del grado (para grados/{gradeId}/alumnos)
  final Map<String, String> _gradeLabelToId = {};

  // Constantes
  static const String markP = 'P';
  static const String markA = 'A';
  static const String markE = 'E';

  bool _showExcuses = false;
  bool _allowPastAttendanceEdit = false;
  DateTime? _pastAttendanceEditUntil;

  // UI sizing
  static const double _dayColWidth = 22;
  static const double _dayColHeight = 22;
  static const double _totalColWidth = 42;
  static const double _pctColWidth = 60;
  static const double _firstColWidthBase = 250;

  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = now.month;
    _schoolYearStart = _resolveSchoolYearStart(now);
    _year = _calendarYearForMonth(_month);
    _escuela = widget.escuela;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // recibir arguments si vino por pushNamed
    final args = ModalRoute.of(context)?.settings.arguments;
    if (_escuela == null && args is Escuela) {
      _escuela = args;
    }

    if (_bootstrapped) return;

    final e = _escuela;
    if (e == null) {
      setState(() {
        _loading = false;
        _error = 'No recibí la escuela (arguments).';
      });
      return;
    }

    // Normaliza + asegúrate de no tener "/" en docId
    final raw = normalizeSchoolIdFromEscuela(e).toString().trim();
    _schoolId = raw.replaceAll('/', '_');

    _bootstrapped = true;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'No hay sesión activa.';
      });
      return;
    }

    try {
      _workDays = _buildWorkDays(_year, _month);

      // 1) Restricciones del docente (si existen)
      final teacherConstraints = await _loadTeacherConstraints(user);

      // 2) Catálogos
      await Future.wait(<Future<void>>[
        _loadCatalogGrades(),
        _loadCatalogSubjects(),
      ]);

      // Priorizar asignaciones del docente si vienen
      if (teacherConstraints.grades.isNotEmpty) _grades = teacherConstraints.grades;
      if (teacherConstraints.subjects.isNotEmpty) _subjects = teacherConstraints.subjects;
      _allowPastAttendanceEdit = teacherConstraints.allowPastAttendanceEdit;
      _pastAttendanceEditUntil = teacherConstraints.pastAttendanceEditUntil;

      // Defaults
      _selectedGrade ??= _grades.isNotEmpty ? _grades.first : null;
      _selectedSubject ??= _subjects.isNotEmpty ? _subjects.first : null;

      await _reloadSheet();

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Error inicializando asistencia: $e';
      });
    }
  }

  // ============================================================
  // Helpers fecha/mes y IDs
  // ============================================================
  List<DateTime> _buildWorkDays(int year, int month) {
    final first = DateTime(year, month, 1);
    final nextMonth = DateTime(year, month + 1, 1);
    final days = <DateTime>[];

    for (DateTime d = first; d.isBefore(nextMonth); d = d.add(const Duration(days: 1))) {
      final wd = d.weekday; // 1=Lun ... 7=Dom
      if (wd >= DateTime.monday && wd <= DateTime.friday) {
        days.add(DateTime(d.year, d.month, d.day));
      }
    }
    return days;
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  int _resolveSchoolYearStart(DateTime date) {
    return date.month >= 8 ? date.year : date.year - 1;
  }

  int _calendarYearForMonth(int month) {
    return month >= 8 ? _schoolYearStart : _schoolYearStart + 1;
  }

  String _schoolYearLabel() => '$_schoolYearStart-${_schoolYearStart + 1}';

  String _dateKey(DateTime d) => '${d.year}${_two(d.month)}${_two(d.day)}'; // yyyyMMdd
  String _monthKey() => '${_year}${_two(_month)}'; // yyyyMM

  String _sanitize(String v) {
    final s = v.trim().toLowerCase();
    return s.replaceAll(RegExp(r'[^a-z0-9_-]+'), '_');
  }

  String _sheetDocId() {
    final g = _sanitize(_selectedGrade ?? 'grado');
    final s = _sanitize(_selectedSubject ?? 'asignatura');
    return '${_monthKey()}__${g}__${s}';
  }

  int _presentCountForStudent(String studentId) {
    final m = _marks[studentId];
    if (m == null) return 0;
    int c = 0;
    for (final d in _workDays) {
      final k = _dateKey(d);
      if (m[k] == markP) c++;
    }
    return c;
  }

  String _pctForStudent(String studentId) {
    final totalDays = _workDays.length;
    if (totalDays <= 0) return '0%';
    final p = _presentCountForStudent(studentId);
    final pct = (p / totalDays) * 100.0;
    return '${pct.toStringAsFixed(0)}%';
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  DateTime? _parseDateTimeValue(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) {
      final parsed = value.toDate();
      return parsed.hour == 0 &&
              parsed.minute == 0 &&
              parsed.second == 0 &&
              parsed.millisecond == 0 &&
              parsed.microsecond == 0
          ? _endOfDay(parsed)
          : parsed;
    }
    if (value is DateTime) {
      return value.hour == 0 &&
              value.minute == 0 &&
              value.second == 0 &&
              value.millisecond == 0 &&
              value.microsecond == 0
          ? _endOfDay(value)
          : value;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return parsed.hour == 0 &&
            parsed.minute == 0 &&
            parsed.second == 0 &&
            parsed.millisecond == 0 &&
            parsed.microsecond == 0
        ? _endOfDay(parsed)
        : parsed;
  }

  bool _readBoolish(dynamic value) {
    if (value is bool) return value;
    final raw = (value ?? '').toString().trim().toLowerCase();
    return raw == 'true' || raw == '1' || raw == 'si' || raw == 'sí';
  }

  bool get _hasPastAttendanceOverride {
    if (_allowPastAttendanceEdit) return true;
    final until = _pastAttendanceEditUntil;
    if (until == null) return false;
    return !DateTime.now().isAfter(until);
  }

  bool _isFutureDay(DateTime d) {
    final today = _dateOnly(DateTime.now());
    return _dateOnly(d).isAfter(today);
  }

  bool _isWithinDefaultAttendanceWindow(DateTime d) {
    final today = _dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final day = _dateOnly(d);
    return !day.isBefore(yesterday) && !day.isAfter(today);
  }

  String? _dayEditBlockedReason(DateTime d) {
    if (_isFutureDay(d)) {
      return 'No puedes registrar asistencia en fechas futuras.';
    }
    if (_isWithinDefaultAttendanceWindow(d) || _hasPastAttendanceOverride) {
      return null;
    }
    return 'Solo puedes registrar asistencia de hoy y ayer. Para fechas anteriores necesitas autorización de administración.';
  }

  bool _canEditDay(DateTime d) {
    return _dayEditBlockedReason(d) == null;
  }

  String _attendanceAccessMessage() {
    if (_allowPastAttendanceEdit) {
      return 'Administración habilitó acceso retroactivo para fechas anteriores.';
    }
    final until = _pastAttendanceEditUntil;
    if (until != null && _hasPastAttendanceOverride) {
      final label =
          '${_two(until.day)}/${_two(until.month)}/${until.year} ${_two(until.hour)}:${_two(until.minute)}';
      return 'Administración habilitó acceso retroactivo hasta $label.';
    }
    return 'Solo se permite registrar asistencia de hoy y ayer. Para fechas anteriores, administración debe habilitar acceso.';
  }

  String? _todayWorkDayKey() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final d in _workDays) {
      if (d.year == today.year && d.month == today.month && d.day == today.day) {
        return _dateKey(d);
      }
    }
    return null;
  }

  String _studentNameById(String studentId) {
    for (final st in _students) {
      if (st.id == studentId) return st.name;
    }
    return studentId;
  }

  String _readStudentFullName(Map<String, dynamic> m, String fallbackId) {
    String s(dynamic v) => (v ?? '').toString().trim();

    String pick(List<String> keys) {
      for (final k in keys) {
        final v = s(m[k]);
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final first = pick(['nombres', 'nombre', 'primerNombre', 'firstName', 'name']);
    final middle = pick(['segundoNombre', 'middleName']);
    final last1 =
        pick(['apellidos', 'apellido', 'primerApellido', 'apellidoPaterno', 'lastName', 'surname']);
    final last2 = pick(['segundoApellido', 'apellidoMaterno', 'lastName2', 'secondSurname']);

    final parts = <String>[];
    if (first.isNotEmpty) parts.add(first);
    if (middle.isNotEmpty) parts.add(middle);
    if (last1.isNotEmpty) parts.add(last1);
    if (last2.isNotEmpty) parts.add(last2);

    final built = parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final full = pick(['fullName', 'nombreCompleto', 'displayName', 'studentName', 'estudiante', 'alumno']);

    int words(String x) => x.split(' ').where((p) => p.trim().isNotEmpty).length;

    if (built.isNotEmpty && words(built) >= 2) return built;
    if (full.isNotEmpty && words(full) >= 2) return full;
    if (built.isNotEmpty) return built;
    if (full.isNotEmpty) return full;

    return fallbackId;
  }

  String _readStudentMatricula(Map<String, dynamic> m) {
    return (m['matricula'] ??
            m['matrícula'] ??
            m['numeroMatricula'] ??
            m['noMatricula'] ??
            m['codigo'] ??
            m['studentNumber'] ??
            '')
        .toString()
        .trim();
  }

  int _matriculaSortKey(String s) {
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 1 << 30;
    return int.tryParse(digits) ?? (1 << 30);
  }

  String _readSubjectName(Map<String, dynamic> m, String fallbackId) {
    return (m['name'] ?? m['nombre'] ?? m['title'] ?? m['asignatura'] ?? m['materia'] ?? fallbackId)
        .toString()
        .trim();
  }

  List<String> _asStringList(dynamic v) {
    if (v is List) {
      return v.map((e) => e.toString().trim()).where((x) => x.isNotEmpty).toList();
    }
    if (v is Map) {
      return v.keys.map((e) => e.toString().trim()).where((x) => x.isNotEmpty).toList();
    }
    final s = (v ?? '').toString().trim();
    return s.isNotEmpty ? [s] : <String>[];
  }

  _TeacherConstraints _buildTeacherConstraintsFromData(Map<String, dynamic> data) {
    final grades = <String>[
      ..._asStringList(data['grades']),
      ..._asStringList(data['grados']),
    ].toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final subjects = <String>[
      ..._asStringList(data['subjects']),
      ..._asStringList(data['materias']),
      ..._asStringList(data['asignaturas']),
    ].toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final allowPastAttendanceEdit = [
      data['allowPastAttendanceEdit'],
      data['attendancePastAccess'],
      data['attendanceLateEntryEnabled'],
      data['canEditPastAttendance'],
      data['attendanceRetroactiveEnabled'],
    ].any(_readBoolish);

    final pastAttendanceEditUntil = _parseDateTimeValue(
      data['attendancePastAccessUntil'] ??
          data['attendanceLateEntryUntil'] ??
          data['pastAttendanceEditUntil'] ??
          data['attendanceRetroactiveUntil'],
    );

    return _TeacherConstraints(
      grades: grades,
      subjects: subjects,
      allowPastAttendanceEdit: allowPastAttendanceEdit,
      pastAttendanceEditUntil: pastAttendanceEditUntil,
    );
  }

  // ============================================================
  // Cargar restricciones del docente (grades/subjects)
  // ============================================================
  Future<_TeacherConstraints> _loadTeacherConstraints(User user) async {
    final emailRaw = (user.email ?? '').trim();
    final emailLower = emailRaw.toLowerCase();
    final uid = user.uid;

    // Candidates por si el docId no coincide al 100%
    final schoolCandidates = <String>{
      _schoolId,
      _schoolId.toLowerCase(),
      _schoolId.toUpperCase(),
      _schoolId.replaceAll('/', '_'),
    }.where((e) => e.trim().isNotEmpty).toList();

    Future<QueryDocumentSnapshot<Map<String, dynamic>>?> findOne(
      CollectionReference<Map<String, dynamic>> ref,
      String field,
      String value,
    ) async {
      if (value.trim().isEmpty) return null;
      try {
        final q = await ref.where(field, isEqualTo: value.trim()).limit(1).get();
        if (q.docs.isNotEmpty) return q.docs.first;
      } catch (_) {}
      return null;
    }

    for (final root in const ['schools', 'escuelas']) {
      for (final sid in schoolCandidates) {
        try {
          final teachersRef = _db.collection(root).doc(sid).collection('teachers');
          final teacherUidRef = _db.collection(root).doc(sid).collection('teachers_uid').doc(uid);

          try {
            final teacherUidSnap = await teacherUidRef.get();
            final teacherDocId = (teacherUidSnap.data()?['teacherDocId'] ?? '').toString().trim();
            if (teacherDocId.isNotEmpty) {
              final teacherDoc = await teachersRef.doc(teacherDocId).get();
              if (teacherDoc.exists) {
                _rootCol = root;
                _schoolId = sid;
                return _buildTeacherConstraintsFromData(teacherDoc.data() ?? <String, dynamic>{});
              }
            }
          } catch (_) {}

          QueryDocumentSnapshot<Map<String, dynamic>>? snap;
          snap = await findOne(teachersRef, 'authUid', uid) ?? snap;

          if (snap == null && emailLower.isNotEmpty) {
            snap = await findOne(teachersRef, 'emailLower', emailLower) ?? snap;
          }
          if (snap == null && emailRaw.isNotEmpty) {
            snap = await findOne(teachersRef, 'email', emailRaw) ?? snap;
          }

// ✅ Fallback limpio: docId == uid (DocumentSnapshot directo)
if (snap == null) {
  try {
    final byId = await teachersRef.doc(uid).get();
    if (byId.exists) {
      _rootCol = root;
      _schoolId = sid;

      return _buildTeacherConstraintsFromData(byId.data() ?? <String, dynamic>{});
    }
  } catch (_) {}
}

          if (snap != null) {
            _rootCol = root; // root real encontrado
            // Ajusta también schoolId real encontrado
            _schoolId = sid;

            return _buildTeacherConstraintsFromData(snap.data());
          }
        } catch (_) {}
      }
    }

    return const _TeacherConstraints(
      grades: [],
      subjects: [],
      allowPastAttendanceEdit: false,
      pastAttendanceEditUntil: null,
    );
  }

  // ============================================================
  // Catálogos (grados / asignaturas)
  // ============================================================
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _safeFetch(
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    try {
      final s = await col.orderBy('order').get();
      return s.docs;
    } catch (_) {
      try {
        final s = await col.orderBy('nameLower').get();
        return s.docs;
      } catch (_) {
        final s = await col.get();
        return s.docs;
      }
    }
  }

  Future<void> _loadCatalogGrades() async {
    final ref = _db.collection(_rootCol).doc(_schoolId).collection('grados');

    try {
      final docs = await _safeFetch(ref);

      final out = <String>{};
      _gradeLabelToId.clear();

      for (final d in docs) {
        final m = d.data();
        final label = (m['name'] ?? m['nombre'] ?? m['label'] ?? m['gradoKey'] ?? d.id).toString().trim();
        final id = d.id;

        if (label.isNotEmpty) {
          out.add(label);
          _gradeLabelToId[label] = id;
          _gradeLabelToId[label.toLowerCase().trim()] = id;
        }

        // fallback: permitir usar el propio id como “label”
        if (id.trim().isNotEmpty) {
          _gradeLabelToId[id] = id;
          _gradeLabelToId[id.toLowerCase().trim()] = id;
        }
      }

      final list = out.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      _grades = list;
    } catch (e) {
    }
  }

  Future<void> _loadCatalogSubjects() async {
    final cols = ['subjects', 'materias', 'asignaturas'];
    final out = <String>{};

    for (final c in cols) {
      final ref = _db.collection(_rootCol).doc(_schoolId).collection(c);
      try {
        final docs = await _safeFetch(ref);
        for (final d in docs) {
          final m = d.data();
          final name = _readSubjectName(m, d.id);
          if (name.isNotEmpty) out.add(name);
        }
      } catch (_) {}
      if (out.isNotEmpty) break;
    }

    final list = out.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    _subjects = list;
  }

  // ============================================================
  // Alumnos: por grado (con fallbacks)
  // ============================================================
  Future<List<_StudentRow>> _fetchStudentsForGrade({
    required String gradeId,
    required String gradeLabel,
  }) async {
    final colNames = ['students', 'alumnos', 'estudiantes'];
    final labelFields = ['gradeLabel', 'grado', 'gradoLabel', 'grade', 'gradeName'];

    void sortRows(List<_StudentRow> rows) {
      rows.sort((a, b) {
        final ak = _matriculaSortKey(a.matricula);
        final bk = _matriculaSortKey(b.matricula);
        if (ak != bk) return ak.compareTo(bk);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }

    // 0) Preferido: grados/{gradeId}/subcolección
    if (gradeId.trim().isNotEmpty) {
      try {
        final gradeDoc =
            _db.collection(_rootCol).doc(_schoolId).collection('grados').doc(gradeId.trim());

        for (final sub in const ['alumnos', 'estudiantes', 'students']) {
          final snap = await gradeDoc.collection(sub).limit(800).get();
          if (snap.docs.isNotEmpty) {
            final rows = snap.docs.map((d) {
              final m = d.data();
              return _StudentRow(
                id: d.id,
                name: _readStudentFullName(m, d.id),
                matricula: _readStudentMatricula(m),
              );
            }).toList();
            sortRows(rows);
            return rows;
          }
        }
      } catch (e) {
      }
    }

    // 1) Colecciones globales: por gradeId y luego por label
    for (final col in colNames) {
      final ref = _db.collection(_rootCol).doc(_schoolId).collection(col);

      // 1A) por gradeId
      if (gradeId.trim().isNotEmpty) {
        for (final f in const ['gradeId', 'gradoId']) {
          try {
            final q = await ref.where(f, isEqualTo: gradeId.trim()).limit(800).get();
            if (q.docs.isNotEmpty) {
              final rows = q.docs.map((d) {
                final m = d.data();
                return _StudentRow(
                  id: d.id,
                  name: _readStudentFullName(m, d.id),
                  matricula: _readStudentMatricula(m),
                );
              }).toList();
              sortRows(rows);
              return rows;
            }
          } catch (_) {}
        }
      }

      // 1B) por label
      for (final f in labelFields) {
        try {
          final q = await ref.where(f, isEqualTo: gradeLabel).limit(800).get();
          if (q.docs.isNotEmpty) {
            final rows = q.docs.map((d) {
              final m = d.data();
              return _StudentRow(
                id: d.id,
                name: _readStudentFullName(m, d.id),
                matricula: _readStudentMatricula(m),
              );
            }).toList();
            sortRows(rows);
            return rows;
          }
        } catch (_) {}
      }
    }

    return <_StudentRow>[];
  }

  // ============================================================
  // Firestore: cargar/guardar hoja
  // schools/{sid}/asistencia/{sheetId}
  //   subcollection: rows/{studentId} con campos m_yyyyMMdd
  // ============================================================
  Future<void> _reloadSheet() async {
    final g = (_selectedGrade ?? '').trim();
    final s = (_selectedSubject ?? '').trim();

    _year = _calendarYearForMonth(_month);
    _workDays = _buildWorkDays(_year, _month);

    if (g.isEmpty || s.isEmpty) {
      if (!mounted) return;
      setState(() {
        _students = [];
        _marks.clear();
        _loading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final gradeLabel = g;
      final gradeId =
          _gradeLabelToId[gradeLabel] ?? _gradeLabelToId[gradeLabel.toLowerCase().trim()] ?? '';

      final students = await _fetchStudentsForGrade(
        gradeId: gradeId,
        gradeLabel: gradeLabel,
      );

      final sheetId = _sheetDocId();
      final sheetDoc = _db.collection(_rootCol).doc(_schoolId).collection('asistencia').doc(sheetId);
      final rowsCol = sheetDoc.collection('rows');

      final loaded = <String, Map<String, String>>{};
      final loadedReasons = <String, Map<String, String>>{};

      try {
        final rowsSnap = await rowsCol.get();
        for (final d in rowsSnap.docs) {
          final data = d.data();
          final m = <String, String>{};
          final reasons = <String, String>{};

          data.forEach((k, v) {
            if (k.startsWith('m_')) {
              final dk = k.substring(2);
              final vv = (v ?? '').toString().trim().toUpperCase();
              if (vv == markP || vv == markA || vv == markE) m[dk] = vv;
            } else if (k.startsWith('r_')) {
              final dk = k.substring(2);
              final rv = (v ?? '').toString().trim();
              if (rv.isNotEmpty) reasons[dk] = rv;
            }
          });

          loaded[d.id] = m;
          loadedReasons[d.id] = reasons;
        }
      } catch (e) {
      }

      _marks
        ..clear()
        ..addAll(loaded);
      _excuseReasons
        ..clear()
        ..addAll(loadedReasons);

      for (final st in students) {
        _marks.putIfAbsent(st.id, () => <String, String>{});
        _excuseReasons.putIfAbsent(st.id, () => <String, String>{});
      }

      if (!mounted) return;
      setState(() {
        _students = students;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Error cargando hoja: $e';
      });
    }
  }

  Future<void> _saveSheet() async {
    final user = _auth.currentUser;
    if (user == null) {
      _snack('No hay sesión activa.');
      return;
    }

    final g = (_selectedGrade ?? '').trim();
    final s = (_selectedSubject ?? '').trim();

    if (g.isEmpty || s.isEmpty) {
      _snack('Selecciona Grado y Asignatura.');
      return;
    }
    if (_students.isEmpty) {
      _snack('No hay alumnos para guardar.');
      return;
    }

    final sheetId = _sheetDocId();
    final sheetDoc = _db.collection(_rootCol).doc(_schoolId).collection('asistencia').doc(sheetId);
    final rowsCol = sheetDoc.collection('rows');

    // 1) Guardar meta primero
    try {
      await sheetDoc.set({
        'schoolId': _schoolId,
        'monthKey': _monthKey(),
        'schoolYear': _schoolYearLabel(),
        'anioEscolar': _schoolYearLabel(),
        'yearStart': _schoolYearStart,
        'yearEnd': _schoolYearStart + 1,
        'year': _year,
        'month': _month,
        'gradeLabel': g,
        'subject': s,
        'teacherUid': user.uid,
        'teacherName': (user.displayName ?? user.email ?? '').toString(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'workDays': _workDays.length,
      }, SetOptions(merge: true));
    } catch (e) {
      _snack('Error guardando encabezado: $e');
      return;
    }

    // 2) Guardar rows en batch
    final batch = _db.batch();
    int writes = 0;

    for (final st in _students) {
      final m = _marks[st.id] ?? <String, String>{};
      final reasons = _excuseReasons[st.id] ?? <String, String>{};

      bool hasAny = false;
      final payload = <String, dynamic>{
        'studentName': st.name,
        'matricula': st.matricula,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      for (final d in _workDays) {
        final dk = _dateKey(d);
        if (_isFutureDay(d)) {
          payload['m_$dk'] = FieldValue.delete();
          payload['r_$dk'] = FieldValue.delete();
          continue;
        }
        if (!_canEditDay(d)) {
          continue;
        }
        final v = (m[dk] ?? '').toString().trim().toUpperCase();
        if (v == markP || v == markA || v == markE) {
          payload['m_$dk'] = v;
          if (v == markE) {
            final reason = (reasons[dk] ?? '').trim();
            if (reason.isNotEmpty) {
              payload['r_$dk'] = reason;
            }
          } else {
            payload['r_$dk'] = FieldValue.delete();
          }
          hasAny = true;
        } else {
          payload['m_$dk'] = FieldValue.delete();
          payload['r_$dk'] = FieldValue.delete();
        }
      }

      if (!hasAny) continue;
      batch.set(rowsCol.doc(st.id), payload, SetOptions(merge: true));
      final alumnoAttendanceDoc = _db
          .collection(_rootCol)
          .doc(_schoolId)
          .collection('alumnos')
          .doc(st.id)
          .collection('asistencia')
          .doc(sheetId);
      batch.set(
        alumnoAttendanceDoc,
        {
          'schoolId': _schoolId,
          'sheetId': sheetId,
          'studentId': st.id,
          'studentName': st.name,
          'matricula': st.matricula,
          'monthKey': _monthKey(),
          'schoolYear': _schoolYearLabel(),
          'anioEscolar': _schoolYearLabel(),
          'yearStart': _schoolYearStart,
          'yearEnd': _schoolYearStart + 1,
          'year': _year,
          'month': _month,
          'gradeLabel': g,
          'subject': s,
          'teacherUid': user.uid,
          'teacherName': (user.displayName ?? user.email ?? '').toString(),
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'workDays': _workDays.length,
          ...payload,
        },
        SetOptions(merge: true),
      );
      writes++;
    }

    try {
      await batch.commit();
      _snack(writes == 0 ? 'Nada que guardar (sin marcas).' : 'Asistencia guardada.');
    } catch (e) {
      _snack('Error guardando filas: $e');
    }
  }

  // ============================================================
  // UI / Interacciones
  // ============================================================
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleCell(String studentId, DateTime day) async {
    final blockedReason = _dayEditBlockedReason(day);
    if (blockedReason != null) {
      _snack(blockedReason);
      return;
    }

    final dateKey = _dateKey(day);
    final map = _marks.putIfAbsent(studentId, () => <String, String>{});
    final reasons = _excuseReasons.putIfAbsent(studentId, () => <String, String>{});
    final cur = (map[dateKey] ?? '').toUpperCase();

    String next;
    if (cur.isEmpty) {
      next = markP;
    } else if (cur == markP) {
      next = markA;
    } else if (cur == markA) {
      next = markE;
    } else {
      next = '';
    }

    String? excuseReason;
    if (next == markE) {
      excuseReason = await _askExcuseReason(
        studentName: _studentNameById(studentId),
        currentReason: reasons[dateKey] ?? '',
      );
      if (excuseReason == null) return;
    }

    setState(() {
      if (next.isEmpty) {
        map.remove(dateKey);
        reasons.remove(dateKey);
      } else {
        map[dateKey] = next;
        if (next == markE) {
          reasons[dateKey] = excuseReason!.trim();
        } else {
          reasons.remove(dateKey);
        }
      }
    });
  }

  void _setAllForDay(String dateKey, String value) {
    setState(() {
      for (final st in _students) {
        final map = _marks.putIfAbsent(st.id, () => <String, String>{});
        final reasons = _excuseReasons.putIfAbsent(st.id, () => <String, String>{});
        if (value.isEmpty) {
          map.remove(dateKey);
          reasons.remove(dateKey);
        } else {
          map[dateKey] = value;
          if (value != markE) {
            reasons.remove(dateKey);
          }
        }
      }
    });
  }

  Future<String?> _askExcuseReason({
    required String studentName,
    String currentReason = '',
  }) async {
    final controller = TextEditingController(text: currentReason);
    String? errorText;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Motivo de excusa'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(studentName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      maxLines: 3,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Razón de la excusa',
                        errorText: errorText,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final reason = controller.text.trim();
                    if (reason.isEmpty) {
                      setLocalState(() => errorText = 'La razón de la excusa es obligatoria.');
                      return;
                    }
                    Navigator.of(context).pop(reason);
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return result;
  }

  Widget _errorBox(String msg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.25)),
      ),
      child: Text(msg, style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _headerCard() {
    const months = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];

    final todayKey = _todayWorkDayKey();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: secondaryColor.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            blurRadius: 14,
            offset: const Offset(0, 6),
            color: Colors.black.withOpacity(0.06),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Días de trabajo',
            style: TextStyle(
              color: Colors.black.withOpacity(0.85),
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 750;

              final monthDrop = DropdownButtonFormField<int>(
                value: _month,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Mes',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: List.generate(12, (i) {
                  final m = i + 1;
                  return DropdownMenuItem(value: m, child: Text(months[i]));
                }),
                onChanged: (v) async {
                  if (v == null) return;
                  setState(() {
                    _month = v;
                    _year = _calendarYearForMonth(v);
                  });
                  await _reloadSheet();
                },
              );

              final schoolYearField = InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Año',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                child: Text(
                  _schoolYearLabel(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              );

              final gradeDrop = DropdownButtonFormField<String>(
                value: _selectedGrade,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Grado',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: _grades.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (v) async {
                  setState(() => _selectedGrade = v);
                  await _reloadSheet();
                },
              );

              final subjectDrop = DropdownButtonFormField<String>(
                value: _selectedSubject,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Asignatura',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: _subjects.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) async {
                  setState(() => _selectedSubject = v);
                  await _reloadSheet();
                },
              );

              final info = Row(
                children: [
                  Expanded(
                    child: Text(
                      'Dias Laborables (Lunes a Viernes): ${_workDays.length}',
                      style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.6)),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: (_students.isEmpty || todayKey == null)
                        ? null
                        : () => _setAllForDay(todayKey, markP),
                    icon: const Icon(Icons.done_all, size: 16),
                    label: const Text('Marcar hoy P'),
                    style: TextButton.styleFrom(foregroundColor: secondaryColor),
                  ),
                ],
              );

              final toolbar = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  info,
                  if (todayKey == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'El marcado global solo aplica al día de hoy cuando ese día pertenece al mes visible.',
                        style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
                      ),
                    ),
                ],
              );

              if (narrow) {
                return Column(
                  children: [
                    monthDrop,
                    const SizedBox(height: 10),
                    schoolYearField,
                    const SizedBox(height: 10),
                    gradeDrop,
                    const SizedBox(height: 10),
                    subjectDrop,
                    const SizedBox(height: 8),
                    toolbar,
                  ],
                );
              }

              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: monthDrop),
                      const SizedBox(width: 10),
                      Expanded(child: schoolYearField),
                      const SizedBox(width: 10),
                      Expanded(child: gradeDrop),
                      const SizedBox(width: 10),
                      Expanded(child: subjectDrop),
                    ],
                  ),
                  const SizedBox(height: 8),
                  toolbar,
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.28)),
            ),
            child: Text(
              'Toque una celda para alternar: P, A, E y vacío. ${_attendanceAccessMessage()} La excusa exige motivo obligatorio.',
              style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.72)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableDaysBandRow({required double firstColW}) {
    final daysWidth = _workDays.length * _dayColWidth;

    Widget box(double w, Widget child) {
      return Container(
        width: w,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.10),
          border: Border.all(color: secondaryColor.withOpacity(0.18)),
        ),
        child: child,
      );
    }

    return Row(
      children: [
        box(firstColW, const SizedBox()),
        box(
          daysWidth,
          const Text(
            'DÍAS TRABAJADOS',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
          ),
        ),
        box(_totalColWidth, const SizedBox()),
        box(_pctColWidth, const SizedBox()),
      ],
    );
  }

  Widget _tableHeaderRow({required double firstColW}) {
    Widget cellBox({
      required double w,
      required Widget child,
      Alignment align = Alignment.center,
    }) {
      return Container(
        width: w,
        height: 34,
        alignment: align,
        decoration: BoxDecoration(
          color: secondaryColor.withOpacity(0.06),
          border: Border.all(color: secondaryColor.withOpacity(0.18)),
        ),
        child: child,
      );
    }

    return Row(
      children: [
        cellBox(
          w: firstColW,
          align: Alignment.centerLeft,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'Matrícula · Estudiante',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
        ),
        ..._workDays.map((d) {
          final dayNum = d.day.toString();
          final dk = _dateKey(d);

          return cellBox(
            w: _dayColWidth,
            child: Text(dayNum, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
          );
        }),
        cellBox(
          w: _totalColWidth,
          child: const Text('T', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
        ),
        cellBox(
          w: _pctColWidth,
          child: const Text('%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }

  List<_ExcuseItem> _collectExcuses() {
    final out = <_ExcuseItem>[];
    for (final st in _students) {
      final marks = _marks[st.id] ?? const <String, String>{};
      final reasons = _excuseReasons[st.id] ?? const <String, String>{};
      for (final d in _workDays) {
        final dk = _dateKey(d);
        if ((marks[dk] ?? '').toUpperCase() != markE) continue;
        final reason = (reasons[dk] ?? '').trim();
        out.add(
          _ExcuseItem(
            studentName: st.name,
            date: d,
            reason: reason,
          ),
        );
      }
    }
    out.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      return a.studentName.toLowerCase().compareTo(b.studentName.toLowerCase());
    });
    return out;
  }

  Widget _excusesPanel() {
    final excuses = _collectExcuses();
    if (excuses.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withOpacity(0.28)),
        boxShadow: [
          BoxShadow(
            blurRadius: 14,
            offset: const Offset(0, 6),
            color: Colors.black.withOpacity(0.06),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _showExcuses = !_showExcuses),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.assignment_late_rounded, color: Colors.amber.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Excusas registradas (${excuses.length})',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                  ),
                  Icon(
                    _showExcuses ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: secondaryColor,
                  ),
                ],
              ),
            ),
          ),
          if (_showExcuses) ...[
            const SizedBox(height: 10),
            ...excuses.map((excuse) {
              final labelDate = '${_two(excuse.date.day)}/${_two(excuse.date.month)}/${excuse.date.year}';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.30)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${excuse.studentName} · $labelDate',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(excuse.reason),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _studentLine(_StudentRow st, {required double firstColW}) {
    final present = _presentCountForStudent(st.id);
    final pct = _pctForStudent(st.id);

    Color markBg(String v) {
      if (v == markP) return Colors.green.withOpacity(0.18);
      if (v == markA) return Colors.red.withOpacity(0.18);
      if (v == markE) return Colors.amber.withOpacity(0.22);
      return Colors.transparent;
    }

    Color markBorder(String v) {
      if (v == markP) return Colors.green.withOpacity(0.55);
      if (v == markA) return Colors.red.withOpacity(0.55);
      if (v == markE) return Colors.amber.withOpacity(0.72);
      return secondaryColor.withOpacity(0.18);
    }

    Widget nameCell() {
      final mat = st.matricula.isNotEmpty ? st.matricula : '--';
      return Container(
        width: firstColW,
        height: _dayColHeight,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: secondaryColor.withOpacity(0.18)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: primaryColor.withOpacity(0.35)),
                ),
                child: Text(mat, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  st.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget dayCell(DateTime d) {
      final dk = _dateKey(d);
      final v = (_marks[st.id]?[dk] ?? '').toUpperCase();
      final canEdit = _canEditDay(d);

      return GestureDetector(
        onTap: canEdit ? () => _toggleCell(st.id, d) : null,
        child: Container(
          width: _dayColWidth,
          height: _dayColHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: canEdit ? markBg(v) : Colors.grey.withOpacity(0.10),
            border: Border.all(
              color: canEdit ? markBorder(v) : secondaryColor.withOpacity(0.10),
            ),
          ),
          child: Text(
            v,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: !canEdit
                  ? Colors.black38
                  : v == markA
                      ? Colors.red.shade800
                      : (v == markE ? Colors.amber.shade900 : Colors.black87),
            ),
          ),
        ),
      );
    }

    Widget totalCell() {
      return Container(
        width: _totalColWidth,
        height: _dayColHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: secondaryColor.withOpacity(0.18)),
        ),
        child: Text('$present', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
      );
    }

    Widget pctCell() {
      return Container(
        width: _pctColWidth,
        height: _dayColHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: secondaryColor.withOpacity(0.18)),
        ),
        child: Text(
          pct,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: Colors.black.withOpacity(0.75),
          ),
        ),
      );
    }

    return Row(
      children: [
        nameCell(),
        ..._workDays.map(dayCell),
        totalCell(),
        pctCell(),
      ],
    );
  }

  Widget _sheetTable() {
    if ((_selectedGrade ?? '').trim().isEmpty || (_selectedSubject ?? '').trim().isEmpty) {
      return Center(
        child: Text(
          'Selecciona Mes/Año, Grado y Asignatura.',
          style: TextStyle(color: Colors.black.withOpacity(0.65)),
        ),
      );
    }

    if (_students.isEmpty) {
      return Center(
        child: Text(
          'No se encontraron alumnos para el grado seleccionado.',
          style: TextStyle(color: Colors.black.withOpacity(0.65)),
          textAlign: TextAlign.center,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final height = c.maxHeight;
        final availableW = c.maxWidth;

        final baseTotalW = _firstColWidthBase +
            (_workDays.length * _dayColWidth) +
            _totalColWidth +
            _pctColWidth;

        final firstColW =
            (availableW > baseTotalW) ? (_firstColWidthBase + (availableW - baseTotalW)) : _firstColWidthBase;

        final totalWidth = (availableW > baseTotalW) ? availableW : baseTotalW;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalWidth,
            height: height,
            child: Column(
              children: [
                _tableDaysBandRow(firstColW: firstColW),
                _tableHeaderRow(firstColW: firstColW),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView.builder(
                    itemCount: _students.length,
                    itemBuilder: (_, i) => _studentLine(_students[i], firstColW: firstColW),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final nombreEscuela = (_escuela?.nombre ?? '').trim();
    final hasExcuses = _collectExcuses().isNotEmpty;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: buildDocenteBackAppBar(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // Nombre escuela pequeño (sin barra azul)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        nombreEscuela,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: Colors.black.withOpacity(0.70),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_error != null) ...[
                      _errorBox(_error!),
                      const SizedBox(height: 10),
                    ],
                    _headerCard(),
                    if (hasExcuses) ...[
                      const SizedBox(height: 12),
                      _excusesPanel(),
                    ],
                    const SizedBox(height: 12),
                    Expanded(child: _sheetTable()),
                  ],
                ),
        ),
      ),

      // Guardar (no AppBar azul)
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _saveSheet,
        icon: const Icon(Icons.save),
        label: const Text('Guardar'),
      ),
    );
  }
}

/// ============================================================
/// Modelos internos (TOP-LEVEL)
/// ============================================================
class _StudentRow {
  final String id;
  final String name;
  final String matricula;

  const _StudentRow({
    required this.id,
    required this.name,
    required this.matricula,
  });
}

class _ExcuseItem {
  final String studentName;
  final DateTime date;
  final String reason;

  const _ExcuseItem({
    required this.studentName,
    required this.date,
    required this.reason,
  });
}

class _TeacherConstraints {
  final List<String> grades;
  final List<String> subjects;
  final bool allowPastAttendanceEdit;
  final DateTime? pastAttendanceEditUntil;

  const _TeacherConstraints({
    required this.grades,
    required this.subjects,
    required this.allowPastAttendanceEdit,
    required this.pastAttendanceEditUntil,
  });
}

