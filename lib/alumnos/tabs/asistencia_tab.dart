import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

class AsistenciaTab extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> estRef;
  const AsistenciaTab({super.key, required this.estRef});

  @override
  State<AsistenciaTab> createState() => _AsistenciaTabState();
}

class _AsistenciaTabState extends State<AsistenciaTab> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // UI colors (alineado a tu estilo)
  static const Color azul = Color.fromARGB(255, 21, 101, 192);
  static const Color naranja = Color.fromARGB(255, 255, 193, 7);

  late int _month;
  late int _year;
  late int _schoolYearStart;

  bool _loading = true;
  String? _error;

  // Contexto
  String _rootCol = 'schools';
  String _schoolId = '';
  String _studentId = '';
  String _gradeLabel = '';

  // Datos cargados
  List<DateTime> _workDays = [];
  final Map<String, _SubjectSheet> _subjects = {}; // sheetId -> data
  final Map<String, _DayAgg> _days = {}; // dateKey -> agg

  // Historial (opcional)
  List<_MonthHistory> _history = [];
  final List<String> _diag = [];

  bool _booted = false;

  void _dlog(String message) {
    if (!kDebugMode) return;
    _diag.add(message);
    if (_diag.length > 24) {
      _diag.removeRange(0, _diag.length - 24);
    }
    debugPrint('[alumno_asistencia] $message');
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = now.month;
    _schoolYearStart = _resolveSchoolYearStart(now);
    _year = _calendarYearForMonth(_month);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_booted) return;
    _booted = true;

    _deriveContextFromRef();
    _reload();
  }

  void _deriveContextFromRef() {
    _studentId = widget.estRef.id;

    // estRef = schools/{schoolId}/alumnos/{studentId}
    final schoolDoc = widget.estRef.parent.parent;
    if (schoolDoc == null) {
      _error = 'No pude derivar schoolId desde estRef.';
      _loading = false;
      return;
    }

    _schoolId = schoolDoc.id;
    _rootCol = schoolDoc.parent.id; // "schools" o "escuelas" (si aplica)
  }

  // =========================
  // Helpers fechas / keys
  // =========================
  String _two(int n) => n.toString().padLeft(2, '0');
  String _monthKey() => '${_year}${_two(_month)}'; // yyyyMM
  String _dateKey(DateTime d) => '${d.year}${_two(d.month)}${_two(d.day)}'; // yyyyMMdd

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

  String _monthName(int m) {
    const months = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];
    return months[(m - 1).clamp(0, 11)];
  }

  int _resolveSchoolYearStart(DateTime date) {
    return date.month >= 8 ? date.year : date.year - 1;
  }

  int? _schoolYearStartFromRaw(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;

    final match = RegExp(r'^(\d{4})\s*-\s*(\d{4})$').firstMatch(raw);
    if (match != null) return int.tryParse(match.group(1)!);

    final year = int.tryParse(raw);
    if (year == null) return null;
    if (year >= 2000 && year <= 2100) {
      return year >= 2050 ? year - 1 : year;
    }
    return null;
  }

  int _calendarYearForMonth(int month) {
    return month >= 8 ? _schoolYearStart : _schoolYearStart + 1;
  }

  String _schoolYearLabel() => '$_schoolYearStart-${_schoolYearStart + 1}';

  List<String> _monthKeyCandidates() {
    return <String>{
      _monthKey(),
      '${_schoolYearStart}${_two(_month)}',
      '${_schoolYearStart + 1}${_two(_month)}',
    }.toList();
  }

  String _sanitize(String value) {
    final s = value.trim().toLowerCase();
    return s.replaceAll(RegExp(r'[^a-z0-9_-]+'), '_');
  }

  String _sheetDocIdFor(String monthKey, String gradeLabel, String subjectName) {
    return '${monthKey}__${_sanitize(gradeLabel)}__${_sanitize(subjectName)}';
  }

  String _subjectNameFromData(Map<String, dynamic> data, String fallbackId) {
    return (data['name'] ?? data['nombre'] ?? data['title'] ?? data['asignatura'] ?? data['materia'] ?? fallbackId)
        .toString()
        .trim();
  }

  Future<List<String>> _loadSubjectCandidates() async {
    final out = <String>{};
    for (final collectionName in const ['subjects', 'asignaturas', 'materias']) {
      try {
        final snap = await _db.collection(_rootCol).doc(_schoolId).collection(collectionName).get();
        for (final doc in snap.docs) {
          final name = _subjectNameFromData(doc.data(), doc.id);
          if (name.isNotEmpty) out.add(name);
        }
      } catch (_) {}
    }
    final list = out.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Future<void> _syncSelectedAlumnoIdForRules() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _dlog('login sync skipped: no current user');
      return;
    }

    final emailLower = (user.email ?? '').trim().toLowerCase();
    final loginCandidates = <DocumentReference<Map<String, dynamic>>>[];
    final loginCol = _db.collection(_rootCol).doc(_schoolId).collection('alumnos_login');

    if (emailLower.isNotEmpty) {
      loginCandidates.add(loginCol.doc(emailLower));
    }
    loginCandidates.add(loginCol.doc(user.uid));

    var foundAnyDoc = false;
    var matchedCurrentStudent = false;
    final refsToUpdate = <DocumentReference<Map<String, dynamic>>>[];

    for (final ref in loginCandidates) {
      try {
        final snap = await ref.get();
        if (!snap.exists) {
          _dlog('login sync miss doc=${ref.id}');
          continue;
        }

        foundAnyDoc = true;

        final data = snap.data() ?? <String, dynamic>{};
        final rawIds = [
          ...(data['studentIds'] is List ? data['studentIds'] as List : const []),
          ...(data['studentsIds'] is List ? data['studentsIds'] as List : const []),
          ...(data['alumnoIds'] is List ? data['alumnoIds'] as List : const []),
          ...(data['alumnosIds'] is List ? data['alumnosIds'] as List : const []),
        ];
        final ids = rawIds.map((e) => e.toString().trim()).where((x) => x.isNotEmpty).toSet().toList();
        final singleId = (data['alumnoId'] ?? '').toString().trim();
        if (singleId.isNotEmpty && !ids.contains(singleId)) ids.add(singleId);

        final selected = (data['selectedAlumnoId'] ?? '').toString().trim();
        _dlog('login sync doc=${ref.id} selected="$selected" ids=$ids containsCurrent=${ids.contains(_studentId)}');

        if (!ids.contains(_studentId)) {
          continue;
        }

        matchedCurrentStudent = true;
        if (selected != _studentId) {
          refsToUpdate.add(ref);
        }
      } catch (e) {
        _dlog('login sync error doc=${ref.id}: $e');
      }
    }

    if (!foundAnyDoc) {
      _dlog('login sync skipped: no alumnos_login docs found');
      return;
    }

    if (!matchedCurrentStudent) {
      _dlog('login sync skipped: current student not present in any alumnos_login doc');
      return;
    }

    if (refsToUpdate.isEmpty) {
      _dlog('login sync already aligned on all matching docs');
      return;
    }

    for (final ref in refsToUpdate) {
      try {
        await ref.update({
          'selectedAlumnoId': _studentId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _dlog('login sync updated doc=${ref.id} selectedAlumnoId=$_studentId');
      } catch (e) {
        _dlog('login sync update error doc=${ref.id}: $e');
      }
    }
  }

  bool _sheetMatchesSchoolYear(Map<String, dynamic> data, String schoolYearLabel) {
    final direct = (data['schoolYear'] ?? data['anioEscolar'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct == schoolYearLabel;

    final yearEnd = data['yearEnd'];
    if (yearEnd is int) return '${yearEnd - 1}-$yearEnd' == schoolYearLabel;

    final year = data['year'];
    if (year is String && year.contains('-')) return year == schoolYearLabel;

    return true;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _findStudentMirrorSheets(
    CollectionReference<Map<String, dynamic>> col,
    String schoolYearLabel,
    int monthNumber,
    String gradeLabel,
    List<String> monthKeys,
  ) async {
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = [];

    try {
      final q = await col
          .where('schoolYear', isEqualTo: schoolYearLabel)
          .where('month', isEqualTo: monthNumber)
          .where('gradeLabel', isEqualTo: gradeLabel)
          .get();
      docs = q.docs;
      _dlog('mirror query A schoolYear+month+grade => ${q.docs.length} sheets');
    } catch (e) {
      _dlog('mirror query A error: $e');
    }

    if (docs.isEmpty) {
      try {
        final q = await col
            .where('anioEscolar', isEqualTo: schoolYearLabel)
            .where('month', isEqualTo: monthNumber)
            .where('gradeLabel', isEqualTo: gradeLabel)
            .get();
        docs = q.docs;
        _dlog('mirror query B anioEscolar+month+grade => ${q.docs.length} sheets');
      } catch (e) {
        _dlog('mirror query B error: $e');
      }
    }

    if (docs.isEmpty) {
      try {
        final q = await col
            .where('schoolYear', isEqualTo: schoolYearLabel)
            .where('monthKey', isEqualTo: _monthKey())
            .where('gradeLabel', isEqualTo: gradeLabel)
            .get();
        docs = q.docs;
        _dlog('mirror query C schoolYear+monthKey(${_monthKey()})+grade => ${q.docs.length} sheets');
      } catch (e) {
        _dlog('mirror query C error: $e');
      }
    }

    if (docs.isEmpty) {
      try {
        final q = await col
            .where('anioEscolar', isEqualTo: schoolYearLabel)
            .where('monthKey', isEqualTo: _monthKey())
            .where('gradeLabel', isEqualTo: gradeLabel)
            .get();
        docs = q.docs;
        _dlog('mirror query D anioEscolar+monthKey(${_monthKey()})+grade => ${q.docs.length} sheets');
      } catch (e) {
        _dlog('mirror query D error: $e');
      }
    }

    if (docs.isEmpty) {
      for (final monthKey in monthKeys) {
        try {
          final q = await col
              .where('monthKey', isEqualTo: monthKey)
              .where('gradeLabel', isEqualTo: gradeLabel)
              .limit(40)
              .get();
          docs = q.docs.where((d) => _sheetMatchesSchoolYear(d.data(), schoolYearLabel)).toList();
          _dlog('mirror query E monthKey($monthKey)+grade filteredByPeriod => ${docs.length} sheets');
        } catch (e) {
          _dlog('mirror query E error monthKey=$monthKey: $e');
        }
        if (docs.isNotEmpty) break;
      }
    }

    return docs;
  }

  void _ingestEmbeddedAttendanceDoc(DocumentSnapshot<Map<String, dynamic>> sheet) {
    final meta = sheet.data() ?? <String, dynamic>{};
    final subjectName = (meta['subject'] ?? meta['asignatura'] ?? meta['materia'] ?? sheet.id)
        .toString()
        .trim();
    _dlog(
      'mirror sheet hit id=${sheet.id} subject="$subjectName" '
      'schoolYear=${meta['schoolYear']} anioEscolar=${meta['anioEscolar']} '
      'month=${meta['month']} monthKey=${meta['monthKey']} gradeLabel=${meta['gradeLabel']}',
    );

    final marks = <String, String>{};
    int p = 0, a = 0;

    meta.forEach((k, v) {
      if (!k.startsWith('m_')) return;
      final dk = k.substring(2);
      final vv = (v ?? '').toString().trim().toUpperCase();
      if (vv == 'P' || vv == 'A') {
        marks[dk] = vv;
        if (vv == 'P') p++;
        if (vv == 'A') a++;
      }
    });

    _subjects[sheet.id] = _SubjectSheet(
      sheetId: sheet.id,
      subject: subjectName,
      marks: marks,
      present: p,
      absent: a,
    );
    _dlog('mirror row parsed sheet=${sheet.id} subject="$subjectName" present=$p absent=$a marks=${marks.length}');
  }

  DateTime _startOfWeek(DateTime d) {
    final diff = d.weekday - DateTime.monday;
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: diff));
  }

  // =========================
  // Lecturas Firestore
  // =========================
  Future<void> _reload() async {
    if (_schoolId.trim().isEmpty || _studentId.trim().isEmpty) {
      setState(() {
        _loading = false;
        _error = _error ?? 'Falta contexto (schoolId/studentId).';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _subjects.clear();
      _days.clear();
      _history = [];
      _diag.clear();
    });

    try {
      // 1) Leer alumno para sacar gradoLabel y usar el periodo escolar actual
      final estSnap = await widget.estRef.get();
      final est = estSnap.data() ?? <String, dynamic>{};

      String s(dynamic v) => (v ?? '').toString().trim();

      final now = DateTime.now();
      _schoolYearStart = now.month >= 8 ? now.year : now.year - 1;

      _year = _calendarYearForMonth(_month);
      _workDays = _buildWorkDays(_year, _month);
      final schoolYearLabel = _schoolYearLabel();
      await _syncSelectedAlumnoIdForRules();

      // Intenta varios campos típicos
      final gradeLabel = s(est['gradeName']).isNotEmpty
          ? s(est['gradeName'])
          : (s(est['grado']).isNotEmpty ? s(est['grado']) : s(est['gradoSeleccionado']));

      _gradeLabel = gradeLabel.isNotEmpty ? gradeLabel : '—';

      // 2) Buscar hojas del mes para ese grado y periodo
      final studentAttendanceCol = widget.estRef.collection('asistencia');
      final asistenciaCol = _db.collection(_rootCol).doc(_schoolId).collection('asistencia');
      final monthKeys = _monthKeyCandidates();
      final monthNumber = _month;
      _dlog('reload schoolId=$_schoolId root=$_rootCol studentId=$_studentId');
      _dlog(
        'student schoolYear=${est['schoolYear']} anioEscolar=${est['anioEscolar']} '
        'gradeName=${est['gradeName']} grado=${est['grado']} gradoSeleccionado=${est['gradoSeleccionado']}',
      );
      _dlog(
        'params schoolYearLabel=$schoolYearLabel month=$_month year=$_year '
        'monthKeys=$monthKeys gradeLabel="$gradeLabel"',
      );

      final mirrorSheets = await _findStudentMirrorSheets(
        studentAttendanceCol,
        schoolYearLabel,
        monthNumber,
        gradeLabel,
        monthKeys,
      );
      if (mirrorSheets.isNotEmpty) {
        _dlog('using student mirror attendance docs count=${mirrorSheets.length}');
        for (final sheet in mirrorSheets) {
          _ingestEmbeddedAttendanceDoc(sheet);
        }
        _aggregateDays();
        _dlog('aggregate done from mirror subjects=${_subjects.length} workDays=${_workDays.length} totalP=$_totalP totalA=$_totalA');
        await _loadHistory(studentAttendanceCol, gradeLabel, embeddedRows: true);
        _dlog('mirror history loaded months=${_history.length}');
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }

      List<QueryDocumentSnapshot<Map<String, dynamic>>> sheets = [];
      final directSheets = <DocumentSnapshot<Map<String, dynamic>>>[];
      try {
        final q = await asistenciaCol
            .where('schoolYear', isEqualTo: schoolYearLabel)
            .where('month', isEqualTo: monthNumber)
            .where('gradeLabel', isEqualTo: gradeLabel)
            .get();
        sheets = q.docs;
        _dlog('query A schoolYear+month+grade => ${q.docs.length} sheets');
      } catch (e) {
        _dlog('query A error: $e');
      }

      if (sheets.isEmpty) {
        try {
          final q = await asistenciaCol
              .where('anioEscolar', isEqualTo: schoolYearLabel)
              .where('month', isEqualTo: monthNumber)
              .where('gradeLabel', isEqualTo: gradeLabel)
              .get();
          sheets = q.docs;
          _dlog('query B anioEscolar+month+grade => ${q.docs.length} sheets');
        } catch (e) {
          _dlog('query B error: $e');
        }
      }

      // Intento A: schoolYear + monthKey + gradeLabel
      if (sheets.isEmpty) {
        try {
          final q = await asistenciaCol
              .where('schoolYear', isEqualTo: schoolYearLabel)
              .where('monthKey', isEqualTo: _monthKey())
              .where('gradeLabel', isEqualTo: gradeLabel)
              .get();
          sheets = q.docs;
          _dlog('query C schoolYear+monthKey(${_monthKey()})+grade => ${q.docs.length} sheets');
        } catch (e) {
          _dlog('query C error: $e');
        }
      }

      // Intento B: anioEscolar + monthKey + gradeLabel
      if (sheets.isEmpty) {
        try {
          final q = await asistenciaCol
              .where('anioEscolar', isEqualTo: schoolYearLabel)
              .where('monthKey', isEqualTo: _monthKey())
              .where('gradeLabel', isEqualTo: gradeLabel)
              .get();
          sheets = q.docs;
          _dlog('query D anioEscolar+monthKey(${_monthKey()})+grade => ${q.docs.length} sheets');
        } catch (e) {
          _dlog('query D error: $e');
        }
      }

      // Intento C: monthKey + gradeLabel y filtramos en cliente por periodo
      if (sheets.isEmpty) {
        try {
          final q = await asistenciaCol
              .where('monthKey', isEqualTo: _monthKey())
              .where('gradeLabel', isEqualTo: gradeLabel)
              .limit(60)
              .get();
          sheets = q.docs.where((d) => _sheetMatchesSchoolYear(d.data(), schoolYearLabel)).toList();
          _dlog('query E monthKey(${_monthKey()})+grade filteredByPeriod => ${sheets.length} sheets');
        } catch (e) {
          _dlog('query E error: $e');
        }
      }

      // Intento D: monthKey solo (fallback) y filtramos en cliente por gradeLabel + periodo
      if (sheets.isEmpty) {
        try {
          final q = await asistenciaCol.where('monthKey', isEqualTo: _monthKey()).limit(60).get();
          sheets = q.docs.where((d) {
            final m = d.data();
            final gl = (m['gradeLabel'] ?? '').toString().trim();
            final gradeMatches = gradeLabel.isEmpty ? true : gl == gradeLabel;
            return gradeMatches && _sheetMatchesSchoolYear(m, schoolYearLabel);
          }).toList();
          _dlog('query F monthKey(${_monthKey()}) filteredByGrade+Period => ${sheets.length} sheets');
        } catch (e) {
          _dlog('query F error: $e');
        }
      }

      // Si sigue vacío, mostramos una pantalla útil (no “misteriosa”)
      if (sheets.isEmpty) {
        for (final monthKey in monthKeys) {
          if (monthKey == _monthKey()) continue;
          if (sheets.isNotEmpty) break;

          try {
            final q = await asistenciaCol
                .where('schoolYear', isEqualTo: schoolYearLabel)
                .where('monthKey', isEqualTo: monthKey)
                .where('gradeLabel', isEqualTo: gradeLabel)
                .get();
            sheets = q.docs;
            _dlog('query G schoolYear+monthKey($monthKey)+grade => ${q.docs.length} sheets');
          } catch (e) {
            _dlog('query G error monthKey=$monthKey: $e');
          }

          if (sheets.isNotEmpty) break;

          try {
            final q = await asistenciaCol
                .where('monthKey', isEqualTo: monthKey)
                .where('gradeLabel', isEqualTo: gradeLabel)
                .limit(60)
                .get();
            sheets = q.docs.where((d) => _sheetMatchesSchoolYear(d.data(), schoolYearLabel)).toList();
            _dlog('query H monthKey($monthKey)+grade filteredByPeriod => ${sheets.length} sheets');
          } catch (e) {
            _dlog('query H error monthKey=$monthKey: $e');
          }
        }
      }

      if (sheets.isEmpty) {
        final subjectCandidates = await _loadSubjectCandidates();
        _dlog(
          'direct subject candidates count=${subjectCandidates.length} '
          'sample=${subjectCandidates.take(8).toList()}',
        );
        final seenSheetIds = <String>{};

        for (final monthKey in monthKeys) {
          for (final subject in subjectCandidates) {
            final sheetId = _sheetDocIdFor(monthKey, gradeLabel, subject);
            if (!seenSheetIds.add(sheetId)) continue;
            try {
              final snap = await asistenciaCol.doc(sheetId).get();
              if (!snap.exists) continue;
              final data = snap.data() ?? <String, dynamic>{};
              if (!_sheetMatchesSchoolYear(data, schoolYearLabel)) {
                _dlog(
                  'direct get skip period mismatch sheetId=$sheetId '
                  'schoolYear=${data['schoolYear']} anioEscolar=${data['anioEscolar']}',
                );
                continue;
              }
              directSheets.add(snap);
              _dlog('direct get hit sheetId=$sheetId subject="$subject" monthKey=$monthKey');
            } catch (e) {
              _dlog('direct get error sheetId=$sheetId: $e');
            }
          }
        }
      }

      final effectiveSheets = directSheets.isNotEmpty
          ? directSheets
          : List<DocumentSnapshot<Map<String, dynamic>>>.from(sheets);

      if (effectiveSheets.isEmpty) {
        try {
          final sample = await asistenciaCol.limit(8).get();
          for (final doc in sample.docs) {
            final data = doc.data();
            _dlog(
              'sample sheet id=${doc.id} schoolYear=${data['schoolYear']} '
              'anioEscolar=${data['anioEscolar']} month=${data['month']} '
              'monthKey=${data['monthKey']} gradeLabel=${data['gradeLabel']}',
            );
          }
        } catch (e) {
          _dlog('sample query error: $e');
        }

        _dlog('no sheets found for params schoolYear=$schoolYearLabel month=$_month year=$_year grade="$gradeLabel"');

        _subjects.clear();
        _aggregateDays();
        await _loadHistory(asistenciaCol, gradeLabel);

        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = null;
        });
        return;
      }

      // 3) Leer row del alumno por cada sheet (asignatura)
      for (final sheet in effectiveSheets) {
        final meta = sheet.data() ?? <String, dynamic>{};

        final subjectName = (meta['subject'] ?? meta['asignatura'] ?? meta['materia'] ?? sheet.id)
            .toString()
            .trim();
        _dlog(
          'sheet hit id=${sheet.id} subject="$subjectName" '
          'schoolYear=${meta['schoolYear']} anioEscolar=${meta['anioEscolar']} '
          'month=${meta['month']} monthKey=${meta['monthKey']} gradeLabel=${meta['gradeLabel']}',
        );

        final rowSnap = await sheet.reference.collection('rows').doc(_studentId).get();
        final row = rowSnap.data() ?? <String, dynamic>{};
        _dlog('row check sheet=${sheet.id} studentId=$_studentId exists=${rowSnap.exists} keys=${row.keys.take(8).toList()}');

        final marks = <String, String>{}; // dateKey -> P/A
        int p = 0, a = 0;

        row.forEach((k, v) {
          if (!k.startsWith('m_')) return;
          final dk = k.substring(2);
          final vv = (v ?? '').toString().trim().toUpperCase();
          if (vv == 'P' || vv == 'A') {
            marks[dk] = vv;
            if (vv == 'P') p++;
            if (vv == 'A') a++;
          }
        });

        _subjects[sheet.id] = _SubjectSheet(
          sheetId: sheet.id,
          subject: subjectName,
          marks: marks,
          present: p,
          absent: a,
        );
        _dlog('row parsed sheet=${sheet.id} subject="$subjectName" present=$p absent=$a marks=${marks.length}');
      }

      // 4) Agregar por día (para heatmap y racha)
      _aggregateDays();
      _dlog('aggregate done subjects=${_subjects.length} workDays=${_workDays.length} totalP=$_totalP totalA=$_totalA');

      // 5) Historial últimos meses (opcional, si existe índice)
      await _loadHistory(asistenciaCol, gradeLabel);
      _dlog('history loaded months=${_history.length}');

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      _dlog('reload error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Error cargando asistencia: $e';
      });
    }
  }

  void _aggregateDays() {
    _days.clear();

    // Inicializa todos los días laborables
    for (final d in _workDays) {
      final dk = _dateKey(d);
      _days[dk] = _DayAgg(date: d, p: 0, a: 0);
    }

    // Suma marcas por asignatura en cada día
    for (final subj in _subjects.values) {
      subj.marks.forEach((dk, v) {
        final day = _days[dk];
        if (day == null) return;
        if (v == 'P') day.p++;
        if (v == 'A') day.a++;
      });
    }
  }

  Future<void> _loadHistory(
    CollectionReference<Map<String, dynamic>> asistenciaCol,
    String gradeLabel,
    {bool embeddedRows = false}
  ) async {
    // Esto es “nice to have”. Si no hay índice, simplemente no lo mostramos.
    try {
 final q = await asistenciaCol
    .where('gradeLabel', isEqualTo: gradeLabel)
    .orderBy('monthKey', descending: true)
    .limit(60)
    .get();


      final out = <_MonthHistory>[];

      for (final sheet in q.docs) {
        final meta = sheet.data();
                if (!_sheetMatchesSchoolYear(meta, _schoolYearLabel())) {
          continue;
        }

        final mk = (meta['monthKey'] ?? '').toString().trim();
        if (mk.isEmpty) continue;

        Map<String, dynamic> row = <String, dynamic>{};

        try {
          row = embeddedRows
              ? meta
              : ((await sheet.reference.collection('rows').doc(_studentId).get()).data() ?? <String, dynamic>{});
        } catch (_) {
          continue;
        }

        int p = 0, a = 0;
        row.forEach((k, v) {
          if (!k.startsWith('m_')) return;
          final vv = (v ?? '').toString().trim().toUpperCase();
          if (vv == 'P') p++;
          if (vv == 'A') a++;
        });

        if (p == 0 && a == 0) {
          continue;
        }


        // Nota: hay múltiples sheets por mes (una por asignatura). Agrupamos por monthKey.
        final existing = out.indexWhere((x) => x.monthKey == mk);
        if (existing >= 0) {
          out[existing] = out[existing].copyWith(p: out[existing].p + p, a: out[existing].a + a);
        } else {
          out.add(_MonthHistory(monthKey: mk, p: p, a: a));
        }
      }

      out.sort((a, b) => b.monthKey.compareTo(a.monthKey));
      _history = out;
    } catch (_) {
      // Silencioso: no rompemos UI si falta índice
      _history = [];
    }
  }

  // =========================
  // Métricas
  // =========================
  int get _totalP => _subjects.values.fold<int>(0, (sum, s) => sum + s.present);
  int get _totalA => _subjects.values.fold<int>(0, (sum, s) => sum + s.absent);
  int get _totalMarked => _totalP + _totalA;

  double get _pctClasses {
    final t = _totalMarked;
    if (t <= 0) return 0;
    return (_totalP / t) * 100.0;
  }

  int get _daysWithAnyRecord {
    int c = 0;
    for (final d in _days.values) {
      if (d.total > 0) c++;
    }
    return c;
  }

  int get _daysPresentFull {
    // Presente “completo”: tuvo registros y no tuvo A ese día
    int c = 0;
    for (final d in _days.values) {
      if (d.total > 0 && d.a == 0 && d.p > 0) c++;
    }
    return c;
  }

  int get _daysMixed {
    int c = 0;
    for (final d in _days.values) {
      if (d.p > 0 && d.a > 0) c++;
    }
    return c;
  }

  int get _daysAbsentOnly {
    int c = 0;
    for (final d in _days.values) {
      if (d.total > 0 && d.p == 0 && d.a > 0) c++;
    }
    return c;
  }

  int get _daysNoRecord {
    int c = 0;
    for (final d in _days.values) {
      if (d.total == 0) c++;
    }
    return c;
  }

  int get _streak {
    // racha de días laborables seguidos (hasta hoy) con “presente completo”
    final today = DateTime.now();
    final t = DateTime(today.year, today.month, today.day);

    final ordered = _workDays.where((d) => !d.isAfter(t)).toList()
      ..sort((a, b) => b.compareTo(a)); // desc

    int streak = 0;
    for (final d in ordered) {
      final dk = _dateKey(d);
      final agg = _days[dk];
      if (agg == null) continue;

      final ok = agg.total > 0 && agg.a == 0 && agg.p > 0;
      if (ok) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  _WeekStats _currentWeekStats() {
    final now = DateTime.now();
    final start = _startOfWeek(now);
    final end = start.add(const Duration(days: 6));

    int p = 0, a = 0, daysRecorded = 0;

    for (final d in _workDays) {
      if (d.isBefore(start) || d.isAfter(end)) continue;
      final agg = _days[_dateKey(d)];
      if (agg == null) continue;

      p += agg.p;
      a += agg.a;
      if (agg.total > 0) daysRecorded++;
    }

    final marked = p + a;
    final pct = marked == 0 ? 0.0 : (p / marked) * 100.0;

    return _WeekStats(p: p, a: a, pct: pct, daysRecorded: daysRecorded);
  }

  String _motivationMessage() {
    final pct = _pctClasses;
    if (_totalMarked == 0) return 'Aún no hay registros este mes. ¡Cuando empiecen, aquí verás tu progreso!';
    if (pct >= 95) return 'Nivel excelente 🔥 Mantén ese ritmo, vas durísimo.';
    if (pct >= 90) return 'Vas muy bien 💪 Esta semana puedes cerrar en 100%.';
    if (pct >= 80) return 'Buen avance ✅ Si mejoras 1 día más por semana, subes rápido.';
    return 'Esta semana es tu oportunidad 🚀 Un día más presente cambia tu promedio.';
  }

  // =========================
  // UI helpers
  // =========================
  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: azul.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            blurRadius: 14,
            offset: const Offset(0, 6),
            color: Colors.black.withOpacity(0.06),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _pill(String text, {Color? bg, Color? fg, IconData? icon}) {
    final b = bg ?? Colors.black.withOpacity(0.06);
    final f = fg ?? Colors.black.withOpacity(0.75);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: b,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: f),
            const SizedBox(width: 6),
          ],
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: f)),
        ],
      ),
    );
  }

  Color _heatColor(_DayAgg d) {
    if (d.total == 0) return Colors.grey.withOpacity(0.20);
    final ratio = d.p / d.total; // 0..1
    if (ratio >= 0.95) return Colors.green.withOpacity(0.55);
    if (ratio >= 0.75) return Colors.green.withOpacity(0.35);
    if (ratio >= 0.50) return Colors.orange.withOpacity(0.45);
    return Colors.red.withOpacity(0.45);
  }

  String _fmtShortDate(DateTime d) => '${d.day}/${_two(d.month)}';

  // =========================
  // Build
  // =========================
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
              ),
              if (_diag.isNotEmpty) ...[
                const SizedBox(height: 18),
                Container(
                  constraints: const BoxConstraints(maxWidth: 920),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black.withOpacity(0.08)),
                  ),
                  child: SelectableText(
                    _diag.join('\n'),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: Colors.black.withOpacity(0.72),
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final week = _currentWeekStats();

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        children: [
          // Header / Selector mes-año
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Asistencia',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.black.withOpacity(0.85),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Actualizar',
                      onPressed: _reload,
                      icon: Icon(Icons.refresh_rounded, color: Colors.black.withOpacity(0.60)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _motivationMessage(),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black.withOpacity(0.65),
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 520;

                                  
final months = _history
    .map((h) => int.tryParse(h.monthKey.substring(4, 6)))
    .whereType<int>()
    .where((m) => m >= 1 && m <= 12)
    .toSet()
    .toList();

final safeMonths = months.isNotEmpty ? months : [_month];
final selectedMonth =
    safeMonths.contains(_month) ? _month : safeMonths.first;



            final monthDrop = DropdownButtonFormField<int>(
                      value: selectedMonth,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Mes',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: safeMonths.map((m) {
                        return DropdownMenuItem(value: m, child: Text(_monthName(m)));
                      }).toList(),
                      onChanged: (v) async {
                        if (v == null) return;
                        setState(() {
                          _month = v;
                          _year = _calendarYearForMonth(v);
                        });
                        await _reload();
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

                    if (narrow) {
                      return Column(
                        children: [
                          monthDrop,
                          const SizedBox(height: 10),
                          schoolYearField,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: monthDrop),
                        const SizedBox(width: 10),
                        Expanded(child: schoolYearField),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill('Grado: ${_gradeLabel.isEmpty ? '—' : _gradeLabel}', icon: Icons.school_rounded),
                    _pill('Mes: ${_monthName(_month)} $_year', icon: Icons.calendar_month_rounded),
                    _pill('Periodo: ${_schoolYearLabel()}', icon: Icons.date_range_rounded),
                    _pill('Racha: $_streak', icon: Icons.local_fire_department_rounded, bg: naranja.withOpacity(0.22)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Resumen mensual (clases)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resumen del mes',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black.withOpacity(0.82)),
                ),
                const SizedBox(height: 10),

                // % principal
                Row(
                  children: [
                    Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: azul.withOpacity(0.08),
                        border: Border.all(color: azul.withOpacity(0.18)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${_pctClasses.toStringAsFixed(0)}%',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Asistencia por clases registradas',
                            style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black.withOpacity(0.75)),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _totalMarked == 0
                                ? 'Sin registros aún.'
                                : 'Presentes: $_totalP • Ausentes: $_totalA • Registros: $_totalMarked',
                            style: TextStyle(color: Colors.black.withOpacity(0.62), fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: _totalMarked == 0 ? 0 : (_totalP / _totalMarked),
                              minHeight: 10,
                              backgroundColor: Colors.black.withOpacity(0.08),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _pctClasses >= 90 ? Colors.green : (_pctClasses >= 75 ? Colors.orange : Colors.red),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _pill('Días con registro: $_daysWithAnyRecord/${_workDays.length}',
                        icon: Icons.event_available_rounded),
                    _pill('Días 100%: $_daysPresentFull', icon: Icons.verified_rounded, bg: Colors.green.withOpacity(0.18)),
                    _pill('Mixtos: $_daysMixed', icon: Icons.remove_circle_outline_rounded, bg: Colors.orange.withOpacity(0.18)),
                    _pill('Ausente: $_daysAbsentOnly', icon: Icons.cancel_outlined, bg: Colors.red.withOpacity(0.16)),
                    _pill('Sin registro: $_daysNoRecord', icon: Icons.help_outline_rounded),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Semana actual
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Semana actual',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black.withOpacity(0.82)),
                ),
                const SizedBox(height: 10),
                Text(
                  week.p + week.a == 0
                      ? 'Aún no hay registros en esta semana.'
                      : 'Clases registradas: ${week.p + week.a} • Presentes: ${week.p} • Ausentes: ${week.a}',
                  style: TextStyle(color: Colors.black.withOpacity(0.62), fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (week.p + week.a) == 0 ? 0 : (week.p / (week.p + week.a)),
                    minHeight: 10,
                    backgroundColor: Colors.black.withOpacity(0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      week.pct >= 90 ? Colors.green : (week.pct >= 75 ? Colors.orange : Colors.red),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${week.pct.toStringAsFixed(0)}% esta semana',
                  style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black.withOpacity(0.75)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Heatmap mensual
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Calendario del mes',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black.withOpacity(0.82)),
                ),
                const SizedBox(height: 10),
                Text(
                  'Verde = excelente • Naranja = bien • Rojo = bajo • Gris = sin registro',
                  style: TextStyle(color: Colors.black.withOpacity(0.58), fontWeight: FontWeight.w700, fontSize: 12),
                ),
                const SizedBox(height: 10),

                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _workDays.map((d) {
                    final dk = _dateKey(d);
                    final agg = _days[dk] ?? _DayAgg(date: d, p: 0, a: 0);
                    final c = _heatColor(agg);

                    return Tooltip(
                      message: '${_fmtShortDate(d)}  •  P:${agg.p}  A:${agg.a}  (reg:${agg.total})',
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: Colors.black.withOpacity(0.06)),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${d.day}',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: agg.total == 0 ? Colors.black45 : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Materias
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Por asignatura',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black.withOpacity(0.82)),
                ),
                const SizedBox(height: 10),
                if (_subjects.isEmpty)
                  Text(
                    'No hay asignaturas registradas este mes.',
                    style: TextStyle(color: Colors.black.withOpacity(0.62), fontWeight: FontWeight.w700),
                  )
       else
  ...(_subjects.values.toList()
        ..sort((a, b) => a.subject.toLowerCase().compareTo(b.subject.toLowerCase())))
      .map((s) {
        final t = s.present + s.absent;
        final pct = t == 0 ? 0.0 : (s.present / t) * 100.0;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.subject,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    t == 0 ? '—' : '${pct.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: pct >= 90 ? Colors.green : (pct >= 75 ? Colors.orange : Colors.red),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: t == 0 ? 0 : (s.present / t),
                  minHeight: 8,
                  backgroundColor: Colors.black.withOpacity(0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    pct >= 90 ? Colors.green : (pct >= 75 ? Colors.orange : Colors.red),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t == 0
                    ? 'Sin registros en esta asignatura.'
                    : 'P:${s.present} • A:${s.absent} • Reg:${t}',
                style: TextStyle(
                  color: Colors.black.withOpacity(0.58),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      })
      .toList(),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Historial últimos meses (si disponible)
          if (_history.isNotEmpty)
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Historial (últimos meses)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black.withOpacity(0.82)),
                  ),
                  const SizedBox(height: 10),
                  ..._history.map((h) {
                    final y = int.tryParse(h.monthKey.substring(0, 4)) ?? 0;
                    final m = int.tryParse(h.monthKey.substring(4, 6)) ?? 1;
                    final t = h.p + h.a;
                    final pct = t == 0 ? 0.0 : (h.p / t) * 100.0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text(
                              '${_monthName(m)} $y',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: t == 0 ? 0 : (h.p / t),
                                minHeight: 8,
                                backgroundColor: Colors.black.withOpacity(0.08),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  pct >= 90 ? Colors.green : (pct >= 75 ? Colors.orange : Colors.red),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            t == 0 ? '—' : '${pct.toStringAsFixed(0)}%',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),

          const SizedBox(height: 20),

          // Nota final
          Text(
            'Nota: “Sin registro” significa que ese día/asignatura no fue marcada por el docente, no que faltaste.',
            style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w700, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// =========================
// Modelos internos
// =========================
class _SubjectSheet {
  final String sheetId;
  final String subject;
  final Map<String, String> marks; // dateKey -> P/A
  final int present;
  final int absent;

  const _SubjectSheet({
    required this.sheetId,
    required this.subject,
    required this.marks,
    required this.present,
    required this.absent,
  });
}

class _DayAgg {
  final DateTime date;
  int p;
  int a;

  _DayAgg({required this.date, required this.p, required this.a});

  int get total => p + a;
}

class _WeekStats {
  final int p;
  final int a;
  final double pct;
  final int daysRecorded;

  const _WeekStats({
    required this.p,
    required this.a,
    required this.pct,
    required this.daysRecorded,
  });
}

class _MonthHistory {
  final String monthKey; // yyyyMM
  final int p;
  final int a;

  const _MonthHistory({required this.monthKey, required this.p, required this.a});

  _MonthHistory copyWith({int? p, int? a}) => _MonthHistory(
        monthKey: monthKey,
        p: p ?? this.p,
        a: a ?? this.a,
      );
}
