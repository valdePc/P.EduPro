import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class AGestionDeMaestros extends StatefulWidget {
  final Escuela escuela;
  const AGestionDeMaestros({Key? key, required this.escuela}) : super(key: key);

  @override
  State<AGestionDeMaestros> createState() => _AGestionDeMaestrosState();
}

class _AGestionDeMaestrosState extends State<AGestionDeMaestros> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ✅ Nuevo flujo: el docente se REGISTRA SOLO (Auth real)
  // Admin aquí SOLO gestiona (aprobar/bloquear/editar/eliminar).
  static const String _statusPending = 'pending';
  static const String _statusActive = 'active';
  static const String _statusBlocked = 'blocked';

  String _search = '';
  String? _filterSubject;
  String? _filterStatus; // null => todos
  bool _loading = false;

  List<Map<String, dynamic>> _teachers = [];

  // Catálogos (de A_asignaturas y A_grados)
  List<String> _availableSubjects = [];
  List<String> _availableGrades = [];

  late final String _schoolIdPrimary;
  late final String _schoolIdAlt;
  late final List<String> _catalogSchoolIds;

  // Dónde realmente están los teachers (se resuelve solo)
  late String _teachersSchoolId;

  final List<StreamSubscription> _catalogSubs = [];
  final Map<String, Set<String>> _subjectsCache = {};
  final Map<String, Set<String>> _gradesCache = {};

  bool _formattingName = false;

  // Rutas candidatas donde A_asignaturas podría estar guardando
  static const List<String> _subjectCollectionsCandidates = [
    'subjects',
    'asignaturas',
    'materias',
    'catalog_subjects',
    'subjects_catalog',
    'catalogo_asignaturas',
  ];

  // Campos candidatos para top-level (si alguna pantalla guarda fuera de schools/{id})
  static const List<String> _topLevelSchoolFieldsToTry = [
    'schoolId',
    'school_id',
    'escuelaId',
    'escuela_id',
    'idEscuela',
    'school',
    'escuela',
    'schoolPath',
  ];

  static const List<String> _dialCodes = ['+1', '+34', '+57', '+52', '+51', '+56', '+54'];

  @override
  void initState() {
    super.initState();

    _schoolIdPrimary = normalizeSchoolIdFromEscuela(widget.escuela);
    _schoolIdAlt = _normalizeSchoolIdLikeAGrados(widget.escuela);
    _catalogSchoolIds = <String>{_schoolIdPrimary, _schoolIdAlt}.toList();

    _teachersSchoolId = _schoolIdPrimary;

    _listenCatalogsRealtime();
    _loadCatalogsOnce();
    _resolveTeachersSchoolId();
  }

  @override
  void dispose() {
    for (final s in _catalogSubs) {
      s.cancel();
    }
    _catalogSubs.clear();
    super.dispose();
  }

  // ------------------------------------------------------------
  //  SchoolId compat (por si A_grados usa otra normalización)
  // ------------------------------------------------------------
  String _normalizeSchoolIdLikeAGrados(Escuela e) {
    final raw = e.nombre ?? 'school-${e.hashCode}';
    var normalized = raw
        .replaceAll(RegExp(r'https?:\/\/'), '')
        .replaceAll(RegExp(r'\/\/+'), '/');
    normalized = normalized.replaceAll('/', '_').replaceAll(RegExp(r'[^A-Za-z0-9\-_]'), '');
    if (normalized.isEmpty) normalized = 'school-${e.hashCode}';
    return normalized;
  }

  // ------------------------------------------------------------
  //  Helpers
  // ------------------------------------------------------------
  List<String> _normalizeStringList(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
  }

  List<String> _parseCommaList(String raw) {
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }

  List<String> _teacherSubjects(Map<String, dynamic> t) {
    final list = _normalizeStringList(t['subjects']);
    if (list.isNotEmpty) return list;

    final s = (t['subjects'] ?? '').toString();
    if (s.contains(',')) return _parseCommaList(s);
    return s.trim().isEmpty ? const [] : [s.trim()];
  }

List<String> _teacherGrades(Map<String, dynamic> t) {
  // nuevo
  final listNew = _normalizeStringList(t['grades']);
  if (listNew.isNotEmpty) return listNew;

  // compat
  final listOld = _normalizeStringList(t['grados']);
  if (listOld.isNotEmpty) return listOld;

  final gNew = (t['grade'] ?? '').toString().trim();
  if (gNew.isNotEmpty) return gNew.contains(',') ? _parseCommaList(gNew) : [gNew];

  final gOld = (t['grado'] ?? '').toString().trim();
  if (gOld.isNotEmpty) return gOld.contains(',') ? _parseCommaList(gOld) : [gOld];

  return const [];
}


  String _normalizeStatus(dynamic raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    if (s == _statusBlocked) return _statusBlocked;
    if (s == _statusPending || s == 'pending_approval') return _statusPending;
    return _statusActive;
  }

  Color _statusColor(String status) {
    switch (status) {
      case _statusPending:
        return Colors.orange.shade700;
      case _statusBlocked:
        return Colors.red.shade700;
      case _statusActive:
      default:
        return Colors.green.shade700;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case _statusPending:
        return 'Pendiente';
      case _statusBlocked:
        return 'Bloqueado';
      case _statusActive:
      default:
        return 'Activo';
    }
  }

  void _syncFilterWithAvailableSubjects() {
    if (_filterSubject == null) return;
    if (!_availableSubjects.contains(_filterSubject)) _filterSubject = null;
  }

  void _recomputeSubjectsFromCache() {
    final set = <String>{};
    for (final s in _subjectsCache.values) {
      set.addAll(s);
    }
    final list = set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (!mounted) return;
    setState(() {
      _availableSubjects = list;
      _syncFilterWithAvailableSubjects();
    });
  }

  void _recomputeGradesFromCache() {
    final set = <String>{};
    for (final s in _gradesCache.values) {
      set.addAll(s);
    }
    final list = set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (!mounted) return;
    setState(() => _availableGrades = list);
  }

  // ✅ Title Case SIN comerse espacios
  String _titleCasePreserveSpaces(String input) {
    if (input.isEmpty) return input;

    final buf = StringBuffer();
    final re = RegExp(r'\S+|\s+');

    for (final m in re.allMatches(input)) {
      final token = m.group(0) ?? '';
      if (token.trim().isEmpty) {
        buf.write(token);
      } else {
        final lower = token.toLowerCase();
        final first = lower.substring(0, 1).toUpperCase();
        final rest = lower.length > 1 ? lower.substring(1) : '';
        buf.write('$first$rest');
      }
    }
    return buf.toString();
  }

  void _attachNameFormatter(TextEditingController ctrl) {
    ctrl.addListener(() {
      if (_formattingName) return;

      final current = ctrl.text;
      final formatted = _titleCasePreserveSpaces(current);
      if (current == formatted) return;

      _formattingName = true;
      final sel = ctrl.selection;
      final offset = sel.baseOffset;

      ctrl.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(
          offset: (offset < 0)
              ? formatted.length
              : (offset > formatted.length ? formatted.length : offset),
        ),
      );
      _formattingName = false;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ------------------------------------------------------------
  //  (Opcional) Directorio: solo para búsquedas/sugerencias
  //  *No toca passwords, no toca Auth.*
  // ------------------------------------------------------------
  Future<void> _upsertTeacherDirectoryFromData({
    required String teacherId,
    required Map<String, dynamic> data,
  }) async {
    final loginKey = (data['loginKey'] ?? '').toString().trim();
    final name = (data['name'] ?? '').toString().trim();
    final status = _normalizeStatus(data['status']);
    final emailLower = (data['emailLower'] ?? data['email'] ?? '').toString().trim().toLowerCase();

    await _db
        .collection('schools')
        .doc(_teachersSchoolId)
        .collection('teacher_directory')
        .doc(teacherId)
        .set({
      'teacherId': teacherId,
      'schoolId': _teachersSchoolId,
      if (loginKey.isNotEmpty) 'loginKey': loginKey,
      if (name.isNotEmpty) 'name': name,
      'status': status,
      'statusLower': status,
      'statusLabel': _statusLabel(status),
      if (emailLower.isNotEmpty) 'emailLower': emailLower,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ------------------------------------------------------------
  //  Resolve teachers schoolId
  // ------------------------------------------------------------
  Future<void> _resolveTeachersSchoolId() async {
    // 1) PRIORIDAD: si el usuario tiene schoolId en /users, úsalo para evitar permission-denied
    try {
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        DocumentSnapshot<Map<String, dynamic>> u = await _db.collection('users').doc(uid).get();
        if (!u.exists) {
          u = await _db.collection('Users').doc(uid).get();
        }

        final data = u.data();
        if (data != null) {
          final enabled = (data['enabled'] != false);
          final role = (data['role'] ?? '').toString().toLowerCase();
          final sid = (data['schoolId'] ?? '').toString().trim();

          if (enabled && sid.isNotEmpty && role != 'superadmin') {
            setState(() {
              _teachersSchoolId = sid;
              _teachers = [];
            });
            await _loadTeachersOnce();
            return;
          }
        }
      }
    } catch (_) {}

    // 2) Fallback por tu normalización vieja
    if (_schoolIdPrimary == _schoolIdAlt) {
      await _loadTeachersOnce();
      return;
    }

    setState(() => _loading = true);
    try {
      final q1 = await _db
          .collection('schools')
          .doc(_schoolIdPrimary)
          .collection('teachers')
          .limit(1)
          .get();

      final q2 = await _db
          .collection('schools')
          .doc(_schoolIdAlt)
          .collection('teachers')
          .limit(1)
          .get();

      final primaryHas = q1.docs.isNotEmpty;
      final altHas = q2.docs.isNotEmpty;

      String chosen = _schoolIdPrimary;
      if (!primaryHas && altHas) chosen = _schoolIdAlt;

      if (mounted) {
        setState(() {
          _teachersSchoolId = chosen;
          _teachers = [];
        });
      }
    } catch (_) {
      // fallback: primary
    } finally {
      if (mounted) setState(() => _loading = false);
    }

    await _loadTeachersOnce();
  }

  // ------------------------------------------------------------
  //  Catalogs: Grados + Asignaturas
  // ------------------------------------------------------------
  Future<void> _loadCatalogsOnce() async {
    setState(() => _loading = true);
    try {
      await Future.wait([
        _loadGradesOnce(),
        _loadSubjectsOnce(),
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadGradesOnce() async {
    try {
      for (final sid in _catalogSchoolIds) {
        final gradesSnap = await _db.collection('schools').doc(sid).collection('grados').get();
        final names = gradesSnap.docs
            .map((d) => (d.data()['name'] ?? d.id).toString().trim())
            .where((s) => s.isNotEmpty)
            .toSet();
        if (names.isNotEmpty) _gradesCache[sid] = names;
      }
      _recomputeGradesFromCache();
    } catch (_) {}
  }

  String _subjectNameFromMap(Map<String, dynamic> m, String fallbackId) {
    return (m['name'] ??
            m['title'] ??
            m['nombre'] ??
            m['asignatura'] ??
            m['materia'] ??
            fallbackId)
        .toString()
        .trim();
  }

  Future<Set<String>> _fetchSubjectsForSchoolId(String sid) async {
    final out = <String>{};

    // 0) campos dentro del doc schools/{sid}
    try {
      final doc = await _db.collection('schools').doc(sid).get();
      final data = doc.data() ?? {};
      out.addAll(_normalizeStringList(data['subjects']).map((e) => e.trim()));
      out.addAll(_normalizeStringList(data['asignaturas']).map((e) => e.trim()));
      out.removeWhere((e) => e.isEmpty);
    } catch (_) {}

    // 1) subcolecciones dentro de schools/{sid}/(...)
    for (final col in _subjectCollectionsCandidates) {
      try {
        final snap = await _db.collection('schools').doc(sid).collection(col).limit(300).get();
        for (final d in snap.docs) {
          final name = _subjectNameFromMap(d.data(), d.id);
          if (name.isNotEmpty) out.add(name);
        }
      } catch (_) {}
    }

    // 2) top-level (si existiera): /subjects, /asignaturas, etc. filtrando por schoolId...
    for (final col in _subjectCollectionsCandidates) {
      for (final f in _topLevelSchoolFieldsToTry) {
        try {
          final snap = await _db.collection(col).where(f, isEqualTo: sid).limit(300).get();
          for (final d in snap.docs) {
            final name = _subjectNameFromMap(d.data(), d.id);
            if (name.isNotEmpty) out.add(name);
          }
        } catch (_) {}
      }
    }

    out.removeWhere((e) => e.trim().isEmpty);
    return out;
  }

  Future<void> _loadSubjectsOnce() async {
    try {
      for (final sid in _catalogSchoolIds) {
        final merged = await _fetchSubjectsForSchoolId(sid);
        if (merged.isNotEmpty) _subjectsCache[sid] = merged;
      }
      _recomputeSubjectsFromCache();
    } catch (_) {}
  }

  void _listenCatalogsRealtime() {
    for (final s in _catalogSubs) {
      s.cancel();
    }
    _catalogSubs.clear();

    for (final sid in _catalogSchoolIds) {
      final schoolDoc = _db.collection('schools').doc(sid);

      _catalogSubs.add(
        schoolDoc.snapshots().listen((snap) {
          if (!mounted) return;
          try {
            final data = snap.data();
            if (data == null) return;

            final fieldsSubjects = <String>{
              ..._normalizeStringList(data['subjects']),
              ..._normalizeStringList(data['asignaturas']),
            }.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();

            if (fieldsSubjects.isNotEmpty) {
              _subjectsCache[sid] = {...(_subjectsCache[sid] ?? <String>{}), ...fieldsSubjects};
              _recomputeSubjectsFromCache();
            }

            final fieldsGrades = <String>{
              ..._normalizeStringList(data['grades']),
              ..._normalizeStringList(data['grados']),
            }.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();

            if (fieldsGrades.isNotEmpty) {
              _gradesCache[sid] = {...(_gradesCache[sid] ?? <String>{}), ...fieldsGrades};
              _recomputeGradesFromCache();
            }
          } catch (_) {}
        }),
      );

      _catalogSubs.add(
        schoolDoc.collection('grados').snapshots().listen((snap) {
          if (!mounted) return;
          try {
            final set = snap.docs
                .map((d) => (d.data()['name'] ?? d.id).toString().trim())
                .where((s) => s.isNotEmpty)
                .toSet();

            if (set.isEmpty) return;
            _gradesCache[sid] = set;
            _recomputeGradesFromCache();
          } catch (_) {}
        }),
      );

      for (final col in _subjectCollectionsCandidates) {
        _catalogSubs.add(
          schoolDoc.collection(col).snapshots().listen((snap) {
            if (!mounted) return;
            try {
              final set = snap.docs
                  .map((d) => _subjectNameFromMap(d.data(), d.id))
                  .where((s) => s.isNotEmpty)
                  .toSet();

              if (set.isEmpty) return;
              _subjectsCache[sid] = {...(_subjectsCache[sid] ?? <String>{}), ...set};
              _recomputeSubjectsFromCache();
            } catch (_) {}
          }),
        );
      }
    }
  }

  // ------------------------------------------------------------
  //  Teachers CRUD (SOLO gestión)
  // ------------------------------------------------------------
  Future<void> _loadTeachersOnce() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _db
            .collection('schools')
            .doc(_teachersSchoolId)
            .collection('teachers')
            .orderBy('createdAt', descending: true)
            .get();
      } catch (_) {
        snap = await _db.collection('schools').doc(_teachersSchoolId).collection('teachers').get();
      }

      final list = snap.docs.map((d) {
        final m = d.data();
        m['__id'] = d.id;
        return m;
      }).toList();

      if (!mounted) return;
      setState(() => _teachers = list);
    } catch (_) {
      if (!mounted) return;
      setState(() => _teachers = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredTeachers {
    final q = _search.trim().toLowerCase();
    final selected = _filterSubject;

    return _teachers.where((t) {
      final status = _normalizeStatus(t['status']);
      if (_filterStatus != null && _filterStatus!.isNotEmpty) {
        if (status != _filterStatus) return false;
      }

      if (selected != null && selected.isNotEmpty) {
        if (!_teacherSubjects(t).contains(selected)) return false;
      }
      if (q.isEmpty) return true;

      final name = (t['name'] ?? '').toString().toLowerCase();
      final phone = (t['phone'] ?? '').toString().toLowerCase();
      final loginKey = (t['loginKey'] ?? '').toString().toLowerCase();
      final email = (t['emailLower'] ?? t['email'] ?? '').toString().toLowerCase();

      final gradesText = _teacherGrades(t).join(', ').toLowerCase();
      final subjectsText = _teacherSubjects(t).join(', ').toLowerCase();

      return name.contains(q) ||
          phone.contains(q) ||
          loginKey.contains(q) ||
          email.contains(q) ||
          gradesText.contains(q) ||
          subjectsText.contains(q);
    }).toList();
  }

  Future<List<String>?> _openMultiSelectDialog({
    required String title,
    required List<String> options,
    required List<String> initialSelected,
    String emptyHint = 'No hay opciones disponibles.',
  }) async {
    final selected = initialSelected.toSet();
    String query = '';

    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, st) {
          final filtered = options.where((o) {
            if (query.trim().isEmpty) return true;
            return o.toLowerCase().contains(query.trim().toLowerCase());
          }).toList();

          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 520,
              height: 520,
              child: Column(
                children: [
                  if (options.length >= 10)
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Buscar...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => st(() => query = v),
                    ),
                  if (options.length >= 10) const SizedBox(height: 10),
                  Expanded(
                    child: options.isEmpty
                        ? Center(child: Text(emptyHint))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final item = filtered[i];
                              final isOn = selected.contains(item);
                              return CheckboxListTile(
                                value: isOn,
                                title: Text(item),
                                onChanged: (v) {
                                  st(() {
                                    if (v == true) {
                                      selected.add(item);
                                    } else {
                                      selected.remove(item);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () {
                  st(() {
                    selected
                      ..clear()
                      ..addAll(options);
                  });
                },
                child: const Text('Seleccionar todo'),
              ),
              ElevatedButton(
                onPressed: () {
                  final out = selected.toList()
                    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                  Navigator.pop(ctx, out);
                },
                child: const Text('Listo'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openEditDialog({required Map<String, dynamic> teacher}) async {
    final nombreCtrl = TextEditingController(text: (teacher['name'] ?? '').toString());
    _attachNameFormatter(nombreCtrl);

    final nameInputFormatters = <TextInputFormatter>[
      FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÁÉÍÓÚÜÑáéíóúüñ\s]")),
      LengthLimitingTextInputFormatter(80),
    ];

    final emailCtrl = TextEditingController(
      text: (teacher['email'] ?? '').toString().trim(),
    );

    List<String> selectedGrades = _teacherGrades(teacher);
    List<String> selectedSubjects = _teacherSubjects(teacher);

    String dialCode = (teacher['phoneDialCode'] ?? '+1').toString();
    if (!_dialCodes.contains(dialCode)) dialCode = '+1';

    final phoneLocalCtrl = TextEditingController(text: (teacher['phoneLocal'] ?? '').toString().trim());

    final rawPhone = (teacher['phone'] ?? '').toString().trim();
    if (phoneLocalCtrl.text.isEmpty && rawPhone.startsWith('+') && rawPhone.length > 2) {
      for (final dc in _dialCodes) {
        if (rawPhone.startsWith(dc)) {
          dialCode = dc;
          phoneLocalCtrl.text = rawPhone.substring(dc.length).replaceAll(RegExp(r'\D'), '');
          break;
        }
      }
    }

    String status = _normalizeStatus(teacher['status'] ?? _statusPending);

    await showDialog<void>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Editar maestro'),
        content: StatefulBuilder(
          builder: (ctx, st) => SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nombreCtrl,
                    inputFormatters: nameInputFormatters,
                    keyboardType: TextInputType.name,
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo',
                      border: OutlineInputBorder(),
                      hintText: 'Ej: Juan Pérez',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo (referencia)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                      hintText: 'Ej: profe@gmail.com',
                    ),
                  ),
                  const SizedBox(height: 12),

                  InkWell(
                    onTap: () async {
                      final picked = await _openMultiSelectDialog(
                        title: 'Selecciona los grados',
                        options: _availableGrades,
                        initialSelected: selectedGrades,
                        emptyHint: 'Aún no hay grados configurados. Ve a "Grados" y agrega.',
                      );
                      if (picked == null) return;
                      st(() => selectedGrades = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Grados',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.arrow_drop_down),
                      ),
                      child: Text(
                        selectedGrades.isEmpty ? 'Seleccionar grados' : '${selectedGrades.length} seleccionado(s)',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  InkWell(
                    onTap: () async {
                      final picked = await _openMultiSelectDialog(
                        title: 'Selecciona las asignaturas',
                        options: _availableSubjects,
                        initialSelected: selectedSubjects,
                        emptyHint: 'Aún no hay asignaturas configuradas. Ve a "Asignaturas" y agrega.',
                      );
                      if (picked == null) return;
                      st(() => selectedSubjects = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Asignaturas',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.arrow_drop_down),
                      ),
                      child: Text(
                        selectedSubjects.isEmpty ? 'Seleccionar asignaturas' : '${selectedSubjects.length} seleccionado(s)',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      SizedBox(
                        width: 140,
                        child: DropdownButtonFormField<String>(
                          value: dialCode,
                          items: _dialCodes.map((dc) => DropdownMenuItem(value: dc, child: Text(dc))).toList(),
                          onChanged: (v) => st(() => dialCode = v ?? dialCode),
                          decoration: const InputDecoration(
                            labelText: 'Código',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: phoneLocalCtrl,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(15),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Número',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.phone),
                            hintText: 'Ej: 8091234567',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    value: status,
                    items: const [
                      DropdownMenuItem(value: _statusPending, child: Text('Pendiente')),
                      DropdownMenuItem(value: _statusActive, child: Text('Activo')),
                      DropdownMenuItem(value: _statusBlocked, child: Text('Bloqueado')),
                    ],
                    onChanged: (v) => st(() => status = v ?? status),
                    decoration: const InputDecoration(
                      labelText: 'Estado',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: TextEditingController(text: (teacher['loginKey'] ?? '—').toString()),
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Usuario (loginKey)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline),
                      helperText: 'El docente se registra solo. Aquí solo gestionas.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final rawName = nombreCtrl.text;

              if (rawName.trim().isEmpty) {
                _snack('Escribe el Nombre completo.');
                return;
              }

              final emailRaw = emailCtrl.text.trim();
              final email = emailRaw.toLowerCase();
              final emailOk = email.isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
              if (!emailOk) {
                _snack('Correo inválido.');
                return;
              }

              final teacherId = (teacher['__id'] ?? '').toString().trim();
              if (teacherId.isEmpty) {
                _snack('No se encontró el ID del maestro.');
                return;
              }

              setState(() => _loading = true);
              try {
                final safeName = _titleCasePreserveSpaces(rawName).trim();

                final gradesFinal = selectedGrades
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toSet()
                    .toList()
                  ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

                final subjectsFinal = selectedSubjects
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toSet()
                    .toList()
                  ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

                final phoneLocal = phoneLocalCtrl.text.trim();
                final phoneFull = phoneLocal.isEmpty ? '' : '$dialCode$phoneLocal';

                final payload = <String, dynamic>{
                  'name': safeName,
                  'grade': gradesFinal.isNotEmpty ? gradesFinal.first : '',
                  'grades': gradesFinal,
                  'subjects': subjectsFinal,
                  'status': status,
                  'statusLower': status,
                  'statusLabel': _statusLabel(status),
                  'phone': phoneFull,
                  'phoneDialCode': dialCode,
                  'phoneLocal': phoneLocal,
                  if (email.isNotEmpty) 'email': email,
                  if (email.isNotEmpty) 'emailLower': email,
                  'updatedAt': FieldValue.serverTimestamp(),
                  'lastEditedAt': FieldValue.serverTimestamp(),
                };

                await _db
                    .collection('schools')
                    .doc(_teachersSchoolId)
                    .collection('teachers')
                    .doc(teacherId)
                    .set(payload, SetOptions(merge: true));

                // Best-effort: mantener directorio sincronizado (si lo usas)
                try {
                  await _upsertTeacherDirectoryFromData(teacherId: teacherId, data: {
                    ...teacher,
                    ...payload,
                  });
                } catch (_) {}

try {
  await _db
      .collection('schools')
      .doc(_teachersSchoolId)
      .collection('teachers_public')
      .doc(teacherId)
      .set({
        ...payload,
        'isActive': status == _statusActive,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
} catch (_) {}



                if (!mounted) return;
                setState(() {
                  final idx = _teachers.indexWhere((t) => t['__id'] == teacherId);
                  if (idx >= 0) _teachers[idx] = {..._teachers[idx], ...payload};
                });

                if (dlgCtx.mounted) Navigator.pop(dlgCtx);
              } catch (e) {
                _snack('Error: $e');
              } finally {
                if (mounted) setState(() => _loading = false);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _setTeacherStatus(String docId, String status) async {
  if (!mounted) return;
  setState(() => _loading = true);

  final normalized = _normalizeStatus(status);

  final payload = <String, dynamic>{
    'status': normalized,
    'statusLower': normalized,
    'statusLabel': _statusLabel(normalized),
    'statusChangedAt': FieldValue.serverTimestamp(),
    if (normalized == _statusActive) 'approvedAt': FieldValue.serverTimestamp(),

    // ✅ útil para login / queries
    'isActive': normalized == _statusActive,

    // ✅ timestamps generales
    'updatedAt': FieldValue.serverTimestamp(),
    'lastEditedAt': FieldValue.serverTimestamp(),
  };

  try {
    final schoolDoc = _db.collection('schools').doc(_teachersSchoolId);
    final batch = _db.batch();

    // schools/{sid}/teachers/{docId}
    batch.set(
      schoolDoc.collection('teachers').doc(docId),
      payload,
      SetOptions(merge: true),
    );

    // schools/{sid}/teacher_directory/{docId}
    batch.set(
      schoolDoc.collection('teacher_directory').doc(docId),
      payload,
      SetOptions(merge: true),
    );

    // schools/{sid}/teachers_public/{docId}
    batch.set(
      schoolDoc.collection('teachers_public').doc(docId),
      payload,
      SetOptions(merge: true),
    );

    await batch.commit();

    if (!mounted) return;
    setState(() {
      final idx = _teachers.indexWhere((t) => t['__id'] == docId);
      if (idx >= 0) _teachers[idx] = {..._teachers[idx], ...payload};
    });
  } catch (e) {
    _snack('Error actualizando estado: $e');
  } finally {
    if (mounted) setState(() => _loading = false);
  }
}


  Future<void> _deleteTeacher(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Eliminar maestro'),
        content: const Text('¿Deseas eliminar este maestro?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(dlgCtx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;

    if (!mounted) return;
    setState(() => _loading = true);
    try {
      await _db.collection('schools').doc(_teachersSchoolId).collection('teachers').doc(docId).delete();

      // best-effort limpiar directorio
      try {
        await _db.collection('schools').doc(_teachersSchoolId).collection('teacher_directory').doc(docId).delete();
      } catch (_) {}

      if (!mounted) return;
      setState(() => _teachers.removeWhere((t) => t['__id'] == docId));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------------------------------------------------
  //  UI
  // ------------------------------------------------------------
  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final rows = _filteredTeachers;
    if (rows.isEmpty) {
      return const Center(child: Text('No hay maestros registrados todavía.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Card(
        elevation: 2,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 52,
            headingRowColor: MaterialStatePropertyAll(Colors.indigo.shade50),
            columns: const [
              DataColumn(label: Text('Nombre')),
              DataColumn(label: Text('Usuario')),
              DataColumn(label: Text('Grados')),
              DataColumn(label: Text('Teléfono')),
              DataColumn(label: Text('Asignaturas')),
              DataColumn(label: Text('Estado')),
              DataColumn(label: Text('Acciones')),
            ],
            rows: rows.map((t) {
              final id = (t['__id'] ?? '').toString();

              final grades = _teacherGrades(t);
              final gradesText = grades.isEmpty ? '—' : grades.join(', ');

              final subjects = _teacherSubjects(t);
              final subjectsText = subjects.isEmpty ? '—' : subjects.join(', ');

              final status = _normalizeStatus(t['status']);
              final phone = (t['phone'] ?? '—').toString();
              final loginKey = (t['loginKey'] ?? '—').toString();

              return DataRow(cells: [
                DataCell(Text((t['name'] ?? '—').toString())),
                DataCell(Text(loginKey)),
                DataCell(SizedBox(width: 220, child: Text(gradesText, overflow: TextOverflow.ellipsis))),
                DataCell(Text(phone)),
                DataCell(SizedBox(width: 360, child: Text(subjectsText, overflow: TextOverflow.ellipsis))),
                DataCell(
                  Chip(
                    label: Text(
                      _statusLabel(status),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    backgroundColor: _statusColor(status),
                  ),
                ),
                DataCell(Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Editar',
                      onPressed: () => _openEditDialog(teacher: t),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'delete') return _deleteTeacher(id);
                        if (v == 'approve') return _setTeacherStatus(id, _statusActive);
                        if (v == 'block') return _setTeacherStatus(id, _statusBlocked);
                        if (v == 'pending') return _setTeacherStatus(id, _statusPending);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'approve', child: Text('Aprobar (Activar)')),
                        PopupMenuItem(value: 'pending', child: Text('Marcar Pendiente')),
                        PopupMenuItem(value: 'block', child: Text('Bloquear')),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Eliminar', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  ],
                )),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _headerBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade900, Colors.indigo.shade700],
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.school, color: Colors.white),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Gestión de Maestros',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton.icon(
            onPressed: _loading ? null : _loadTeachersOnce,
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: const Text('Actualizar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: Colors.indigo.shade900,
        title: const Text('Maestros'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _loadTeachersOnce,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _headerBar(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Buscar por nombre, usuario, teléfono, correo, grados o asignaturas',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String?>(
                      value: _filterStatus,
                      hint: const Text('Estado'),
                      items: const [
                        DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                        DropdownMenuItem<String?>(value: _statusPending, child: Text('Pendiente')),
                        DropdownMenuItem<String?>(value: _statusActive, child: Text('Activo')),
                        DropdownMenuItem<String?>(value: _statusBlocked, child: Text('Bloqueado')),
                      ],
                      onChanged: (v) => setState(() => _filterStatus = v),
                    ),
                    const SizedBox(width: 12),
                    if (_availableSubjects.isNotEmpty)
                      DropdownButton<String?>(
                        value: (_filterSubject != null && _availableSubjects.contains(_filterSubject))
                            ? _filterSubject
                            : null,
                        hint: const Text('Asignatura'),
                        items: <DropdownMenuItem<String?>>[
                          const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
                          ..._availableSubjects.map((s) => DropdownMenuItem<String?>(value: s, child: Text(s))),
                        ],
                        onChanged: (v) => setState(() => _filterSubject = v),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }
}
