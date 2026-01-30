// lib/docentes/screens/paneldedocentes.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

// ✅ IMPORTA TU ENUM REAL DEL CALENDARIO
import 'package:edupro/calendario/models/user_role.dart';

// ✅ CALENDARIO
import 'package:edupro/calendario/ui/calendario_screen.dart';

// ✅ CHAT NUEVO (docentes)
import 'D_chat_docente_screen.dart';

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

  // ✅ resueltos por members
  String _rootCol = 'schools'; // o 'escuelas'
  String? _schoolIdAuth;
  String? _teacherDocIdAuth;
  String _memberRole = '';

  String _teacherName = '';
  List<String> _teacherGrades = [];
  List<String> _teacherSubjects = [];

  List<String> _schoolGrades = [];
  List<String> _schoolSubjects = [];

  String? _selectedGrade;
  String? _selectedSubject;

  // ✅ school doc id: eduproapp_admin_ITVB9J7T (tu “modo actual”)
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
    _loadFromMembers();
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
    final a = _asStringListOrMapKeys(data['grados']);
    if (a.isNotEmpty) return a;
    final b = _asStringListOrMapKeys(data['grades']);
    if (b.isNotEmpty) return b;
    final c = _asStringListOrMapKeys(data['gradeIds']);
    if (c.isNotEmpty) return c;
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
  // 1) Resolver members + schoolId real
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

  Future<void> _loadFromMembers() async {
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
    final emailLower = (user.email ?? '').toLowerCase().trim();

    final schoolCandidates = _candidateSchoolIds();
    const rootCandidates = ['schools', 'escuelas'];

    Future<DocumentSnapshot<Map<String, dynamic>>?> _tryMemberByQuery(
      String root,
      String schoolId,
    ) async {
      final membersRef = _db.collection(root).doc(schoolId).collection('members');

      try {
        final q = await membersRef.where('authUid', isEqualTo: uid).limit(1).get();
        if (q.docs.isNotEmpty) return q.docs.first;
      } catch (_) {}

      try {
        final q = await membersRef.where('uid', isEqualTo: uid).limit(1).get();
        if (q.docs.isNotEmpty) return q.docs.first;
      } catch (_) {}

      if (emailLower.isNotEmpty) {
        try {
          final q = await membersRef.where('emailLower', isEqualTo: emailLower).limit(1).get();
          if (q.docs.isNotEmpty) return q.docs.first;
        } catch (_) {}

        try {
          final q = await membersRef.where('email', isEqualTo: emailLower).limit(1).get();
          if (q.docs.isNotEmpty) return q.docs.first;
        } catch (_) {}
      }

      return null;
    }

    DocumentSnapshot<Map<String, dynamic>>? memberSnap;
    String? resolvedSchoolId;
    String resolvedRoot = 'schools';

    for (final root in rootCandidates) {
      for (final sid in schoolCandidates) {
        final direct = await _tryMember(root, sid, uid);
        if (direct != null) {
          memberSnap = direct;
          resolvedSchoolId = sid;
          resolvedRoot = root;
          break;
        }

        final byQuery = await _tryMemberByQuery(root, sid);
        if (byQuery != null) {
          debugPrint('✅ MEMBER FOUND (QUERY) => ${byQuery.reference.path}');
          memberSnap = byQuery;
          resolvedSchoolId = sid;
          resolvedRoot = root;
          break;
        }
      }
      if (memberSnap != null) break;
    }

    if (memberSnap == null || resolvedSchoolId == null) {
      setState(() {
        _loading = false;
        _error =
            'No encontré tu member.\nProbé schoolId: ${schoolCandidates.join(", ")}\nEn: schools y escuelas.';
      });
      return;
    }

    final md = memberSnap.data() ?? {};
    final role = (md['role'] ?? md['rol'] ?? '').toString().trim().toLowerCase();

    String teacherDocId = (md['teacherDocId'] ??
            md['teacherDocID'] ??
            md['teacherId'] ??
            md['docenteId'] ??
            '')
        .toString()
        .trim();

    // ✅ fallback: si el member no trae teacherDocId, búscalo en teachers_public/teacher_public
    if (teacherDocId.isEmpty) {
      final resolved = await _resolveTeacherDocIdFromPublicIndex(
        resolvedRoot,
        resolvedSchoolId,
        user,
      );

      if (resolved.isNotEmpty) {
        teacherDocId = resolved;

        // ✅ intenta guardar el teacherDocId en el member para la próxima
        try {
          await memberSnap.reference.set({
            'teacherDocId': teacherDocId,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint('⚠️ No pude guardar teacherDocId en member: $e');
        }
      }
    }

    // ❌ si sigue vacío => muestra error y corta
    if (teacherDocId.isEmpty) {
      setState(() {
        _rootCol = resolvedRoot;
        _schoolIdAuth = resolvedSchoolId;
        _memberRole = role;
        _loading = false;
        _error =
            'Encontré el member, pero NO pude resolver teacherDocId.\n'
            'Ruta: $resolvedRoot/$resolvedSchoolId/members/(docId puede no ser uid)\n'
            'Revisa teachers_public/teacher_public: authUid/emailLower/teacherId.';
      });
      return;
    }

    // ✅ ok: ya tenemos root + schoolId + teacherDocId
    _rootCol = resolvedRoot;
    _schoolIdAuth = resolvedSchoolId;
    _teacherDocIdAuth = teacherDocId;
    _memberRole = role;

    await Future.wait([
      _loadTeacherByDocId(),
      _loadCatalogGrades(),
      _loadCatalogSubjects(),
    ]);

    _applySelections();

    if (!mounted) return;
    setState(() => _loading = false);
  }

  // -------------------------
  // 2) Cargar docente desde teacher_directory (fallback teachers / teachers_public)
  // -------------------------
  Future<Map<String, dynamic>?> _getTeacherDocFromAny(String teacherDocId) async {
    final sid = _schoolIdAuth!;
    final root = _rootCol;

    final paths = [
      _db.collection(root).doc(sid).collection('teacher_directory').doc(teacherDocId),
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
        _error = 'No pude leer el documento del docente (teacher_directory/teachers/teachers_public).';
      });
      return;
    }

    final name = _readName(data);
    final grades = _readGrades(data);
    final subjects = _readSubjects(data);

    if (!mounted) return;
    setState(() {
      _teacherName = name.isNotEmpty ? name : userFallbackName();
      _teacherGrades = grades;
      _teacherSubjects = subjects;
    });
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
      final out = <String>{};

      for (final d in docs) {
        final m = d.data();
        final name = (m['name'] ?? m['gradoKey'] ?? m['nombre'] ?? d.id).toString().trim();
        if (name.isNotEmpty) out.add(name);
      }

      final list = out.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (!mounted) return;
      setState(() => _schoolGrades = list);
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

  void _applySelections() {
    final gradesOptions = _teacherGrades.isNotEmpty ? _teacherGrades : _schoolGrades;
    final subjectsOptions = _teacherSubjects.isNotEmpty ? _teacherSubjects : _schoolSubjects;

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
      _selectedGrade = nextGrade;
      _selectedSubject = nextSubject;
    });
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

  // -------------------------
  // UI (más compacto, mismas funciones)
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
              // fila superior (nombre + meta)
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

              // controles compactos (en una línea si cabe)
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

                  // ✅ Header MUCHO más compacto (mismas funciones)
                  _compactHeader(
                    gradesOptions: gradesOptions,
                    subjectsOptions: subjectsOptions,
                  ),

                  const SizedBox(height: 12),

                  // ✅ Menú (más denso y sin “gigantismo”)
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final crossAxisCount = width < 600 ? 2 : 4;

                        // tiles más compactos
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
                            _menuItem(
                              context,
                              Icons.group,
                              'Estudiantes',
                              onTap: () => Navigator.pushNamed(
                                context,
                                '/estudiantes',
                                arguments: widget.escuela,
                              ),
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
