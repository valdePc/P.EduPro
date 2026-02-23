// lib/docentes/screens/paneldedocentes.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

// ✅ IMPORTA TU ENUM REAL DEL CALENDARIO
import 'package:edupro/calendario/models/user_role.dart';

// ✅ CALENDARIO
import 'package:edupro/calendario/ui/calendario_screen.dart';
import 'package:edupro/docentes/screens/calendario_escolar.dart';


// ✅ CHAT NUEVO (docentes)
import 'D_chat_docente_screen.dart';

// ✅ ESTUDIANTES (docentes)
import 'estudiantes.dart'; // ajusta si tu path es distinto

class PaneldedocentesScreen extends StatefulWidget {
  final Escuela escuela;
  const PaneldedocentesScreen({Key? key, required this.escuela}) : super(key: key);

  @override
  State<PaneldedocentesScreen> createState() => _PaneldedocentesScreenState();
}

class _PaneldedocentesScreenState extends State<PaneldedocentesScreen> {
  static const Color primaryColor = Color.fromARGB(255, 255, 193, 7); // naranja
  static const Color secondaryColor = Color.fromARGB(255, 21, 101, 192); // azul

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _loading = true;
  String? _error;

  // ✅ resueltos por members / teachers
  String _rootCol = 'schools'; // o 'escuelas'
  String? _schoolIdAuth;
  String? _teacherDocIdAuth;
  String _memberRole = '';

  String _teacherName = '';
  List<String> _teacherGrades = [];
  List<String> _teacherSubjects = [];
  List<String> _teacherGradeIds = [];

  // ✅ NUEVO: para mapear label -> gradoKey
  List<String> _teacherGradeKeys = [];
  Map<String, String> _gradeLabelToKey = {};

  // ✅ NUEVO: mapping desde catálogo grados (name/label -> gradoKey/docId)
  Map<String, String> _catalogGradeLabelToKey = {};
  Map<String, String> _catalogGradeLabelToId = {};

  List<String> _schoolGrades = [];
  List<String> _schoolSubjects = [];

  String? _selectedGrade;
  String? _selectedSubject;

  // ✅ NUEVO: listener en vivo al docente (teachers_public)
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _teacherPublicSub;
  DocumentReference<Map<String, dynamic>>? _teacherPublicRef;

  // cache de identidad para resolver doc en teachers_public
  String _emailLowerCache = '';
  String _emailRawCache = '';
  String _phoneE164Cache = '';
  String _phoneLocalCache = '';
  String _uidCache = '';

  String _resolveSelectedGradeId(String selectedLabel) {
  final sel = selectedLabel.trim().toLowerCase();
  if (sel.isEmpty) return '';

  // Caso ideal: grades y gradeIds alineados por índice
  if (_teacherGrades.isNotEmpty &&
      _teacherGradeIds.isNotEmpty &&
      _teacherGrades.length == _teacherGradeIds.length) {
    final idx = _teacherGrades.indexWhere((g) => g.trim().toLowerCase() == sel);
    if (idx >= 0) return _teacherGradeIds[idx].trim();
  }

  // Fallback: si el label ya vino siendo un id y está dentro de gradeIds
  final maybeId = selectedLabel.trim();
  if (_teacherGradeIds.contains(maybeId)) return maybeId;

  return '';
}

  // ✅ school doc id: eduproapp_admin_<CODIGO> (tu “modo actual”)
  String get _schoolDocId {
    final raw = normalizeSchoolIdFromEscuela(widget.escuela).toString().trim();

    if (raw.startsWith('eduproapp_admin_')) {
      final tail = raw.replaceFirst('eduproapp_admin_', '').toUpperCase();
      return 'eduproapp_admin_$tail';
    }
    return 'eduproapp_admin_${raw.toUpperCase()}';
  }

  @override
  void initState() {
    super.initState();
    _loadTeacherFromTeachers(); // ✅ buscar directo en schools/.../teachers
  }

  @override
  void dispose() {
    _teacherPublicSub?.cancel();
    _teacherPublicSub = null;
    super.dispose();
  }

  // ------------------------------------------------------------
  // ✅ Si el member NO trae teacherDocId, intenta resolverlo
  //    en teachers_public / teacher_public (por emailLower / email / authUid)
  // ------------------------------------------------------------
  Future<String> _resolveTeacherDocIdFromPublicIndex(
    String root,
    String schoolId,
    User user,
  ) async {
    final emailLower = (user.email ?? '').toLowerCase().trim();
    final uid = user.uid;

    final collections = ['teachers_public', 'teacher_public'];

    for (final col in collections) {
      final ref = _db.collection(root).doc(schoolId).collection(col);

      // 1) por emailLower
      if (emailLower.isNotEmpty) {
        try {
          final q1 = await ref.where('emailLower', isEqualTo: emailLower).limit(1).get();
          if (q1.docs.isNotEmpty) {
            final d = q1.docs.first;
            final data = d.data();
            final id = (data['teacherDocId'] ?? data['teacherId'] ?? d.id).toString().trim();
            if (id.isNotEmpty) return id;
          }
        } catch (_) {}
      }

      // 2) por email (por si guardaste email normal)
      if (emailLower.isNotEmpty) {
        try {
          final q2 = await ref.where('email', isEqualTo: emailLower).limit(1).get();
          if (q2.docs.isNotEmpty) {
            final d = q2.docs.first;
            final data = d.data();
            final id = (data['teacherDocId'] ?? data['teacherId'] ?? d.id).toString().trim();
            if (id.isNotEmpty) return id;
          }
        } catch (_) {}
      }

      // 3) por authUid (aunque no haya email)
      try {
        final q3 = await ref.where('authUid', isEqualTo: uid).limit(1).get();
        if (q3.docs.isNotEmpty) {
          final d = q3.docs.first;
          final data = d.data();
          final id = (data['teacherDocId'] ?? data['teacherId'] ?? d.id).toString().trim();
          if (id.isNotEmpty) return id;
        }
      } catch (_) {}
    }

    return '';
  }

  // -------------------------
  // Helpers (listas / maps)
  // -------------------------
  List<String> _asStringListOrMapKeys(dynamic v) {
    if (v is List) {
      return v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    if (v is Map) {
      return v.keys.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }

  String _readName(Map<String, dynamic> data) {
    return (data['name'] ??
            data['nombre'] ??
            data['displayName'] ??
            data['fullName'] ??
            '')
        .toString()
        .trim();
  }
List<String> _readGrades(Map<String, dynamic> data) {
  // ✅ Primero el campo nuevo
  final b = _asStringListOrMapKeys(data['grades']);
  if (b.isNotEmpty) return b;

  // ✅ Luego compat con campo viejo
  final a = _asStringListOrMapKeys(data['grados']);
  if (a.isNotEmpty) return a;

  final c = _asStringListOrMapKeys(data['gradeIds']);
  if (c.isNotEmpty) return c;

  return const [];
}

List<String> _readGradeIds(Map<String, dynamic> data) {
  final a = _asStringListOrMapKeys(data['gradeIds']);
  if (a.isNotEmpty) return a;

  final b = _asStringListOrMapKeys(data['gradoIds']);
  if (b.isNotEmpty) return b;

  final c = _asStringListOrMapKeys(data['gradosIds']);
  if (c.isNotEmpty) return c;

  final d = _asStringListOrMapKeys(data['gradesIds']);
  if (d.isNotEmpty) return d;

  return const [];
}

// ✅ leer gradeKeys/keys reales (gradoKey) del docente
List<String> _readGradeKeys(Map<String, dynamic> data) {
  final a = _asStringListOrMapKeys(data['gradosKeys']);
  if (a.isNotEmpty) return a;

  final b = _asStringListOrMapKeys(data['gradoKeys']);
  if (b.isNotEmpty) return b;

  final c = _asStringListOrMapKeys(data['gradeKeys']);
  if (c.isNotEmpty) return c;

  final d = _asStringListOrMapKeys(data['gradosAsignadosKeys']);
  if (d.isNotEmpty) return d;

  return const [];
}


  List<String> _readSubjects(Map<String, dynamic> data) {
    final a = _asStringListOrMapKeys(data['subjects']);
    if (a.isNotEmpty) return a;
    final b = _asStringListOrMapKeys(data['materias']);
    if (b.isNotEmpty) return b;
    final c = _asStringListOrMapKeys(data['asignaturas']);
    if (c.isNotEmpty) return c;
    return const [];
  }

  List<String> _candidateSchoolIds() {
    final raw = normalizeSchoolIdFromEscuela(widget.escuela).toString().trim();

    final out = <String>[
      _schoolDocId,
      raw,
      raw.toUpperCase(),
      raw.toLowerCase(),
    ];

    final seen = <String>{};
    return out.where((e) {
      final v = e.trim();
      if (v.isEmpty) return false;
      if (seen.contains(v)) return false;
      seen.add(v);
      return true;
    }).toList();
  }

  String _initials(String name) {
    final t = name.trim();
    if (t.isEmpty) return 'D';
    final parts = t.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'D';
    final first = parts.first;
    final last = parts.length > 1 ? parts.last : '';
    final a = first.isNotEmpty ? first[0] : 'D';
    final b = last.isNotEmpty ? last[0] : '';
    return (a + b).toUpperCase();
  }

  // -------------------------
  // ✅ NUEVO: construir mapping label->key combinando:
  // - catálogo de grados (name/label -> gradoKey/docId)
  // - info del docente (si viene alineado label[i] -> key[i])
  // -------------------------
  Map<String, String> _buildGradeLabelToKeyMap({
    required List<String> gradesLabels,
    required List<String> gradeKeys,
  }) {
    final map = <String, String>{};

    // 1) base catálogo
    map.addAll(_catalogGradeLabelToKey);

    // 2) si vienen alineados por índice: label[i] -> key[i]
    if (gradesLabels.isNotEmpty &&
        gradeKeys.isNotEmpty &&
        gradesLabels.length == gradeKeys.length) {
      for (int i = 0; i < gradesLabels.length; i++) {
        final label = gradesLabels[i].trim();
        final key = gradeKeys[i].trim();
        if (label.isNotEmpty && key.isNotEmpty) {
          map[label] = key;
          map[label.toLowerCase().trim()] = key;
        }
      }
    }

    // 3) fallback: key -> key
    for (final k in gradeKeys) {
      final key = k.trim();
      if (key.isEmpty) continue;
      map[key] = key;
      map[key.toLowerCase().trim()] = key;
    }

    return map;
  }

  // -------------------------
  // ✅ NUEVO: aplica estado docente + revalida dropdowns en 1 setState
  // -------------------------
  void _applyTeacherDataToState(Map<String, dynamic> data) {
    final user = FirebaseAuth.instance.currentUser;

    final name = _readName(data);
    final grades = _readGrades(data);
    final subjects = _readSubjects(data);
    final gradeIds = _readGradeIds(data);
    final gradeKeys = _readGradeKeys(data);

    final map = _buildGradeLabelToKeyMap(
      gradesLabels: grades,
      gradeKeys: gradeKeys,
    );

    final nextTeacherName = name.isNotEmpty ? name : userFallbackName();
  final nextTeacherGrades =
    grades.isNotEmpty ? grades : _teacherGrades;

final nextTeacherSubjects =
    subjects.isNotEmpty ? subjects : _teacherSubjects;

    final gradesOptions = nextTeacherGrades.isNotEmpty ? nextTeacherGrades : _schoolGrades;
    final subjectsOptions = nextTeacherSubjects.isNotEmpty ? nextTeacherSubjects : _schoolSubjects;

    final nextGrade = gradesOptions.isNotEmpty
        ? ((_selectedGrade != null && gradesOptions.contains(_selectedGrade))
            ? _selectedGrade
            : gradesOptions.first)
        : null;

    final nextSubject = subjectsOptions.isNotEmpty
        ? ((_selectedSubject != null && subjectsOptions.contains(_selectedSubject))
            ? _selectedSubject
            : subjectsOptions.first)
        : null;

    if (!mounted) return;
    setState(() {
      _teacherName = nextTeacherName;
      _teacherGrades = nextTeacherGrades;
      _teacherSubjects = nextTeacherSubjects;
      _teacherGradeIds = gradeIds;

      _teacherGradeKeys = gradeKeys;
      _gradeLabelToKey = map;

      _selectedGrade = nextGrade;
      _selectedSubject = nextSubject;

      // si el stream era el que estaba controlando, quitamos error viejo
      _error = null;
    });
  }

  // -------------------------
  // ✅ NUEVO: resolver docId real en teachers_public y suscribirse
  // -------------------------
  Future<DocumentReference<Map<String, dynamic>>?> _resolveTeachersPublicDocRef({
    required String root,
    required String schoolId,
    required String teacherDocId,
  }) async {
    final col = _db.collection(root).doc(schoolId).collection('teachers_public');

    // 0) docId directo (ideal)
    try {
      final direct = col.doc(teacherDocId);
      final snap = await direct.get();
      if (snap.exists) return direct;
    } catch (_) {}

    // 1) buscar por teacherDocId / teacherId
    Future<DocumentReference<Map<String, dynamic>>?> byField(String field, String value) async {
      if (value.trim().isEmpty) return null;
      try {
        final q = await col.where(field, isEqualTo: value.trim()).limit(1).get();
        if (q.docs.isNotEmpty) return q.docs.first.reference;
      } catch (_) {}
      return null;
    }

    final ref1 = await byField('teacherDocId', teacherDocId);
    if (ref1 != null) return ref1;

    final ref2 = await byField('teacherId', teacherDocId);
    if (ref2 != null) return ref2;

    // 2) fallback por authUid/email/phone (por si el docId no es teacherDocId)
    final ref3 = await byField('authUid', _uidCache);
    if (ref3 != null) return ref3;

    final ref4 = await byField('emailLower', _emailLowerCache);
    if (ref4 != null) return ref4;

    final ref5 = await byField('phoneLocal', _phoneLocalCache);
    if (ref5 != null) return ref5;

    final ref6 = await byField('phone', _phoneE164Cache);
    if (ref6 != null) return ref6;

    return null;
  }

  Future<void> _attachTeacherPublicRealtime() async {
    final sid = _schoolIdAuth;
    final tid = _teacherDocIdAuth;
    if (sid == null || tid == null) return;

    // evitar duplicar
    if (_teacherPublicSub != null) return;

    final ref = await _resolveTeachersPublicDocRef(
      root: _rootCol,
      schoolId: sid,
      teacherDocId: tid,
    );

    if (ref == null) {
      debugPrint('⚠️ No pude resolver doc en teachers_public para tid=$tid');
      return;
    }

    _teacherPublicRef = ref;

    debugPrint('🔴 Subscribing teachers_public => ${ref.path}');

    _teacherPublicSub = ref.snapshots(includeMetadataChanges: true).listen(
      (snap) {
        if (!snap.exists) return;
        final data = snap.data() ?? <String, dynamic>{};
        _applyTeacherDataToState(data);
      },
      onError: (e) {
        debugPrint('⚠️ teachers_public stream error => $e');
      },
    );
  }

  // -------------------------
  // 1) Resolver members + schoolId real (no usado ahora, pero lo dejo)
  // -------------------------
  Future<DocumentSnapshot<Map<String, dynamic>>?> _tryMember(
    String root,
    String schoolId,
    String uid,
  ) async {
    try {
      final ref = _db.collection(root).doc(schoolId).collection('members').doc(uid);
      final snap = await ref.get();
      if (snap.exists) {
        debugPrint('✅ MEMBER FOUND => ${ref.path}');
        return snap;
      }
      debugPrint('.. member no existe => ${ref.path}');
      return null;
    } catch (e) {
      debugPrint('⚠️ error leyendo member $root/$schoolId => $e');
      return null;
    }
  }

  Future<void> _loadTeacherFromTeachers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'No hay sesión activa.';
      });
      return;
    }

    final uid = user.uid;
    _uidCache = uid;

    final emailRaw = (user.email ?? '').trim();
    final emailLower = emailRaw.toLowerCase();
    _emailRawCache = emailRaw;
    _emailLowerCache = emailLower;

    final phoneE164 = (user.phoneNumber ?? '').trim();
    _phoneE164Cache = phoneE164;

    String digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');
    final phoneDigits = digitsOnly(phoneE164);
    final phoneLocal =
        phoneDigits.length >= 10 ? phoneDigits.substring(phoneDigits.length - 10) : phoneDigits;
    _phoneLocalCache = phoneLocal;

    final schoolCandidates = _candidateSchoolIds();
    const rootCandidates = ['schools', 'escuelas'];

    DocumentSnapshot<Map<String, dynamic>>? teacherSnap;
    String? resolvedSchoolId;
    String resolvedRoot = 'schools';

    Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findOne(
      CollectionReference<Map<String, dynamic>> ref,
      String field,
      String value,
    ) async {
      if (value.trim().isEmpty) return null;
      try {
        final q = await ref.where(field, isEqualTo: value).limit(1).get();
        if (q.docs.isNotEmpty) return q.docs.first;
      } catch (e) {
        debugPrint('⚠️ where($field == $value) => $e');
      }
      return null;
    }

    for (final root in rootCandidates) {
      for (final sid in schoolCandidates) {
        final teachersRef = _db.collection(root).doc(sid).collection('teachers');

        // 0) docId == uid (por si acaso)
        try {
          final byId = await teachersRef.doc(uid).get();
          if (byId.exists) {
            teacherSnap = byId;
            resolvedSchoolId = sid;
            resolvedRoot = root;
            break;
          }
        } catch (_) {}

        // 1) authUid
        final byAuthUid = await _findOne(teachersRef, 'authUid', uid);
        if (byAuthUid != null) {
          teacherSnap = byAuthUid;
          resolvedSchoolId = sid;
          resolvedRoot = root;
          break;
        }

        // 2) emailLower / email
        if (emailLower.isNotEmpty) {
          final byEmailLower = await _findOne(teachersRef, 'emailLower', emailLower);
          if (byEmailLower != null) {
            teacherSnap = byEmailLower;
            resolvedSchoolId = sid;
            resolvedRoot = root;
            break;
          }

          final byEmail = await _findOne(teachersRef, 'email', emailLower);
          if (byEmail != null) {
            teacherSnap = byEmail;
            resolvedSchoolId = sid;
            resolvedRoot = root;
            break;
          }
        }

        // 3) phone / phoneLocal ✅
        if (phoneE164.isNotEmpty) {
          final byPhone = await _findOne(teachersRef, 'phone', phoneE164);
          if (byPhone != null) {
            teacherSnap = byPhone;
            resolvedSchoolId = sid;
            resolvedRoot = root;
            break;
          }
        }
        if (phoneLocal.isNotEmpty) {
          final byPhoneLocal = await _findOne(teachersRef, 'phoneLocal', phoneLocal);
          if (byPhoneLocal != null) {
            teacherSnap = byPhoneLocal;
            resolvedSchoolId = sid;
            resolvedRoot = root;
            break;
          }
        }

        // 4) fallback: teachers_public -> sacar teacherDocId y luego leer teachers/{id}
        final pubCols = ['teachers_public', 'teacher_public'];
        for (final pub in pubCols) {
          final pubRef = _db.collection(root).doc(sid).collection(pub);

          QueryDocumentSnapshot<Map<String, dynamic>>? pubSnap;

          if (emailLower.isNotEmpty) {
            pubSnap = await _findOne(pubRef, 'emailLower', emailLower) ?? pubSnap;
            pubSnap = await _findOne(pubRef, 'email', emailLower) ?? pubSnap;
          }
          if (pubSnap == null && phoneLocal.isNotEmpty) {
            pubSnap = await _findOne(pubRef, 'phoneLocal', phoneLocal);
          }
          if (pubSnap == null && phoneE164.isNotEmpty) {
            pubSnap = await _findOne(pubRef, 'phone', phoneE164);
          }
          if (pubSnap == null) {
            pubSnap = await _findOne(pubRef, 'authUid', uid);
          }

          if (pubSnap != null) {
            final pd = pubSnap.data();
            final teacherId =
                (pd['teacherDocId'] ?? pd['teacherId'] ?? pubSnap.id).toString().trim();
            if (teacherId.isNotEmpty) {
              try {
                final real = await teachersRef.doc(teacherId).get();
                if (real.exists) {
                  teacherSnap = real;
                  resolvedSchoolId = sid;
                  resolvedRoot = root;
                  break;
                }
              } catch (_) {}
            }
          }
        }
        if (teacherSnap != null) break;
      }
      if (teacherSnap != null) break;
    }

 if (teacherSnap == null || resolvedSchoolId == null) {
  setState(() {
    _loading = false;
    _error =
        'No encontré tu registro en teachers.\n'
        'Probé schoolId: ${schoolCandidates.join(", ")}\n'
        'Ruta: /schools/{schoolId}/teachers\n'
        'emailLower: ${emailLower.isEmpty ? "(vacío)" : emailLower}\n'
        'phoneLocal: ${phoneLocal.isEmpty ? "(vacío)" : phoneLocal}';
  });
  return;
}

// 🔥 DEBUG AQUÍ
debugPrint("=================================");
debugPrint("DOCENTE ENCONTRADO => ${teacherSnap.reference.path}");
debugPrint("SCHOOL RESUELTO => $resolvedSchoolId");
debugPrint("ROOT RESUELTO => $resolvedRoot");
debugPrint("DATA => ${teacherSnap.data()}");
debugPrint("=================================");

final data = teacherSnap.data() ?? {};

    // ✅ vincular authUid para que NUNCA vuelva a fallar
    final hasAuthUid = (data['authUid'] ?? '').toString().trim().isNotEmpty;
    if (!hasAuthUid) {
      try {
        await teacherSnap.reference.set({
          'authUid': uid,
          if (emailLower.isNotEmpty) 'emailLower': emailLower,
          if (emailRaw.isNotEmpty) 'email': emailRaw,
          if (phoneE164.isNotEmpty) 'phone': phoneE164,
          if (phoneLocal.isNotEmpty) 'phoneLocal': phoneLocal,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('⚠️ No pude guardar authUid en teacher: $e');
      }
    }

    _rootCol = resolvedRoot;
    _schoolIdAuth = resolvedSchoolId;
    _teacherDocIdAuth = teacherSnap.id;
    _memberRole = 'teacher';

    // ✅ Catálogos (por si teacher no trae grades/subjects completos)
    await Future.wait([
      _loadCatalogGrades(),
      _loadCatalogSubjects(),
    ]);

    // ✅ aplica info inicial (desde teachers) para no dejar UI vacía
    _applyTeacherDataToState(data);

    // ✅ NUEVO: escucha en vivo teachers_public (para reflejar cambios del admin)
    await _attachTeacherPublicRealtime();

    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  // -------------------------
  // 2) Cargar docente desde teacher_directory (fallback teachers / teachers_public)
  // -------------------------
  Future<Map<String, dynamic>?> _getTeacherDocFromAny(String teacherDocId) async {
    final sid = _schoolIdAuth!;
    final root = _rootCol;

    // ✅ Incluyo ambos nombres por si tu DB usa plural
    final paths = [
      _db.collection(root).doc(sid).collection('teacher_directory').doc(teacherDocId),
      _db.collection(root).doc(sid).collection('teachers_directory').doc(teacherDocId),
      _db.collection(root).doc(sid).collection('teachers').doc(teacherDocId),
      _db.collection(root).doc(sid).collection('teachers_public').doc(teacherDocId),
    ];

    for (final ref in paths) {
      try {
        final snap = await ref.get();
        if (snap.exists) {
          debugPrint('✅ TEACHER DOC FOUND => ${ref.path}');
          return snap.data();
        }
      } catch (e) {
        debugPrint('⚠️ error leyendo teacher doc ${ref.path} => $e');
      }
    }
    return null;
  }

  Future<void> _loadTeacherByDocId() async {
    if (_schoolIdAuth == null || _teacherDocIdAuth == null) return;

    final data = await _getTeacherDocFromAny(_teacherDocIdAuth!);
    if (data == null) {
      setState(() {
        _teacherName = userFallbackName();
        _teacherGrades = [];
        _teacherSubjects = [];
        _teacherGradeKeys = [];
        _gradeLabelToKey = _buildGradeLabelToKeyMap(gradesLabels: const [], gradeKeys: const []);
        _error = 'No pude leer el documento del docente (teacher_directory/teachers/teachers_public).';
      });
      return;
    }

    _applyTeacherDataToState(data);
  }

  String userFallbackName() {
    final u = FirebaseAuth.instance.currentUser;
    return (u?.displayName ?? u?.email ?? '--').toString();
  }

  // -------------------------
  // 3) Catálogos (grados / subjects)
  // -------------------------
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
  final sid = _schoolIdAuth;
  if (sid == null) return;

  final ref = _db.collection(_rootCol).doc(sid).collection('grados');

  try {
    final docs = await _safeFetch(ref);

    // ✅ log 1 vez
    debugPrint('📚 _loadCatalogGrades => ref=${ref.path} docs=${docs.length}');
    if (docs.isNotEmpty) {
      debugPrint('📚 ejemplo primero => id=${docs.first.id} data=${docs.first.data()}');
    }

    final out = <String>{};
    final map = <String, String>{};   // label -> gradoKey
    final mapId = <String, String>{}; // label -> gradeId (docId)

    int i = 0;
    for (final d in docs) {
      final m = d.data();

      // ✅ IMPORTANTE: label preferido es name/nombre
      final label = (m['name'] ?? m['nombre'] ?? m['label'] ?? m['gradoKey'] ?? d.id)
          .toString()
          .trim();

      // key real (prioridad: gradoKey)
      final key = (m['gradoKey'] ?? m['key'] ?? d.id).toString().trim();

      // gradeId real: docId del grado (ideal)
      final gradeId = (m['gradeId'] ?? d.id).toString().trim();

      // ✅ log solo primeros 3
      if (i < 3) {
        debugPrint('📚 grado[$i] => label="$label" key="$key" gradeId="$gradeId" docId=${d.id}');
      }
      i++;

      // ✅ map label -> gradeId
      if (label.isNotEmpty && gradeId.isNotEmpty) {
        mapId[label] = gradeId;
        mapId[label.toLowerCase().trim()] = gradeId;
      }
      // fallback: id->id
      if (gradeId.isNotEmpty) {
        mapId[gradeId] = gradeId;
        mapId[gradeId.toLowerCase().trim()] = gradeId;
      }

      // ✅ lista para dropdown
      if (label.isNotEmpty) out.add(label);

      // ✅ map label -> gradoKey
      if (label.isNotEmpty && key.isNotEmpty) {
        map[label] = key;
        map[label.toLowerCase().trim()] = key;
      }
      if (key.isNotEmpty) {
        map[key] = key;
        map[key.toLowerCase().trim()] = key;
      }
    }

    final list = out.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // ✅ log final 1 vez
    debugPrint(
      '📚 gradesOptions=${list.length} | tiene "1 de Primaria"=${mapId.containsKey("1 de Primaria")} | id="${mapId["1 de Primaria"] ?? ""}"',
    );

    if (!mounted) return;
    setState(() {
      _schoolGrades = list;
      _catalogGradeLabelToKey = map;
      _catalogGradeLabelToId = mapId;

      // refresca mapping combinado
      _gradeLabelToKey = _buildGradeLabelToKeyMap(
        gradesLabels: _teacherGrades,
        gradeKeys: _teacherGradeKeys,
      );
    });
  } catch (e) {
    debugPrint('ERROR _loadCatalogGrades => $e');
  }
}

  Future<void> _loadCatalogSubjects() async {
    final sid = _schoolIdAuth;
    if (sid == null) return;

    final cols = ['subjects', 'materias', 'asignaturas'];
    final out = <String>{};

    for (final c in cols) {
      final ref = _db.collection(_rootCol).doc(sid).collection(c);
      try {
        final docs = await _safeFetch(ref);
        for (final d in docs) {
          final m = d.data();
          final name = (m['name'] ?? m['nombre'] ?? d.id).toString().trim();
          if (name.isNotEmpty) out.add(name);
        }
      } catch (_) {}
      if (out.isNotEmpty) break;
    }

    final list = out.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (!mounted) return;
    setState(() => _schoolSubjects = list);
  }

  // -------------------------
  // Navegación
  // -------------------------
  void _openChatDocente() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DChatDocenteScreen(
          escuela: widget.escuela,
          docenteNombre: _teacherName.isNotEmpty ? _teacherName : null,
        ),
      ),
    );
  }

  void _openCalendarioDocente() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay sesión activa. Inicia sesión nuevamente.')),
      );
      return;
    }

    final schoolId = _schoolIdAuth ?? normalizeSchoolIdFromEscuela(widget.escuela);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CalendarioScreen(
          schoolId: schoolId,
          role: UserRole.teacher,
          userUid: user.uid,
          userGroups: const [],
        ),
      ),
    );
  }

  void _openCalendarioEscolarDocente() {
    final sid = (_schoolIdAuth ?? normalizeSchoolIdFromEscuela(widget.escuela))
        .toString()
        .trim();

    final selectedLabel = (_selectedGrade ?? '').trim();

    final key = selectedLabel.isNotEmpty
        ? (_gradeLabelToKey[selectedLabel] ??
            _gradeLabelToKey[selectedLabel.toLowerCase().trim()] ??
            '')
        : '';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CalendarioEscolarDocenteScreen(
          escuela: widget.escuela,
          schoolId: sid,
          initialGradeLabel: selectedLabel.isNotEmpty ? selectedLabel : null,
          initialGradeKey: key.isNotEmpty ? key : null,
        ),
      ),
    );
  }

  // ✅ abrir Estudiantes ya “amarrado” al grado seleccionado del panel
  void _openEstudiantesDocente() {
    final sid = _schoolIdAuth;
    if (sid == null || sid.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pude resolver el schoolId.')),
      );
      return;
    }

final selectedLabel = (_selectedGrade ?? '').trim();
if (selectedLabel.isEmpty) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Selecciona un grado primero.')),
  );
  return;
}

final resolvedGradeId = _resolveSelectedGradeId(selectedLabel);
debugPrint('🧪 Estudiantes => selectedLabel="$selectedLabel" | gradeId="$resolvedGradeId" | schoolId="$sid"');

final gradeKey = _gradeLabelToKey[selectedLabel] ??
    _gradeLabelToKey[selectedLabel.toLowerCase().trim()] ??
    selectedLabel;

final gradeId = _catalogGradeLabelToId[selectedLabel] ??
    _catalogGradeLabelToId[selectedLabel.toLowerCase().trim()] ??
    '';

debugPrint(
  '🧪 Estudiantes => selectedLabel="$selectedLabel" | gradeKey="$gradeKey" | gradeId="$gradeId" | schoolId="$sid"',
);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocenteEstudiantesScreen(
          escuela: widget.escuela,
          schoolIdOverride: sid,
          gradeKeyOverride: gradeKey,
          gradeLabelOverride: selectedLabel,
         // gradeIdOverride: gradeId.isNotEmpty ? gradeId : null,
          gradeIdOverride: resolvedGradeId.isNotEmpty ? resolvedGradeId : null,
        ),
      ),
    );
  }

  // -------------------------
  // UI
  // -------------------------
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

  Widget _compactHeader({
    required List<String> gradesOptions,
    required List<String> subjectsOptions,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final isNarrow = c.maxWidth < 650;

        final name = _teacherName.isNotEmpty ? _teacherName : '--';
        final avatarText = _initials(name);

        Widget gradeDrop() => SizedBox(
              width: isNarrow ? double.infinity : 200,
              child: DropdownButtonFormField<String>(
                value: _selectedGrade,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Grado',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: gradesOptions
                    .map((g) => DropdownMenuItem(
                          value: g,
                          child: Text(g, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: gradesOptions.isEmpty ? null : (v) => setState(() => _selectedGrade = v),
              ),
            );

        Widget subjectDrop() => SizedBox(
              width: isNarrow ? double.infinity : 240,
              child: DropdownButtonFormField<String>(
                value: _selectedSubject,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Asignatura',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: subjectsOptions
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged:
                    subjectsOptions.isEmpty ? null : (v) => setState(() => _selectedSubject = v),
              ),
            );

        Widget actions() => SizedBox(
              width: isNarrow ? double.infinity : 260,
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: () => Navigator.pushNamed(
                          context,
                          '/evaluaciones',
                          arguments: widget.escuela,
                        ),
                        icon: const Icon(Icons.fact_check, size: 18),
                        label: const Text('Evaluaciones', overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: secondaryColor.withOpacity(0.85)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          foregroundColor: secondaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: _openCalendarioDocente,
                        icon: const Icon(Icons.calendar_month, size: 18),
                        label: const Text('Calendario', overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ),
                ],
              ),
            );

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: secondaryColor.withOpacity(0.12)),
            boxShadow: [
              BoxShadow(
                blurRadius: 14,
                spreadRadius: 0,
                offset: const Offset(0, 6),
                color: Colors.black.withOpacity(0.06),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: secondaryColor,
                    child: Text(
                      avatarText,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'School: ${_schoolIdAuth ?? "--"} · role: ${_memberRole.isNotEmpty ? _memberRole : "--"}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.black.withOpacity(0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.20),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: primaryColor.withOpacity(0.35)),
                    ),
                    child: const Text(
                      'Docente',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (isNarrow) ...[
                gradeDrop(),
                const SizedBox(height: 10),
                subjectDrop(),
                const SizedBox(height: 10),
                actions(),
              ] else ...[
                Row(
                  children: [
                    Expanded(child: gradeDrop()),
                    const SizedBox(width: 10),
                    Expanded(child: subjectDrop()),
                    const SizedBox(width: 10),
                    Expanded(child: actions()),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombreEscuela = (widget.escuela.nombre ?? 'EduPro').trim();

    final gradesOptions = _teacherGrades.isNotEmpty ? _teacherGrades : _schoolGrades;
    final subjectsOptions = _teacherSubjects.isNotEmpty ? _teacherSubjects : _schoolSubjects;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(nombreEscuela, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: secondaryColor,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_error != null) ...[
                    _errorBox(_error!),
                    const SizedBox(height: 10),
                  ],
                  _compactHeader(
                    gradesOptions: gradesOptions,
                    subjectsOptions: subjectsOptions,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final crossAxisCount = width < 600 ? 2 : 4;

                        final tileHeight = width < 600 ? 130.0 : 120.0;
                        final childAspect = (width / crossAxisCount) / tileHeight;

                        return GridView.count(
                          padding: EdgeInsets.zero,
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: childAspect,
                          children: [
                            _menuItem(
                              context,
                              Icons.insert_drive_file,
                              'Planificaciones',
                              onTap: () => Navigator.pushNamed(
                                context,
                                '/planificaciones',
                                arguments: widget.escuela,
                              ),
                            ),
                            _menuItem(
                              context,
                              Icons.calendar_today,
                              'Períodos\ny Boletín',
                              onTap: () => Navigator.pushNamed(
                                context,
                                '/periodos',
                                arguments: widget.escuela,
                              ),
                            ),
                            _menuItem(
                              context,
                              Icons.lightbulb,
                              'Estrategias',
                              onTap: () => Navigator.pushNamed(
                                context,
                                '/estrategias',
                                arguments: widget.escuela,
                              ),
                            ),
                            _menuItem(
                              context,
                              Icons.book,
                              'Currículo',
                              onTap: () => Navigator.pushNamed(
                                context,
                                '/curriculo',
                                arguments: widget.escuela,
                              ),
                            ),

                            // ✅ abre Estudiantes filtrado por el grado seleccionado
                            _menuItem(
                              context,
                              Icons.group,
                              'Estudiantes',
                              onTap: _openEstudiantesDocente,
                            ),
                             _menuItem(
                              context,
                              Icons.schedule,
                              'Calendario\nEscolar',
                              onTap: _openCalendarioEscolarDocente,
                            ),

                            _menuItem(
                              context,
                              Icons.chat_bubble,
                              'Chat',
                              onTap: _openChatDocente,
                            ),
                            _menuItem(
                              context,
                              Icons.edit,
                              'Planificación\nDocente',
                              onTap: () => Navigator.pushNamed(
                                context,
                                '/planificacionDocente',
                                arguments: widget.escuela,
                              ),
                            ),
                            _menuItem(
                              context,
                              Icons.check_box,
                              'Colocar\nCalificaciones',
                              onTap: () => Navigator.pushNamed(
                                context,
                                '/colocarCalificaciones',
                                arguments: widget.escuela,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _menuItem(
    BuildContext context,
    IconData icon,
    String label, {
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: secondaryColor.withOpacity(0.18)),
          borderRadius: BorderRadius.circular(14),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              blurRadius: 10,
              offset: const Offset(0, 4),
              color: Colors.black.withOpacity(0.05),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: primaryColor.withOpacity(0.28)),
              ),
              child: Icon(icon, size: 24, color: secondaryColor),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}