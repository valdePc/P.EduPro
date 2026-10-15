// lib/docentes/screens/colocar_calificaciones.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:edupro/docentes/widgets/docente_app_bar.dart';
import 'package:flutter/services.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

/// ===============================================================
/// ColocarCalificacionesScreen (v2) — Docente
/// UI tipo libro (scroll horizontal) con 4 competencias y P/RP.
/// Guarda en calificaciones_v2 (no rompe legacy).
/// Incluye logs + probe para diagnosticar permission-denied.
/// - FIX: separar subjectIds (IDs) vs subjects (nombres)
/// - FIX: semáforo/logs fiables (incluye sample + lectura server en debug)
/// - OBJETIVOS: lee subjects/{subjectId}.periodObjectives.p1..p4 (listas de 4)
/// ===============================================================

class ColocarCalificacionesScreen extends StatefulWidget {
  final Escuela escuela;

  /// ✅ Opcional: misma lógica que Estudiantes (alumnos.tanda)
  /// Si viene vacío, NO filtra por tanda (no rompe nada).
  final String? tandaOverride;

  const ColocarCalificacionesScreen({
    super.key,
    required this.escuela,
    this.tandaOverride,
  });

  static const Color primaryColor = Color(0xFF0D47A1);
  static const Color accentColor = Color(0xFFFFA000);

  @override
  State<ColocarCalificacionesScreen> createState() => _ColocarCalificacionesScreenState();
}

/// ---------------- CONFIG (ajusta solo si tu Firestore usa otros nombres) ----------------
const String kRoot = 'schools';

// Catálogos
const String kGradesCollection = 'grados'; // schools/{schoolId}/grados/{gradeId}
const String kSubjectsCollection = 'subjects'; // schools/{schoolId}/subjects/{subjectId}
const String kStudentsCollection = 'alumnos'; // schools/{schoolId}/alumnos/{studentId}

// Docentes
const String kTeachersUidCollection = 'teachers_uid'; // schools/{schoolId}/teachers_uid/{authUid}
const String kTeachersCollection = 'teachers'; // schools/{schoolId}/teachers/{teacherDocId}
const String kMembersCollection = 'members'; // schools/{schoolId}/members/{uid}

// Calificaciones v2
const String kGradesV2Collection = 'calificaciones_v2'; // schools/{schoolId}/calificaciones_v2/{docId}

// Competencias texto (opcional legacy)
const String kCompetenciasV2Collection = 'competencias_v2'; // schools/{schoolId}/competencias_v2/{docId}
const String kCompetenciasBaseCollection = 'competencias_base'; // competencias_base/{subjectKey}

// Campos alumnos
const String kStudentGradeIdFieldA = 'gradoId';
const String kStudentGradeIdFieldB = 'gradeId';
const String kStudentEnabledField = 'enabled';
const String kStudentActiveField = 'active';

// ✅ Campos “tanda”
const String kStudentTandaField = 'tanda';
const String kStudentTandaLowerField = 'tandaLower';

// ✅ Tandas soportadas (según tu BD)
const List<String> kTandas = <String>['Mañana', 'Tarde', 'Noche'];
const List<String> kTandasLower = <String>['mañana', 'tarde', 'noche'];

// Campos teacher (grados / asignaturas)
const String kTeacherGradeIdsFieldA = 'gradeIds';
const String kTeacherGradeIdsFieldB = 'gradoIds';

// ✅ IDs reales de asignaturas (docIds def_*)
const String kTeacherSubjectIdsFieldA = 'subjectIds';
const String kTeacherSubjectIdsFieldB = 'subjectsIds';

// ✅ Nombres de asignaturas (solo UI)
const String kTeacherSubjectsNamesField = 'subjects';

/// ---------------- UI constants ----------------
const double _wNum = 44; // # fila
const double _wStudent = 240; // nombre alumno
const double _wCell = 46; // P/RP
const double _wCalc = 54; // PCE / FINAL
const int _competenciasCount = 4;
const int _periodos = 4;

class _Opt {
  final String id;
  final String name;
  const _Opt(this.id, this.name);
}

class _StudentRow {
  final String id;
  final String nombres;
  final String apellidos;
  final String matricula;
  const _StudentRow({
    required this.id,
    required this.nombres,
    required this.apellidos,
    required this.matricula,
  });

  String get display {
    final a = apellidos.trim();
    final n = nombres.trim();
    final m = matricula.trim();
    final base = '${a.isEmpty ? '' : a}, ${n.isEmpty ? '' : n}'.trim();
    return '${base.isEmpty ? id : base}${m.isEmpty ? '' : ' • #$m'}'.trim();
  }
}

class _ColocarCalificacionesScreenState extends State<ColocarCalificacionesScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // School
  late final String _schoolId;

  // Teacher binding
  bool _loadingTeacher = true;
  String? _teacherErr;
  String? _teacherDocId;
  String _teacherName = 'Docente';
  Set<String> _teacherGradeIds = <String>{};

  /// ✅ SOURCE OF TRUTH (permisos): docIds reales (def_*)
  Set<String> _teacherSubjectIds = <String>{};

  /// ✅ Solo UI: nombres (“CIENCIAS…”)
  Set<String> _teacherSubjectNames = <String>{};

  String? _subjectsWarn; // aviso si el docente no tiene asignaturas asignadas

  // UI state
  bool _loadingData = false;
  bool _saving = false;

  // Year selector: active cycle only for the selected grade
  late final int _yearNow;
  List<int> _yearsAllowed = const [];
  late int _yearSel;

  // Selections
  List<_Opt> _grades = [];
  List<_Opt> _subjects = [];
  String? _gradeIdSel;
  String? _subjectIdSel;

  // ✅ Tanda seleccionada (si la usan en alumnos)
  String _tandaSel = '';

  // ✅ Opciones de dropdown
  final List<String> _tandasAllowed = <String>['', ...kTandas];

  // Loaded
  List<_StudentRow> _students = [];

  // ====== Competencias / Objetivos ======
  // periodObjectives[p-1] = lista de 4 objetivos (c1..c4)
  final List<List<String>> _periodObjectives =
      List<List<String>>.generate(_periodos, (_) => List<String>.filled(_competenciasCount, ''));

  // Competencias text mostradas (4)
  final List<String> _compTexts = List<String>.filled(_competenciasCount, '');
  final List<String> _compCardLabels =
      List<String>.generate(_competenciasCount, (i) => 'Competencia ${i + 1}');

  // Values per student per cellKey
  final Map<String, Map<String, String>> _values = {}; // studentId -> {cellKey: "85"}
  final Map<String, TextEditingController> _controllers = {}; // "$sid|$key" -> controller
  final Set<String> _dirtyStudents = <String>{};

  // Scroll sync (header/body)
  final ScrollController _hHeader = ScrollController();
  final ScrollController _hBody = ScrollController();
  bool _syncing = false;

  // “Hoja” actual (para reset total al cambiar asignatura/año/grado/tanda)
  String? _sheetKey;

  // Competencias: para saber de dónde se cargaron (debug)
  String? _competenciasSourcePath;

  @override
  void initState() {
    super.initState();

    final raw = normalizeSchoolIdFromEscuela(widget.escuela);
    _schoolId = raw.trim().replaceAll('/', '_'); // Firestore docId no permite "/"

    // ✅ Normaliza override (si llega en minúscula o con espacios)
    _tandaSel = _normalizeTanda(widget.tandaOverride ?? '');

    _yearNow = DateTime.now().year;
    _yearsAllowed = <int>[_yearNow];
    _yearSel = _yearNow;

    _hHeader.addListener(() => _syncH(_hHeader, _hBody));
    _hBody.addListener(() => _syncH(_hBody, _hHeader));

    _bootstrap();
  }

  @override
  void dispose() {
    _hHeader.dispose();
    _hBody.dispose();
    _disposeAllControllers();
    super.dispose();
  }

  // ✅ Normaliza “tanda” para que siempre use: Mañana / Tarde / Noche / ''
  String _normalizeTanda(String raw) {
    final v = raw.toString().trim();
    if (v.isEmpty) return '';

    // 1) ya viene canonical
    if (kTandas.contains(v)) return v;

    // 2) viene lower
    final lower = v.toLowerCase();
    final idx = kTandasLower.indexOf(lower);
    if (idx >= 0) return kTandas[idx];

    // 3) fallback por si viene “manana” sin ñ (extra seguro)
    final simple = lower.replaceAll('ñ', 'n');
    if (simple == 'manana') return 'Mañana';

    // 4) si llega algo raro, lo dejamos tal cual (pero evitando crash en dropdown)
    return v;
  }

  String _tandaLabel(String v) => v.trim().isEmpty ? 'Todas' : v.trim();

  bool get _tandaLocked => (widget.tandaOverride ?? '').trim().isNotEmpty;

  void _disposeAllControllers() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
  }

  void _syncH(ScrollController from, ScrollController to) {
    if (_syncing) return;
    if (!from.hasClients || !to.hasClients) return;
    _syncing = true;
    try {
      final o = from.offset;
      if ((to.offset - o).abs() > 0.5) {
        to.jumpTo(o.clamp(to.position.minScrollExtent, to.position.maxScrollExtent));
      }
    } finally {
      _syncing = false;
    }
  }

  Color get _blue => ColocarCalificacionesScreen.primaryColor;
  Color get _orange => ColocarCalificacionesScreen.accentColor;

  void _log(String m) {}

  void _logCtx(String tag, {Map<String, Object?> extra = const {}}) {
    final base = <String, Object?>{
      'tag': tag,
      'uid': _auth.currentUser?.uid,
      'schoolId': _schoolId,
      'yearSel': _yearSel,
      'gradeSel': _gradeIdSel,
      'subjectSel': _subjectIdSel,
      'tandaSel': _tandaSel,
      'teacherDocId': _teacherDocId,
    };
    base.addAll(extra);
    _log(base.toString());
  }

  // ---------------- Firestore refs ----------------
  DocumentReference<Map<String, dynamic>> _teacherUidRef(String uid) =>
      _db.collection(kRoot).doc(_schoolId).collection(kTeachersUidCollection).doc(uid);

  DocumentReference<Map<String, dynamic>> _teacherRef(String teacherDocId) =>
      _db.collection(kRoot).doc(_schoolId).collection(kTeachersCollection).doc(teacherDocId);

  DocumentReference<Map<String, dynamic>> _memberRef(String uid) =>
      _db.collection(kRoot).doc(_schoolId).collection(kMembersCollection).doc(uid);

  CollectionReference<Map<String, dynamic>> _gradesCol() =>
      _db.collection(kRoot).doc(_schoolId).collection(kGradesCollection);

  CollectionReference<Map<String, dynamic>> _subjectsCol() =>
      _db.collection(kRoot).doc(_schoolId).collection(kSubjectsCollection);

  CollectionReference<Map<String, dynamic>> _studentsCol() =>
      _db.collection(kRoot).doc(_schoolId).collection(kStudentsCollection);

  CollectionReference<Map<String, dynamic>> _gradesV2Col() =>
      _db.collection(kRoot).doc(_schoolId).collection(kGradesV2Collection);

  DocumentReference<Map<String, dynamic>> _competenciasV2Ref({
    required int year,
    required String gradeId,
    required String subjectId,
  }) {
    final docId = '${year}_${gradeId}_$subjectId';
    return _db.collection(kRoot).doc(_schoolId).collection(kCompetenciasV2Collection).doc(docId);
  }

  DocumentReference<Map<String, dynamic>> _competenciasBaseRef(String subjectKey) =>
      _db.collection(kCompetenciasBaseCollection).doc(subjectKey);

  String _schoolYearLabel(int endYear) => '${endYear - 1}-$endYear';

  int? _schoolYearEndFromRaw(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    final match = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(raw);
    if (match != null) {
      return int.tryParse(match.group(2)!);
    }
    return int.tryParse(raw);
  }

  bool _matchesSchoolYearValue(dynamic value, int endYear) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return false;
    final label = _schoolYearLabel(endYear);
    return raw == label || raw == endYear.toString() || raw == (endYear - 1).toString();
  }

  bool _studentMatchesActiveYear(Map<String, dynamic> data) {
    final raw = data['schoolYear'] ?? data['anioEscolar'];
    if ((raw?.toString().trim() ?? '').isEmpty) return true;
    return _matchesSchoolYearValue(raw, _yearSel);
  }

  Future<void> _refreshVisibleYearsForGrade(String gradeId) async {
    final snap = await _studentsCol().get();
    int? latestEndYear;

    for (final d in snap.docs) {
      final m = d.data();
      final gradeIdA = (m[kStudentGradeIdFieldB] ?? '').toString().trim();
      final gradeIdB = (m[kStudentGradeIdFieldA] ?? '').toString().trim();
      if (gradeIdA != gradeId && gradeIdB != gradeId) continue;

      final enabled = (m[kStudentEnabledField] is bool) ? (m[kStudentEnabledField] as bool) : true;
      final active = (m[kStudentActiveField] is bool) ? (m[kStudentActiveField] as bool) : true;
      if (!enabled || !active) continue;

      final endYear = _schoolYearEndFromRaw(m['schoolYear'] ?? m['anioEscolar']);
      if (endYear == null) continue;
      if (latestEndYear == null || endYear > latestEndYear) {
        latestEndYear = endYear;
      }
    }

    final resolvedYear = latestEndYear ?? _yearNow;
    if (!mounted) return;
    setState(() {
      _yearsAllowed = <int>[resolvedYear];
      _yearSel = resolvedYear;
    });
  }

  String _gradesV2DocId({
    required int year,
    required String subjectId,
    required String studentId,
  }) =>
      '${year}_${subjectId}_$studentId';

  // ---------------- Probe helpers (diagnóstico permission-denied) ----------------
  Future<T> _tryGet<T>(String label, Future<T> Function() fn) async {
    try {
      final res = await fn();
      _log('PROBE OK $label');
      return res;
    } on FirebaseException catch (e) {
      _log('PROBE DENIED $label code=${e.code} msg=${e.message}');
      rethrow;
    } catch (e) {
      _log('PROBE FAIL $label err=$e');
      rethrow;
    }
  }

  Future<void> _probeSafe<T>(String label, Future<T> Function() fn) async {
    try {
      await _tryGet(label, fn);
    } catch (e) {
      // El probe es diagnóstico, no debe romper el guardado.
      _log('PROBE IGNORE $label err=$e');
    }
  }

  Future<void> _probeWritePermissions({
    required String gradeId,
    required String subjectId,
    required String anyStudentId,
  }) async {
    _logCtx('PROBE_START', extra: {
      'gradeId': gradeId,
      'subjectId': subjectId,
      'anyStudentId': anyStudentId,
      'writesTo': _gradesV2Col().path,
    });

    final uid = _auth.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      _log('PROBE_ABORT no uid');
      return;
    }

    await _probeSafe('teachers_uid/{uid}', () => _teacherUidRef(uid).get());

    final tid = (_teacherDocId ?? '').trim();
    if (tid.isNotEmpty) {
      await _probeSafe('teachers/{teacherDocId}', () => _teacherRef(tid).get());
    } else {
      _log('PROBE_SKIP teachers doc (teacherDocId vacío)');
    }

    await _probeSafe('grados/{gradeId}', () => _gradesCol().doc(gradeId).get());
    await _probeSafe('subjects/{subjectId}', () => _subjectsCol().doc(subjectId).get());
    await _probeSafe('alumnos/{studentId}', () => _studentsCol().doc(anyStudentId).get());

    final gradesV2DocId = _gradesV2DocId(
      year: _yearSel,
      subjectId: subjectId,
      studentId: anyStudentId,
    );

    await _probeSafe('calificaciones_v2/{docId}', () => _gradesV2Col().doc(gradesV2DocId).get());

    _logCtx('PROBE_END', extra: {'gradesV2DocId': gradesV2DocId});
  }

  // ==============================
  // LOGS “tipo rules” (debug)
  // ==============================
  String _normToken(String v) => v.toString().replaceAll('\u00A0', ' ').trim();

  String _normId(String v) {
    final s = _normToken(v).replaceAll('"', '').replaceAll("'", '');
    return s;
  }

  String _normName(String v) {
    final s = _normToken(v);
    return s;
  }

  String _slugSubjectKey(String v) {
    final lower = _normToken(v).toLowerCase();
    if (lower.isEmpty) return '';
    return lower
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll('&', ' ')
        .replaceAll('/', ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
  }

  Set<String> _listToSetNorm(dynamic raw, {required String Function(String) norm}) {
    final out = <String>{};
    if (raw is List) {
      for (final e in raw) {
        final v = norm(e.toString());
        if (v.isNotEmpty) out.add(v);
      }
      return out;
    }
    if (raw is String) {
      final v = norm(raw);
      if (v.isNotEmpty) out.add(v);
      return out;
    }
    return out;
  }

  Future<void> _logRuleInputs(String stage, {String? gradeId, String? subjectId}) async {
    if (!kDebugMode) return;

    final uid = _auth.currentUser?.uid ?? '';
    final email = _auth.currentUser?.email ?? '';
    final gid = _normId(gradeId ?? _gradeIdSel ?? '');
    final sid = _normId(subjectId ?? _subjectIdSel ?? '');

    _logCtx('RULE_INPUTS_$stage', extra: {
      'email': email,
      'schoolId_used': _schoolId,
      'gradeId': gid,
      'subjectId': sid,
    });

    // Members
    try {
      if (uid.isNotEmpty) {
        final ref = _memberRef(uid);
        final snap = await ref.get(const GetOptions(source: Source.server));
        final exists = snap.exists;
        final d = snap.data() ?? <String, dynamic>{};
        _logCtx('RULE_MEMBERS', extra: {
          'path': ref.path,
          'exists': exists,
          'role': (d['role'] ?? d['rol'] ?? d['enrol']),
          'enabled': d['enabled'],
          'keys': d.keys.toList(),
        });
      }
    } catch (e) {
      _logCtx('RULE_MEMBERS_ERR', extra: {'err': e.toString()});
    }

    // teachers_uid
    try {
      if (uid.isNotEmpty) {
        final ref = _teacherUidRef(uid);
        final snap = await ref.get(const GetOptions(source: Source.server));
        final d = snap.data() ?? <String, dynamic>{};
        _logCtx('RULE_TEACHERS_UID', extra: {
          'path': ref.path,
          'exists': snap.exists,
          'schoolId_in_doc': d['schoolId'],
          'keys': d.keys.toList(),
        });
      }
    } catch (e) {
      _logCtx('RULE_TEACHERS_UID_ERR', extra: {'err': e.toString()});
    }

    // teacher doc
    try {
      final tid = (_teacherDocId ?? '').trim();
      if (tid.isNotEmpty) {
        final ref = _teacherRef(tid);
        final snap = await ref.get(const GetOptions(source: Source.server));
        final d = snap.data() ?? <String, dynamic>{};

        final gradeIds = (d['gradeIds'] is List) ? List.from(d['gradeIds']) : null;
        final subjectIds = (d['subjectIds'] is List) ? List.from(d['subjectIds']) : null;

        _logCtx('RULE_TEACHER_DOC', extra: {
          'path': ref.path,
          'exists': snap.exists,
          'authUid': d['authUid'],
          'emailLower': d['emailLower'],
          'gradeIds': gradeIds,
          'subjectIds': subjectIds,
          'keys': d.keys.toList(),
        });
      }
    } catch (e) {
      _logCtx('RULE_TEACHER_DOC_ERR', extra: {'err': e.toString()});
    }

    // Semáforo
    _logCtx('RULE_SEMAPHORE', extra: {
      'gid': gid,
      'sid': sid,
      'teacherGradeIds_has_gid': _teacherGradeIds.contains(gid),
      'teacherSubjectIds_has_sid': _teacherSubjectIds.contains(sid),
      'teacherGradeIds_count': _teacherGradeIds.length,
      'teacherSubjectIds_count': _teacherSubjectIds.length,
      'teacherSubjectIds_sample': _teacherSubjectIds.take(10).toList(),
      'teacherSubjectNames_count': _teacherSubjectNames.length,
      'teacherSubjectNames_sample': _teacherSubjectNames.take(10).toList(),
    });
  }

  // ============================================================
  // OBJETIVOS desde SUBJECTS (periodObjectives)
  // Estructura real: periodObjectives.p1/p2/p3/p4 = List<String> (4 items)
  // ============================================================

  List<String> _extract4FromPeriodNode(dynamic node) {
    // Lista ["...","...","...","..."]
    if (node is List) {
      return List<String>.generate(
        _competenciasCount,
        (i) => i < node.length ? _normToken(node[i].toString()) : '',
      );
    }

    // Map {c1,c2,c3,c4} o {0,1,2,3}
    if (node is Map) {
      final m = node.cast<String, dynamic>();
      String pickAny(List<String> keys) {
        for (final k in keys) {
          final v = m[k];
          if (v != null) {
            final s = _normToken(v.toString());
            if (s.isNotEmpty) return s;
          }
        }
        return '';
      }

      return <String>[
        pickAny(['c1', 'comp1', '0']),
        pickAny(['c2', 'comp2', '1']),
        pickAny(['c3', 'comp3', '2']),
        pickAny(['c4', 'comp4', '3']),
      ];
    }

    // String único => lo pongo en la primera
    if (node is String) {
      final s = _normToken(node);
      return <String>[s, '', '', ''];
    }

    return List<String>.filled(_competenciasCount, '');
  }

  String? _extractSingleCompetenciaFromNode(dynamic node) {
    if (node is String) {
      final s = _normToken(node);
      return s.isEmpty ? null : s;
    }

    if (node is List) {
      final values = node.map((e) => _normToken(e.toString())).where((e) => e.isNotEmpty).toList();
      if (values.isEmpty) return null;
      if (values.length == 1) return values.first;
      return null;
    }

    if (node is Map) {
      final comps = _extract4FromPeriodNode(node).where((e) => e.trim().isNotEmpty).toList();
      if (comps.length == 1) return comps.first;
      return null;
    }

    return null;
  }

  List<String>? _extractDirectCompetenciasFromPeriods(Map<String, dynamic> source) {
    final out = <String>[];
    bool hasAny = false;

    for (int p = 1; p <= _periodos; p++) {
      final node = source['p$p'] ?? source['P$p'] ?? source['period$p'];
      final single = _extractSingleCompetenciaFromNode(node);
      out.add(single ?? '');
      if ((single ?? '').trim().isNotEmpty) {
        hasAny = true;
      }
    }

    return hasAny ? out : null;
  }

  List<String>? _extractDirectCompetenciasFromLoadedPeriods() {
    final out = <String>[];
    bool hasAny = false;

    for (int p = 0; p < _periodos; p++) {
      final values = _periodObjectives[p].map((e) => _normToken(e)).where((e) => e.isNotEmpty).toList();
      if (values.length == 1) {
        out.add(values.first);
        hasAny = true;
      } else {
        out.add('');
      }
    }

    return hasAny ? out : null;
  }

  void _setCompCardsFromCompetencias(List<String> values) {
    _compTexts.setAll(0, values.map((e) => e.trim()).toList());
    _compCardLabels.setAll(
      0,
      List<String>.generate(_competenciasCount, (i) => 'Competencia ${i + 1}'),
    );
  }

  void _setCompCardsFromPeriods(List<String> values) {
    _compTexts.setAll(0, values.map((e) => e.trim()).toList());
    _compCardLabels.setAll(
      0,
      List<String>.generate(_competenciasCount, (i) => 'Competencia ${i + 1}'),
    );
  }

  bool _isGenericCompetencias(List<String> values) {
    final cleaned = values.map((e) => _normToken(e)).toList();
    if (cleaned.every((e) => e.isEmpty)) return true;

    const generic = <String>[
      'Competencia 1',
      'Competencia 2',
      'Competencia 3',
      'Competencia 4',
    ];

    if (cleaned.length < _competenciasCount) return false;
    for (int i = 0; i < _competenciasCount; i++) {
      if (cleaned[i] != generic[i]) return false;
    }
    return true;
  }

  List<String> _subjectKeysFromId(String subjectId, Map<String, dynamic> data) {
    final out = <String>[];

    void addKey(String raw) {
      final key = _normId(raw);
      if (key.isNotEmpty && !out.contains(key)) out.add(key);
    }

    void addSlug(String raw) {
      final key = _slugSubjectKey(raw);
      if (key.isNotEmpty && !out.contains(key)) out.add(key);
    }

    addKey((data['subjectKey'] ?? '').toString());
    addKey(subjectId);

    if (subjectId.startsWith('def_')) {
      addKey(subjectId.substring(4));
    }

    addSlug((data['nombre'] ?? '').toString());
    addSlug((data['name'] ?? '').toString());
    addSlug((data['subjectName'] ?? '').toString());

    return out;
  }

  Future<bool> _tryLoadCompetenciasBase({
    required List<String> subjectKeys,
  }) async {
    if (subjectKeys.isEmpty) return false;

    try {
      for (final subjectKey in subjectKeys) {
        final ref = _competenciasBaseRef(subjectKey);
        final snap = await ref.get();
        if (!snap.exists) continue;

        final data = snap.data() ?? <String, dynamic>{};
        final po = data['periodObjectives'];

        if (po is Map) {
          final m = po.cast<String, dynamic>();
          final direct = _extractDirectCompetenciasFromPeriods(m);
          if (direct != null) {
            _setCompCardsFromPeriods(direct);
            _competenciasSourcePath = ref.path;
            return true;
          }

          for (int p = 1; p <= _periodos; p++) {
            final node = m['p$p'] ?? m['P$p'] ?? m['period$p'];
            _periodObjectives[p - 1] = _extract4FromPeriodNode(node);
          }
        } else {
          final direct = _extractDirectCompetenciasFromPeriods(data);
          if (direct != null) {
            _setCompCardsFromPeriods(direct);
            _competenciasSourcePath = ref.path;
            return true;
          }

          for (int p = 1; p <= _periodos; p++) {
            final node = data['p$p'] ?? data['P$p'] ?? data['period$p'];
            _periodObjectives[p - 1] = _extract4FromPeriodNode(node);
          }
        }

        final directFromPeriods = _extractDirectCompetenciasFromLoadedPeriods();
        if (directFromPeriods != null && directFromPeriods.where((e) => e.isNotEmpty).length >= 2) {
          _setCompCardsFromPeriods(directFromPeriods);
          _competenciasSourcePath = '${ref.path}.periodObjectives[p1..p4]';
          return true;
        }

        final comps = _periodObjectives.first;
        if (comps.every((x) => x.trim().isEmpty)) continue;

        _setCompCardsFromCompetencias(comps);
        _competenciasSourcePath = '${ref.path}.periodObjectives.p1';
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadCompetenciasText({
    required int year,
    required String gradeId,
    required String subjectId,
  }) async {
    _competenciasSourcePath = null;

    // Limpia
    for (int p = 0; p < _periodos; p++) {
      _periodObjectives[p] = List<String>.filled(_competenciasCount, '');
    }
    _setCompCardsFromCompetencias(List<String>.filled(_competenciasCount, ''));

    // 1) PRIORIDAD: subjects/{subjectId}.periodObjectives.p1..p4
    try {
      final sref = _subjectsCol().doc(subjectId);
      final snap = await sref.get();
      if (snap.exists) {
        final data = snap.data() ?? <String, dynamic>{};
        final subjectKeys = _subjectKeysFromId(subjectId, data);
        final po = data['periodObjectives'];

        if (po is Map) {
          final m = po.cast<String, dynamic>();
          final direct = _extractDirectCompetenciasFromPeriods(m);
          if (direct != null) {
            final directCount = direct.where((e) => e.trim().isNotEmpty).length;
            if (directCount >= _periodos) {
              _setCompCardsFromPeriods(direct);
              _competenciasSourcePath = '${sref.path}.periodObjectives';
              _logCtx('COMPETENCIAS_OK', extra: {
                'sourcePath': _competenciasSourcePath,
                'subjectDocId': subjectId,
                'mode': 'direct_period_map_complete',
                'keys': data.keys.toList(),
              });
              return;
            }

            final fromBase = await _tryLoadCompetenciasBase(
              subjectKeys: subjectKeys,
            );
            if (fromBase) {
              _logCtx('COMPETENCIAS_BASE_OK', extra: {
                'subjectKeys': subjectKeys,
                'sourcePath': _competenciasSourcePath,
                'mode': 'prefer_base_after_subject_direct_partial',
              });
              return;
            }

            _setCompCardsFromPeriods(direct);
            _competenciasSourcePath = '${sref.path}.periodObjectives';
            _logCtx('COMPETENCIAS_OK', extra: {
              'sourcePath': _competenciasSourcePath,
              'subjectDocId': subjectId,
              'mode': 'direct_period_map_partial',
              'keys': data.keys.toList(),
            });
            return;
          }

          for (int p = 1; p <= _periodos; p++) {
            final node = m['p$p'] ?? m['P$p'] ?? m['period$p'];
            _periodObjectives[p - 1] = _extract4FromPeriodNode(node);
          }

          final fromBase = await _tryLoadCompetenciasBase(
            subjectKeys: subjectKeys,
          );
          if (fromBase) {
            _logCtx('COMPETENCIAS_BASE_OK', extra: {
              'subjectKeys': subjectKeys,
              'sourcePath': _competenciasSourcePath,
              'mode': 'prefer_base_after_subject_periods',
            });
            return;
          }

          final directFromPeriods = _extractDirectCompetenciasFromLoadedPeriods();
          if (directFromPeriods != null && directFromPeriods.where((e) => e.isNotEmpty).length >= 2) {
            _setCompCardsFromPeriods(directFromPeriods);
            _competenciasSourcePath = '${sref.path}.periodObjectives[p1..p4]';

            _logCtx('COMPETENCIAS_OK', extra: {
              'sourcePath': _competenciasSourcePath,
              'subjectDocId': subjectId,
              'mode': 'direct_from_period_lists',
              'keys': data.keys.toList(),
            });
            return;
          }

          final comps = _periodObjectives.first;

          if (comps.any((x) => x.trim().isNotEmpty)) {
            if (_isGenericCompetencias(comps)) {
              final fromBase = await _tryLoadCompetenciasBase(
                subjectKeys: subjectKeys,
              );
              if (fromBase) {
                _logCtx('COMPETENCIAS_BASE_OK', extra: {
                  'subjectKeys': subjectKeys,
                  'sourcePath': _competenciasSourcePath,
                });
                return;
              }
            }

            _setCompCardsFromCompetencias(comps);
            _competenciasSourcePath = '${sref.path}.periodObjectives.p1';

            _logCtx('COMPETENCIAS_OK', extra: {
              'sourcePath': _competenciasSourcePath,
              'subjectDocId': subjectId,
              'mode': 'period_p1_fallback',
              'keys': data.keys.toList(),
            });
            return;
          }
        }

        final fromBase = await _tryLoadCompetenciasBase(
          subjectKeys: subjectKeys,
        );
        if (fromBase) {
          _logCtx('COMPETENCIAS_BASE_OK', extra: {
            'subjectKeys': subjectKeys,
            'sourcePath': _competenciasSourcePath,
          });
          return;
        }
      }
    } catch (e) {
      _logCtx('COMPETENCIAS_SUBJECT_ERR', extra: {
        'err': e.toString(),
        'subjectId': subjectId,
      });
    }

    // 2) Fallback opcional: competencias_v2/{year_grade_subject}
    try {
      final cref = _competenciasV2Ref(year: year, gradeId: gradeId, subjectId: subjectId);
      final csnap = await cref.get();
      if (csnap.exists) {
        final m = csnap.data() ?? <String, dynamic>{};
        final comps = <String>[
          _normToken((m['c1'] ?? m['comp1'] ?? '').toString()),
          _normToken((m['c2'] ?? m['comp2'] ?? '').toString()),
          _normToken((m['c3'] ?? m['comp3'] ?? '').toString()),
          _normToken((m['c4'] ?? m['comp4'] ?? '').toString()),
        ];

        if (comps.any((x) => x.isNotEmpty)) {
          _setCompCardsFromPeriods(comps);
          _competenciasSourcePath = cref.path;

          _logCtx('COMPETENCIAS_OK', extra: {
            'sourcePath': cref.path,
            'subjectId': subjectId,
            'keys': m.keys.toList(),
          });
          return;
        }
      }
    } catch (_) {}

    _logCtx('COMPETENCIAS_EMPTY', extra: {
      'subjectId': subjectId,
      'hint': 'Verifica subjects/{subjectId}.periodObjectives.p1..p4 (listas de 4).',
    });
  }

  // ---------------- Bootstrap ----------------
  Future<void> _bootstrap() async {
    await _bindTeacher();
    if (!mounted) return;

    await _loadGradeOptions();
    if (!mounted) return;

    await _loadSubjectOptions();
    if (!mounted) return;

    if (_grades.isNotEmpty) _gradeIdSel ??= _grades.first.id;
    if (_subjects.isNotEmpty) _subjectIdSel ??= _subjects.first.id;

    if (_gradeIdSel != null && _subjectIdSel != null) {
      await _reloadAll();
    }
  }

  String _pickName(Map<String, dynamic> m, {String fallback = 'Docente'}) {
    final v = (m['displayName'] ?? m['name'] ?? m['nombre'] ?? m['nombres'] ?? '').toString().trim();
    return v.isNotEmpty ? v : fallback;
  }

  Future<void> _bindTeacher() async {
    setState(() {
      _loadingTeacher = true;
      _teacherErr = null;
      _subjectsWarn = null;
      _teacherDocId = null;
      _teacherGradeIds = <String>{};
      _teacherSubjectIds = <String>{};
      _teacherSubjectNames = <String>{};
    });

    try {
      final u = _auth.currentUser;
      if (u == null) {
        setState(() => _teacherErr = 'No hay sesión activa.');
        return;
      }

      final uid = u.uid;
      _log('AUTH uid=$uid schoolId=$_schoolId');

      final linkSnap = await _teacherUidRef(uid).get();
      if (!linkSnap.exists) {
        setState(() {
          _teacherErr =
              'Este docente NO está vinculado en teachers_uid.\n'
              'Crea: schools/$_schoolId/teachers_uid/$uid { teacherDocId }';
        });
        return;
      }

      final link = linkSnap.data() ?? {};
      final tDocId = _normId((link['teacherDocId'] ?? '').toString());
      if (tDocId.isEmpty) {
        setState(() => _teacherErr = 'teachers_uid existe pero teacherDocId está vacío.');
        return;
      }

      _teacherDocId = tDocId;

      final tSnap = await _teacherRef(tDocId).get();
      final t = tSnap.data() ?? {};
      _teacherName = _pickName(t, fallback: widget.escuela.nombre ?? 'Docente');

      // ----------- Grados (IDs) -----------
      _teacherGradeIds = <String>{}
        ..addAll(_listToSetNorm(t[kTeacherGradeIdsFieldA], norm: _normId))
        ..addAll(_listToSetNorm(t[kTeacherGradeIdsFieldB], norm: _normId))
        // extras por compat
        ..addAll(_listToSetNorm(t['gradosIds'], norm: _normId))
        ..addAll(_listToSetNorm(t['gradesIds'], norm: _normId));

      // ----------- Asignaturas (IDs reales) -----------
      _teacherSubjectIds = <String>{}
        ..addAll(_listToSetNorm(t[kTeacherSubjectIdsFieldA], norm: _normId))
        ..addAll(_listToSetNorm(t[kTeacherSubjectIdsFieldB], norm: _normId))
        // extras por compat (IDS)
        ..addAll(_listToSetNorm(t['materiaIds'], norm: _normId))
        ..addAll(_listToSetNorm(t['materiasIds'], norm: _normId))
        ..addAll(_listToSetNorm(t['asignaturaIds'], norm: _normId))
        ..addAll(_listToSetNorm(t['asignaturasIds'], norm: _normId));

      // ----------- Asignaturas (NOMBRES UI) -----------
      _teacherSubjectNames = <String>{}
        ..addAll(_listToSetNorm(t[kTeacherSubjectsNamesField], norm: _normName))
        ..addAll(_listToSetNorm(t['materias'], norm: _normName))
        ..addAll(_listToSetNorm(t['asignaturas'], norm: _normName))
        ..addAll(_listToSetNorm(t['subjectsNames'], norm: _normName))
        ..addAll(_listToSetNorm(t['materiasNames'], norm: _normName))
        ..addAll(_listToSetNorm(t['asignaturasNames'], norm: _normName));

      _logCtx('BIND_TEACHER_OK', extra: {
        'teacherDocId': _teacherDocId,
        'gradeIds_count': _teacherGradeIds.length,
        'subjectIds_count': _teacherSubjectIds.length,
        'subjectIds_sample': _teacherSubjectIds.take(10).toList(),
        'subjectNames_count': _teacherSubjectNames.length,
        'subjectNames_sample': _teacherSubjectNames.take(10).toList(),
      });

      await _logRuleInputs('AFTER_BIND');
    } catch (e) {
      setState(() => _teacherErr = 'Error vinculando docente: $e');
    } finally {
      if (mounted) setState(() => _loadingTeacher = false);
    }
  }

  Future<void> _loadGradeOptions() async {
    if (_teacherGradeIds.isEmpty) {
      setState(() => _grades = []);
      return;
    }

    final out = <_Opt>[];
    for (final gid in _teacherGradeIds) {
      try {
        final s = await _gradesCol().doc(gid).get();
        if (!s.exists) {
          out.add(_Opt(gid, gid));
          continue;
        }
        final m = s.data() ?? {};
        final name = (m['name'] ?? m['grado'] ?? m['nombre'] ?? gid).toString().trim();
        out.add(_Opt(gid, name.isEmpty ? gid : name));
      } catch (_) {
        out.add(_Opt(gid, gid));
      }
    }

    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    setState(() => _grades = out);
  }

  /// ✅ SOLO asignaturas del docente
  /// - Prioridad: teacher.subjectIds (docIds)
  /// - Fallback UI: teacher.subjects (nombres) => intenta resolver a docId, pero advierte que para guardar necesita subjectIds.
  Future<void> _loadSubjectOptions() async {
    final out = <_Opt>[];
    final unresolved = <String>[];

    try {
      if (_teacherSubjectIds.isEmpty && _teacherSubjectNames.isEmpty) {
        if (!mounted) return;
        setState(() {
          _subjects = [];
          _subjectIdSel = null;
          _subjectsWarn =
              'Este docente no tiene asignaturas asignadas en Firestore.\n'
              'En teachers/{teacherDocId} agrega subjectIds con docIds (def_...).';
        });
        return;
      }

      // 1) IDs reales
      for (final raw in _teacherSubjectIds) {
        final opt = await _resolveSubjectOptFromAny(raw);
        if (opt != null) {
          out.add(opt);
        } else {
          unresolved.add(raw);
        }
      }

      // 2) Fallback por nombres (solo si NO hay IDs)
      if (_teacherSubjectIds.isEmpty && _teacherSubjectNames.isNotEmpty) {
        for (final rawName in _teacherSubjectNames) {
          final opt = await _resolveSubjectOptFromAny(rawName);
          if (opt != null) {
            out.add(opt);
          } else {
            unresolved.add(rawName);
          }
        }
      }
    } catch (e) {
      _log('subjects load error: $e');
    }

    // dedupe por id
    final byId = <String, _Opt>{};
    for (final o in out) {
      byId[o.id] = o;
    }
    final finalList = byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (!mounted) return;
    setState(() {
      _subjects = finalList;

      if (_teacherSubjectIds.isEmpty && _teacherSubjectNames.isNotEmpty) {
        _subjectsWarn =
            'Este docente tiene asignaturas por NOMBRE (teachers.subjects).\n'
            'Para poder GUARDAR calificaciones, debe existir teachers.subjectIds con docIds (def_...).';
      } else {
        _subjectsWarn = unresolved.isEmpty
            ? null
            : 'Algunas asignaturas del docente no se pudieron resolver:\n'
                '${unresolved.take(6).join(', ')}${unresolved.length > 6 ? '…' : ''}\n'
                'Solución: usa docIds (def_...) en teachers.subjectIds.';
      }

      if (_subjectIdSel == null || !_subjects.any((x) => x.id == _subjectIdSel)) {
        _subjectIdSel = _subjects.isEmpty ? null : _subjects.first.id;
      }
    });
  }

  Future<_Opt?> _resolveSubjectOptFromAny(String raw) async {
    final v = raw.trim();
    if (v.isEmpty) return null;

    // 1) Intento directo: raw es docId (ej: def_ciencias_naturaleza)
    try {
      final doc = await _subjectsCol().doc(v).get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        final name = (data['name'] ?? data['asignatura'] ?? data['materia'] ?? doc.id).toString().trim();
        return _Opt(doc.id, name.isEmpty ? doc.id : name);
      }
    } catch (_) {}

    // 2) Intento por nameLower
    final lower = v.toLowerCase();
    try {
      final q1 = await _subjectsCol().where('nameLower', isEqualTo: lower).limit(1).get();
      if (q1.docs.isNotEmpty) {
        final d = q1.docs.first;
        final data = d.data();
        final name = (data['name'] ?? data['asignatura'] ?? data['materia'] ?? d.id).toString().trim();
        return _Opt(d.id, name.isEmpty ? d.id : name);
      }
    } catch (_) {}

    // 3) Intento por name exacto
    try {
      final q2 = await _subjectsCol().where('name', isEqualTo: v).limit(1).get();
      if (q2.docs.isNotEmpty) {
        final d = q2.docs.first;
        final data = d.data();
        final name = (data['name'] ?? data['asignatura'] ?? data['materia'] ?? d.id).toString().trim();
        return _Opt(d.id, name.isEmpty ? d.id : name);
      }
    } catch (_) {}

    return null;
  }

  String _gradeNameById(String id) {
    for (final g in _grades) {
      if (g.id == id) return g.name;
    }
    return id;
  }

  String _subjectNameById(String id) {
    for (final s in _subjects) {
      if (s.id == id) return s.name;
    }
    return id;
  }

  Future<bool> _confirmDiscardChangesIfNeeded() async {
    if (_dirtyStudents.isEmpty) return true;
    if (!mounted) return false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Cambios sin guardar'),
        content: const Text('Tienes cambios sin guardar. Si cambias el filtro se perderán. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continuar')),
        ],
      ),
    );

    return ok == true;
  }

  Future<void> _reloadAll() async {
    final gradeId = (_gradeIdSel ?? '').trim();
    final subjectId = (_subjectIdSel ?? '').trim();
    if (gradeId.isEmpty || subjectId.isEmpty) return;

    final tKey = _tandaSel.isEmpty ? 'ALL' : _tandaSel;
    final newKey = '${_yearSel}_$gradeId\_$subjectId\_$tKey';
    final keyChanged = (_sheetKey != newKey);
    _sheetKey = newKey;

    setState(() {
      _loadingData = true;
      _students = [];

      // ✅ Reset total SOLO si cambió la “hoja” (asignatura/año/grado/tanda)
      if (keyChanged) {
        _hardResetSheetState();
      } else {
        _dirtyStudents.clear();
      }
    });

    try {
      await _refreshVisibleYearsForGrade(gradeId);
      await _loadCompetenciasText(year: _yearSel, gradeId: gradeId, subjectId: subjectId);
      await _loadStudentsForGrade(gradeId);
      await _loadExistingGrades(year: _yearSel, gradeId: gradeId, subjectId: subjectId);

      _logCtx('RELOAD_OK', extra: {
        'sheetKey': _sheetKey,
        'keyChanged': keyChanged,
        'competenciasSource': _competenciasSourcePath,
      });
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  void _hardResetSheetState() {
    _values.clear();
    _dirtyStudents.clear();

    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
  }

  Future<void> _loadStudentsForGrade(String gradeId) async {
    final out = <_StudentRow>[];

    Future<void> readByField(String field) async {
      Query<Map<String, dynamic>> q1 = _studentsCol().where(field, isEqualTo: gradeId);

      if (_tandaSel.isNotEmpty) {
        q1 = q1.where(kStudentTandaField, isEqualTo: _tandaSel);
      }

      final snap1 = await q1.get();
      final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[...snap1.docs];

      if (_tandaSel.isNotEmpty) {
        try {
          Query<Map<String, dynamic>> q2 = _studentsCol().where(field, isEqualTo: gradeId);
          q2 = q2.where(kStudentTandaLowerField, isEqualTo: _tandaSel.toLowerCase());
          final snap2 = await q2.get();

          final existingIds = docs.map((d) => d.id).toSet();
          for (final d in snap2.docs) {
            if (!existingIds.contains(d.id)) {
              docs.add(d);
            }
          }
        } catch (_) {}
      }

      for (final d in docs) {
        final m = d.data();

        final enabled = (m[kStudentEnabledField] is bool) ? (m[kStudentEnabledField] as bool) : true;
        final active = (m[kStudentActiveField] is bool) ? (m[kStudentActiveField] as bool) : true;
        if (!enabled || !active) continue;
        if (!_studentMatchesActiveYear(m)) continue;

        final nombres = (m['nombres'] ?? '').toString().trim();
        final apellidos = (m['apellidos'] ?? '').toString().trim();
        final matricula = (m['matricula'] ?? m['numero'] ?? '').toString().trim();

        out.add(_StudentRow(
          id: d.id,
          nombres: nombres,
          apellidos: apellidos,
          matricula: matricula,
        ));
      }
    }

    try {
      await readByField(kStudentGradeIdFieldB); // gradeId
      if (out.isEmpty) await readByField(kStudentGradeIdFieldA); // gradoId
    } catch (e) {
      _log('students load error: $e');
    }

    final uniq = <String, _StudentRow>{};
    for (final s in out) {
      uniq[s.id] = s;
    }

    final list = uniq.values.toList()
      ..sort((a, b) {
        final aa = '${a.apellidos} ${a.nombres}'.toLowerCase();
        final bb = '${b.apellidos} ${b.nombres}'.toLowerCase();
        return aa.compareTo(bb);
      });

    if (!mounted) return;
    setState(() => _students = list);
  }

  Future<void> _loadExistingGrades({
    required int year,
    required String gradeId,
    required String subjectId,
  }) async {
    if (_students.isEmpty) return;

    try {
      final snap = await _gradesV2Col()
          .where('gradeId', isEqualTo: gradeId)
          .where('subjectId', isEqualTo: subjectId)
          .get();

      final byStudent = <String, Map<String, dynamic>>{};
      for (final d in snap.docs) {
        final m = d.data();
        final sid = (m['studentId'] ?? '').toString().trim();
        if (sid.isEmpty || !_matchesSchoolYearValue(m['year'], year)) continue;
        byStudent[sid] = m;
      }

      for (final s in _students) {
        final doc = byStudent[s.id];
        if (doc == null) continue;

        final scores = (doc['scores'] is Map)
            ? (doc['scores'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};

        for (int c = 1; c <= _competenciasCount; c++) {
          final cm = (scores['c$c'] is Map) ? (scores['c$c'] as Map).cast<String, dynamic>() : <String, dynamic>{};

          for (int p = 1; p <= _periodos; p++) {
            final pKey = _cellKey(c, p, false);
            final rpKey = _cellKey(c, p, true);

            final pv = cm['p$p'];
            final rpv = cm['rp$p'];

            if (pv != null) _setLocalValue(s.id, pKey, pv.toString(), markDirty: false);
            if (rpv != null) _setLocalValue(s.id, rpKey, rpv.toString(), markDirty: false);
          }
        }
      }
    } on FirebaseException catch (e) {
      _log('gradesV2 load error: ${e.message} (${e.code})');

      if (e.code == 'permission-denied' && _students.isNotEmpty) {
        try {
          await _probeWritePermissions(
            gradeId: gradeId,
            subjectId: subjectId,
            anyStudentId: _students.first.id,
          );
        } catch (probeErr) {
          _log('PROBE_SUPPRESSED (loadExistingGrades) err=$probeErr');
        }
      }
    } catch (e) {
      _log('gradesV2 load error: $e');
    }
  }

  // ---------------- Cell keys / parsing ----------------
  String _cellKey(int comp, int periodo, bool rp) => 'c${comp}_${rp ? 'rp' : 'p'}$periodo';

  String _getValue(String studentId, String key) => (_values[studentId] ?? const {})[key]?.toString() ?? '';

  int? _parseScore(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final v = int.tryParse(s);
    if (v == null) return null;
    if (v < 0) return 0;
    if (v > 100) return 100;
    return v;
  }

  bool _rpEnabled(String studentId, int comp, int periodo) {
    final p = _parseScore(_getValue(studentId, _cellKey(comp, periodo, false)));
    if (p == null) return false;
    return p < 70;
  }

  int? _effectiveScore(String studentId, int comp, int periodo) {
    final p = _parseScore(_getValue(studentId, _cellKey(comp, periodo, false)));
    if (p == null) return null;

    if (p < 70) {
      final rp = _parseScore(_getValue(studentId, _cellKey(comp, periodo, true)));
      return rp ?? p;
    }
    return p;
  }

  double? _avgCompetencia(String studentId, int periodo) {
    final vals = <int>[];
    for (int comp = 1; comp <= _competenciasCount; comp++) {
      final v = _effectiveScore(studentId, comp, periodo);
      if (v == null) return null; // estricto
      vals.add(v);
    }
    final sum = vals.fold<int>(0, (a, b) => a + b);
    return sum / vals.length; // 4
  }

  double? _avgFinal(String studentId) {
    final vals = <double>[];
    for (int p = 1; p <= _periodos; p++) {
      final pc = _avgCompetencia(studentId, p);
      if (pc == null) return null; // estricto
      vals.add(pc);
    }
    final sum = vals.fold<double>(0, (a, b) => a + b);
    return sum / vals.length; // 4
  }

  String _fmtAvg(double? v) => (v == null) ? '' : v.toStringAsFixed(1);

  void _setLocalValue(String studentId, String key, String value, {required bool markDirty}) {
    final v = value.trim();
    _values.putIfAbsent(studentId, () => <String, String>{})[key] = v;
    if (markDirty) _dirtyStudents.add(studentId);
  }

  TextEditingController _ctrlFor(String studentId, String key) {
    final mapKey = '$studentId|$key';
    final existing = _controllers[mapKey];
    if (existing != null) return existing;

    final c = TextEditingController(text: _getValue(studentId, key));
    _controllers[mapKey] = c;
    return c;
  }

  bool _teacherCanSaveForSelection({
    required String gradeId,
    required String subjectId,
  }) {
    final gid = _normId(gradeId);
    final sid = _normId(subjectId);
    if (gid.isEmpty || sid.isEmpty) return false;
    if ((_teacherDocId ?? '').trim().isEmpty) return false;
    return _teacherGradeIds.contains(gid) && _teacherSubjectIds.contains(sid);
  }

  // ---------------- Save ----------------
  Future<void> _saveAll() async {
    if (_saving) return;

    final gradeId = (_gradeIdSel ?? '').trim();
    final subjectId = (_subjectIdSel ?? '').trim();

    if (gradeId.isEmpty || subjectId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona grado y asignatura.')),
      );
      return;
    }

    if (_dirtyStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay cambios para guardar.')),
      );
      return;
    }

    final uid = _auth.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesión inválida.')),
      );
      return;
    }

    if (!_teacherCanSaveForSelection(gradeId: gradeId, subjectId: subjectId)) {
      _logCtx('SAVE_BLOCKED_SCOPE', extra: {
        'gradeId': gradeId,
        'subjectId': subjectId,
        'teacherDocId': _teacherDocId,
        'teacherHasGrade': _teacherGradeIds.contains(_normId(gradeId)),
        'teacherHasSubject': _teacherSubjectIds.contains(_normId(subjectId)),
      });

      if (kDebugMode) {
        await _logRuleInputs('SAVE_BLOCKED_SCOPE', gradeId: gradeId, subjectId: subjectId);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No autorizado para este grado/asignatura. '
            'Pide a administración revisar teachers_uid y teachers.gradeIds/subjectIds (docIds reales).',
          ),
        ),
      );
      return;
    }

    final dirtyCount = _dirtyStudents.length;

    _logCtx('SAVE_PRECHECK', extra: {
      'studentsLoaded': _students.length,
      'dirtyCount': dirtyCount,
      'writesTo': _gradesV2Col().path,
    });

    setState(() => _saving = true);

    try {
      if (kDebugMode) {
        await _logRuleInputs('BEFORE_SAVE', gradeId: gradeId, subjectId: subjectId);
      }

      _logCtx('SAVE_START', extra: {
        'gradeId': gradeId,
        'subjectId': subjectId,
        'dirtyCount': dirtyCount,
        'writesTo': _gradesV2Col().path,
      });

      final batch = _db.batch();
      final gradeName = _gradeNameById(gradeId);
      final subjectName = _subjectNameById(subjectId);

      final dirtyList = _dirtyStudents.toList(); // congelar lista
      for (int idx = 0; idx < dirtyList.length; idx++) {
        final sid = dirtyList[idx];
        final docId = _gradesV2DocId(year: _yearSel, subjectId: subjectId, studentId: sid);
        final ref = _gradesV2Col().doc(docId);

        final scores = <String, dynamic>{};
        for (int c = 1; c <= _competenciasCount; c++) {
          final cm = <String, dynamic>{};
          for (int p = 1; p <= _periodos; p++) {
            final pv = _parseScore(_getValue(sid, _cellKey(c, p, false)));
            final rpv = _parseScore(_getValue(sid, _cellKey(c, p, true)));
            cm['p$p'] = pv;
            cm['rp$p'] = rpv;
          }
          scores['c$c'] = cm;
        }

        final computed = <String, dynamic>{
          'c1avg': _avgCompetencia(sid, 1),
          'c2avg': _avgCompetencia(sid, 2),
          'c3avg': _avgCompetencia(sid, 3),
          'c4avg': _avgCompetencia(sid, 4),
          'final': _avgFinal(sid),
        };

        final payload = <String, dynamic>{
          'year': _yearSel,
          'yearEnd': _yearSel,
          'yearStart': _yearSel - 1,
          'schoolYear': _schoolYearLabel(_yearSel),
          'anioEscolar': _schoolYearLabel(_yearSel),
          'schoolId': _schoolId,
          'gradeId': gradeId,
          'gradeName': gradeName,
          'subjectId': subjectId,
          'subjectName': subjectName,
          'studentId': sid,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedByUid': uid,
          'updatedByRole': 'teacher',
          'scores': scores,
          'computed': computed,
        };

        if (idx < 3) {
          _logCtx('WRITE_DOC', extra: {
            'docId': docId,
            'docPath': ref.path,
            'studentId': sid,
            'payloadKeys': payload.keys.toList(),
          });
        }

        if (kDebugMode && idx < 3) {
  _logCtx('WRITE_DOC_VALUES', extra: {
    'docPath': ref.path,
    'docId': docId,
    'payload_schoolId': payload['schoolId'],
    'payload_updatedByUid': payload['updatedByUid'],
    'payload_gradeId': payload['gradeId'],
    'payload_subjectId': payload['subjectId'],
    'auth_uid_now': uid,
    'teacherDocId_state': _teacherDocId,
    'tandaSel': _tandaSel,
  });
}

        batch.set(ref, payload, SetOptions(merge: true));
      }

      await batch.commit();

      if (!mounted) return;
      setState(() => _dirtyStudents.clear());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Guardado: $dirtyCount alumnos.')),
      );

      _logCtx('SAVE_OK', extra: {'dirtyCount': dirtyCount});
    } on FirebaseException catch (e) {
      _logCtx('SAVE_FIREBASE_EX', extra: {'code': e.code, 'msg': e.message});

      if (e.code == 'permission-denied') {
        final anySid =
            _dirtyStudents.isNotEmpty ? _dirtyStudents.first : (_students.isNotEmpty ? _students.first.id : '');

        if (anySid.isNotEmpty) {
          try {
            await _probeWritePermissions(
              gradeId: gradeId,
              subjectId: subjectId,
              anyStudentId: anySid,
            );
          } catch (probeErr) {
            _log('PROBE_SUPPRESSED err=$probeErr');
          }
        } else {
          _log('PROBE_SKIP no studentId available');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'permission-denied'
                ? 'No tienes permisos para guardar calificaciones (permission-denied).'
                : 'Firestore ${e.code}: ${e.message ?? ''}',
          ),
        ),
      );
    } catch (e) {
      _logCtx('SAVE_ERR', extra: {'err': e.toString()});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final schoolName = (widget.escuela.nombre ?? 'Escuela').toString().trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: buildDocenteBackAppBar(
        context,
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: (_loadingTeacher || _loadingData || _saving) ? null : _reloadAll,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ElevatedButton.icon(
              onPressed: (_loadingTeacher || _loadingData || _saving) ? null : _saveAll,
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_saving ? 'Guardando…' : 'Guardar', style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _buildTopFiltersCard(),
          const SizedBox(height: 12),
          _buildCompetenciasCard(),
          const SizedBox(height: 12),
          _buildTableCard(),
        ],
      ),
    );
  }

  Widget _buildTopFiltersCard() {
    final gradeEnabled = !_loadingTeacher && _grades.isNotEmpty;
    final subjectEnabled = !_loadingTeacher && _subjects.isNotEmpty;

    final tandaValueSafe = _tandasAllowed.contains(_tandaSel) ? _tandaSel : '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: _orange.withOpacity(0.15),
                child: Icon(Icons.fact_check, color: _orange),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Filtros',
                  style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey.shade900),
                ),
              ),
              _pill(
                icon: Icons.person,
                text: _teacherName,
                bg: const Color(0xFFEFF3FF),
                fg: _blue,
                maxWidth: 210,
              ),
            ],
          ),
          if (_teacherErr != null) ...[
            const SizedBox(height: 8),
            Text(_teacherErr!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w800)),
          ],
          if (_subjectsWarn != null) ...[
            const SizedBox(height: 8),
            Text(_subjectsWarn!, style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w800)),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 1040;
              final mid = c.maxWidth >= 860 && c.maxWidth < 1040;

              final yearDd = DropdownButtonFormField<int>(
                value: _yearSel,
                decoration: const InputDecoration(
                  labelText: 'Año',
                  border: OutlineInputBorder(),
                ),
                items: _yearsAllowed
                    .map(
                      (y) => DropdownMenuItem<int>(
                        value: y,
                        child: Text(_schoolYearLabel(y)),
                      ),
                    )
                    .toList(),
                onChanged: (_loadingData || _saving)
                    ? null
                    : (v) async {
                        if (v == null) return;
                        final ok = await _confirmDiscardChangesIfNeeded();
                        if (!ok) return;

                        setState(() => _yearSel = v);
                        await _reloadAll();
                      },
              );

              final gradeDd = DropdownButtonFormField<String>(
                value: _gradeIdSel,
                decoration: const InputDecoration(
                  labelText: 'Grado',
                  border: OutlineInputBorder(),
                ),
                items: _grades.map((g) => DropdownMenuItem<String>(value: g.id, child: Text(g.name))).toList(),
                onChanged: (!gradeEnabled || _loadingData || _saving)
                    ? null
                    : (v) async {
                        if (v == null) return;
                        final ok = await _confirmDiscardChangesIfNeeded();
                        if (!ok) return;

                        setState(() => _gradeIdSel = v);
                        await _reloadAll();
                      },
              );

              final subjectDd = DropdownButtonFormField<String>(
                value: _subjectIdSel,
                decoration: const InputDecoration(
                  labelText: 'Asignatura',
                  border: OutlineInputBorder(),
                ),
                items: _subjects.map((s) => DropdownMenuItem<String>(value: s.id, child: Text(s.name))).toList(),
                onChanged: (!subjectEnabled || _loadingData || _saving)
                    ? null
                    : (v) async {
                        if (v == null) return;
                        final ok = await _confirmDiscardChangesIfNeeded();
                        if (!ok) return;

                        setState(() => _subjectIdSel = v);
                        await _reloadAll();
                      },
              );

              final tandaDd = DropdownButtonFormField<String>(
                value: tandaValueSafe,
                decoration: const InputDecoration(
                  labelText: 'Tanda',
                  border: OutlineInputBorder(),
                ),
                items: _tandasAllowed
                    .map(
                      (t) => DropdownMenuItem<String>(
                        value: t,
                        child: Text(_tandaLabel(t)),
                      ),
                    )
                    .toList(),
                onChanged: (_loadingData || _saving || _tandaLocked)
                    ? null
                    : (v) async {
                        if (v == null) return;
                        final ok = await _confirmDiscardChangesIfNeeded();
                        if (!ok) return;

                        final nv = _normalizeTanda(v);

                        setState(() => _tandaSel = nv);
                        await _reloadAll();
                      },
              );

              if (!wide && !mid) {
                return Column(
                  children: [
                    yearDd,
                    const SizedBox(height: 10),
                    gradeDd,
                    const SizedBox(height: 10),
                    subjectDd,
                    const SizedBox(height: 10),
                    tandaDd,
                    if (_tandaLocked) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Tanda bloqueada por tandaOverride.',
                        style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ],
                  ],
                );
              }

              if (mid) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: yearDd),
                        const SizedBox(width: 10),
                        Expanded(child: gradeDd),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: subjectDd),
                        const SizedBox(width: 10),
                        Expanded(child: tandaDd),
                      ],
                    ),
                    if (_tandaLocked) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Tanda bloqueada por tandaOverride.',
                          style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                );
              }

              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: yearDd),
                      const SizedBox(width: 10),
                      Expanded(child: gradeDd),
                      const SizedBox(width: 10),
                      Expanded(child: subjectDd),
                      const SizedBox(width: 10),
                      Expanded(child: tandaDd),
                    ],
                  ),
                  if (_tandaLocked) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Tanda bloqueada por tandaOverride.',
                        style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          if (_loadingTeacher || _loadingData) ...[
            const SizedBox(height: 12),
            const Row(
              children: [
                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Cargando…', style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompetenciasCard() {
    final gradeId = (_gradeIdSel ?? '').trim();
    final subjectId = (_subjectIdSel ?? '').trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Competencias Educativas',
              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey.shade900)),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 900;
              final cols = wide ? 2 : 1;

              final cards = <Widget>[];
              for (int i = 0; i < _competenciasCount; i++) {
                final title = _compCardLabels[i];
                final txt = _compTexts[i].trim();

                cards.add(
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0x11000000)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey.shade900)),
                        const SizedBox(height: 8),
                        Text(
                          txt.isEmpty ? '— (sin objetivo) —' : txt,
                          style: TextStyle(color: Colors.grey.shade800, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (cols == 1) {
                return Column(
                  children: [
                    for (int i = 0; i < cards.length; i++) ...[
                      cards[i],
                      if (i != cards.length - 1) const SizedBox(height: 10),
                    ]
                  ],
                );
              }

              return Column(
                children: [
                  Row(children: [Expanded(child: cards[0]), const SizedBox(width: 10), Expanded(child: cards[1])]),
                  const SizedBox(height: 10),
                  Row(children: [Expanded(child: cards[2]), const SizedBox(width: 10), Expanded(child: cards[3])]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTableCard() {
    final gradeId = (_gradeIdSel ?? '').trim();
    final subjectId = (_subjectIdSel ?? '').trim();
    final canShow = !_loadingTeacher && !_loadingData && gradeId.isNotEmpty && subjectId.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Tabla de calificaciones', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey.shade900)),
              const SizedBox(width: 10),
              if (_dirtyStudents.isNotEmpty)
                _pill(
                  icon: Icons.edit,
                  text: 'Cambios: ${_dirtyStudents.length}',
                  bg: const Color(0xFFFFF5E6),
                  fg: const Color(0xFF8A5B00),
                  maxWidth: 160,
                ),
              const Spacer(),
                _pill(
                  icon: Icons.calendar_month,
                text: _schoolYearLabel(_yearSel),
                  bg: const Color(0xFFEFF3FF),
                  fg: _blue,
                maxWidth: 140,
                ),
              const SizedBox(width: 8),
              if (_tandaSel.trim().isNotEmpty)
                _pill(
                  icon: Icons.schedule,
                  text: _tandaSel,
                  bg: const Color(0xFFEFF3FF),
                  fg: _blue,
                  maxWidth: 140,
                ),
              if (_tandaSel.trim().isNotEmpty) const SizedBox(width: 8),
              if (gradeId.isNotEmpty)
                _pill(
                  icon: Icons.school,
                  text: _gradeNameById(gradeId),
                  bg: const Color(0xFFEFF3FF),
                  fg: _blue,
                  maxWidth: 180,
                ),
              const SizedBox(width: 8),
              if (subjectId.isNotEmpty)
                _pill(
                  icon: Icons.book,
                  text: _subjectNameById(subjectId),
                  bg: const Color(0xFFEFF3FF),
                  fg: _blue,
                  maxWidth: 220,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: Colors.grey.shade200, height: 1),
          const SizedBox(height: 12),
          if (!canShow)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Selecciona Año, Grado y Asignatura para ver la tabla.'),
            )
          else if (_students.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No hay alumnos en este grado (o no tienes permiso para verlos).'),
            )
          else
            SizedBox(
              height: 520,
              child: _GradeGrid(
                blue: _blue,
                orange: _orange,
                students: _students,
                compTexts: _compTexts,
                hHeader: _hHeader,
                hBody: _hBody,
                wNum: _wNum,
                wStudent: _wStudent,
                wCell: _wCell,
                wCalc: _wCalc,
                onCellChanged: (studentId, key, v) {
                  final cleaned = v.replaceAll(RegExp(r'[^0-9]'), '');
                  _setLocalValue(studentId, key, cleaned, markDirty: true);

                  final c = _ctrlFor(studentId, key);
                  if (c.text != cleaned) {
                    c.value = c.value.copyWith(
                      text: cleaned,
                      selection: TextSelection.collapsed(offset: cleaned.length),
                    );
                  }

                  setState(() {});
                },
                ctrlFor: _ctrlFor,
                rpEnabled: _rpEnabled,
                avgCompetencia: (sid, p) => _avgCompetencia(sid, p),
                avgFinal: _avgFinal,
                fmtAvg: _fmtAvg,
                cellKey: _cellKey,
              ),
            ),
        ],
      ),
    );
  }

  Widget _pill({
    required IconData icon,
    required String text,
    required Color bg,
    required Color fg,
    double maxWidth = 240,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: fg.withOpacity(0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ===============================================================
/// Grid Widget (separado para mantener build limpio)
/// ===============================================================
class _GradeGrid extends StatelessWidget {
  final Color blue;
  final Color orange;

  final List<_StudentRow> students;
  final List<String> compTexts;

  final ScrollController hHeader;
  final ScrollController hBody;

  final double wNum;
  final double wStudent;
  final double wCell;
  final double wCalc;

  final void Function(String studentId, String key, String v) onCellChanged;
  final TextEditingController Function(String studentId, String key) ctrlFor;

  final bool Function(String studentId, int comp, int periodo) rpEnabled;
  final double? Function(String studentId, int periodo) avgCompetencia;
  final double? Function(String studentId) avgFinal;
  final String Function(double?) fmtAvg;
  final String Function(int comp, int periodo, bool rp) cellKey;

  const _GradeGrid({
    required this.blue,
    required this.orange,
    required this.students,
    required this.compTexts,
    required this.hHeader,
    required this.hBody,
    required this.wNum,
    required this.wStudent,
    required this.wCell,
    required this.wCalc,
    required this.onCellChanged,
    required this.ctrlFor,
    required this.rpEnabled,
    required this.avgCompetencia,
    required this.avgFinal,
    required this.fmtAvg,
    required this.cellKey,
  });

  static final _digitsOnly = FilteringTextInputFormatter.digitsOnly;

  @override
  Widget build(BuildContext context) {
    final totalWidth = wNum + wStudent + (4 * 8 * wCell) + (4 * wCalc) + wCalc;

    return Column(
      children: [
        SizedBox(
          height: 124,
          child: SingleChildScrollView(
            controller: hHeader,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalWidth,
              child: Column(
                children: [
                  _headerRowCompetencias(totalWidth),
                  _headerRowPRP(totalWidth),
                ],
              ),
            ),
          ),
        ),
        Divider(color: Colors.grey.shade200, height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: hBody,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalWidth,
              child: ListView.separated(
                itemCount: students.length,
                separatorBuilder: (_, __) => Divider(color: Colors.grey.shade200, height: 1),
                itemBuilder: (context, i) {
                  final s = students[i];
                  return _row(context, index: i + 1, s: s);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerCell({
    required double w,
    required Widget child,
    Color? bg,
    bool borderRight = true,
  }) {
    return Container(
      width: w,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg ?? Colors.white,
        border: Border(
          right: borderRight ? BorderSide(color: Colors.grey.shade300) : BorderSide.none,
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: child,
    );
  }

  Widget _headerRowCompetencias(double totalWidth) {
    return SizedBox(
      height: 70,
      width: totalWidth,
      child: Row(
        children: [
          _headerCell(
            w: wNum,
            bg: const Color(0xFFF7F9FC),
            child: const Text('#', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          _headerCell(
            w: wStudent,
            bg: const Color(0xFFF7F9FC),
            child: const Text('Alumno', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
          for (int c = 1; c <= 4; c++)
            _headerCell(
              w: 8 * wCell,
              bg: const Color(0xFFF7F9FC),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Competencia $c', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Text(
                      (compTexts.length >= c ? compTexts[c - 1] : '').trim().isEmpty ? '—' : compTexts[c - 1],
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade800, height: 1.15, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          for (int i = 1; i <= 4; i++)
            _headerCell(
              w: wCalc,
              bg: const Color(0xFFF7F9FC),
              child: RotatedBox(
                quarterTurns: 3,
                child: Text('PCE$i', style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          _headerCell(
            w: wCalc,
            bg: const Color(0xFFF7F9FC),
            borderRight: false,
            child: const RotatedBox(
              quarterTurns: 3,
              child: Text('FINAL', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerRowPRP(double totalWidth) {
    Widget prpLabel(String t, {bool isRP = false}) {
      return Text(
        t,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12,
          color: isRP ? Colors.grey.shade800 : Colors.black87,
        ),
      );
    }

    Color colBg(int colIndexWithin8) {
      final isRp = (colIndexWithin8 % 2 == 1);
      return isRp ? const Color(0xFFF1F1F1) : Colors.white;
    }

    return SizedBox(
      height: 54,
      width: totalWidth,
      child: Row(
        children: [
          _headerCell(w: wNum, bg: Colors.white, child: const SizedBox.shrink()),
          _headerCell(w: wStudent, bg: Colors.white, child: const SizedBox.shrink()),
          for (int c = 1; c <= 4; c++)
            for (int p = 1; p <= 4; p++) ...[
              _headerCell(
                w: wCell,
                bg: colBg((p - 1) * 2),
                child: prpLabel('P$p'),
              ),
              _headerCell(
                w: wCell,
                bg: colBg((p - 1) * 2 + 1),
                child: prpLabel('RP$p', isRP: true),
              ),
            ],
          for (int i = 0; i < 4; i++) _headerCell(w: wCalc, bg: Colors.white, child: const SizedBox.shrink()),
          _headerCell(w: wCalc, bg: Colors.white, borderRight: false, child: const SizedBox.shrink()),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, {required int index, required _StudentRow s}) {
    Color colBg(int within8, {bool isDisabled = false}) {
      final isRp = (within8 % 2 == 1);
      final base = isRp ? const Color(0xFFF6F6F6) : Colors.white;
      return isDisabled ? const Color(0xFFECECEC) : base;
    }

    Widget scoreCell({
      required int comp,
      required int periodo,
      required bool rp,
    }) {
      final key = cellKey(comp, periodo, rp);
      final enabled = !rp || rpEnabled(s.id, comp, periodo);
      final c = ctrlFor(s.id, key);

      return Container(
        width: wCell,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colBg(((periodo - 1) * 2) + (rp ? 1 : 0), isDisabled: !enabled),
          border: Border(
            right: BorderSide(color: Colors.grey.shade300),
          ),
        ),
        child: TextField(
          controller: c,
          enabled: enabled,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [
            _digitsOnly,
            LengthLimitingTextInputFormatter(3),
          ],
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 10),
          ),
          onChanged: (v) => onCellChanged(s.id, key, v),
        ),
      );
    }

    Widget calcCell(String text, {bool borderRight = true}) {
      return Container(
        width: wCalc,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FC),
          border: Border(
            right: borderRight ? BorderSide(color: Colors.grey.shade300) : BorderSide.none,
          ),
        ),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
      );
    }

    final pce1 = fmtAvg(avgCompetencia(s.id, 1));
    final pce2 = fmtAvg(avgCompetencia(s.id, 2));
    final pce3 = fmtAvg(avgCompetencia(s.id, 3));
    final pce4 = fmtAvg(avgCompetencia(s.id, 4));
    final fin = fmtAvg(avgFinal(s.id));

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Container(
            width: wNum,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FC),
              border: Border(right: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Text(index.toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          Container(
            width: wStudent,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Text(
              s.display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          for (int c = 1; c <= 4; c++)
            for (int p = 1; p <= 4; p++) ...[
              scoreCell(comp: c, periodo: p, rp: false),
              scoreCell(comp: c, periodo: p, rp: true),
            ],
          calcCell(pce1),
          calcCell(pce2),
          calcCell(pce3),
          calcCell(pce4),
          calcCell(fin, borderRight: false),
        ],
      ),
    );
  }
}
