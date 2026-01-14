import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
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

  // Si tus functions están en otra región, usa:
  // final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  String _search = '';
  String? _filterSubject;
  bool _loading = false;

  List<Map<String, dynamic>> _teachers = [];

  // Catálogos (de A_asignaturas y A_grados)
  List<String> _availableSubjects = [];
  List<String> _availableGrades = [];

  // Por si A_grados usa otra normalización
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
  //  LoginKey robusto (sin acentos) + único
  // ------------------------------------------------------------
  String _stripAccents(String s) {
    const from = 'ÁÀÂÄÃáàâäãÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÖÕóòôöõÚÙÛÜúùûüÑñ';
    const to = 'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuNn';
    for (int i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    return s;
  }

  String _normalizeTeacherLoginKey(String name) {
    // “Juan Pérez” -> “juan perez”
    final cleaned = _stripAccents(name).trim().toLowerCase();
    return cleaned.replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<String> _makeUniqueLoginKey(String base) async {
    var candidate = base;

    for (int i = 0; i < 20; i++) {
      final snap = await _db
          .collection('schools')
          .doc(_teachersSchoolId)
          .collection('teachers')
          .where('loginKey', isEqualTo: candidate)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) return candidate;

      // si existe, agrega 2 dígitos (ej: "juan perez 27")
      final n = _rng().nextInt(90) + 10;
      candidate = '$base $n';
    }

    // fallback súper raro
    return '${base}_${DateTime.now().millisecondsSinceEpoch % 10000}';
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
    final list = _normalizeStringList(t['grades']);
    if (list.isNotEmpty) return list;

    final g = (t['grade'] ?? '').toString().trim();
    if (g.isEmpty) return const [];
    if (g.contains(',')) return _parseCommaList(g);
    return [g];
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
    final re = RegExp(r'\S+|\s+'); // palabras o espacios

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

  Random _rng() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  String _generateTempPassword({int length = 10}) {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789@#%';
    final r = _rng();
    return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
  }

  String _sha256(String input) => sha256.convert(utf8.encode(input)).toString();

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------------
  //  Resolve teachers schoolId
  // ------------------------------------------------------------
  Future<void> _resolveTeachersSchoolId() async {
    if (_schoolIdPrimary == _schoolIdAlt) {
      await _loadTeachersOnce();
      return;
    }

    setState(() => _loading = true);
    try {
      final q1 = await _db.collection('escuelas').doc(_schoolIdPrimary).collection('teachers').limit(1).get();
      final q2 = await _db.collection('schools').doc(_schoolIdAlt).collection('teachers').limit(1).get();

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
  //  Cloud Function: crear cuenta de maestro (Firebase Auth)
  // ------------------------------------------------------------
  Future<Map<String, dynamic>> _createTeacherAuthAccount({
    required String teacherName,
    required String loginKey,
    required String tempPassword,
  }) async {
    final callable = _functions.httpsCallable('createTeacherAccount');
    final res = await callable.call(<String, dynamic>{
      'schoolId': _teachersSchoolId,
      'teacherName': teacherName.trim(),
      'loginKey': loginKey,
      'tempPassword': tempPassword,
    });

    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> _showCredentialsDialog({
    required String userLoginKey,
    required String email,
    required String tempPassword,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Acceso del maestro creado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Comparte estos datos con el maestro:'),
            const SizedBox(height: 12),
            SelectableText('Usuario: $userLoginKey'),
            const SizedBox(height: 6),
            SelectableText('Correo (interno): $email'),
            const SizedBox(height: 6),
            SelectableText('Contraseña provisional: $tempPassword'),
            const SizedBox(height: 12),
            const Text(
              'Recomendación: que el maestro cambie su contraseña al primer inicio.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text: 'Usuario: $userLoginKey\nCorreo: $email\nClave: $tempPassword',
                ),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Copiar y cerrar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  //  Catalogs: Grados (A_grados) + Asignaturas (A_asignaturas)
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

    // 2) top-level (si existiera): /subjects, /asignaturas, etc. filtrando por schoolId/escuelaId...
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
      final schoolDoc = _db.collection('escuelas').doc(sid);

      // doc fields (subjects/asignaturas) y grades/grados
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

      // grades realtime
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

      // subjects realtime: escuchamos varias subcolecciones candidatas
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
  //  Teachers CRUD
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
      if (selected != null && selected.isNotEmpty) {
        if (!_teacherSubjects(t).contains(selected)) return false;
      }
      if (q.isEmpty) return true;

      final name = (t['name'] ?? '').toString().toLowerCase();
      final phone = (t['phone'] ?? '').toString().toLowerCase();
      final email = (t['email'] ?? '').toString().toLowerCase();

      final gradesText = _teacherGrades(t).join(', ').toLowerCase();
      final subjectsText = _teacherSubjects(t).join(', ').toLowerCase();

      return name.contains(q) ||
          phone.contains(q) ||
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

  Future<void> _openEditDialog({Map<String, dynamic>? teacher}) async {
    final isNew = teacher == null;

    final nombreCtrl = TextEditingController(text: (teacher?['name'] ?? '').toString());
    _attachNameFormatter(nombreCtrl);

    // ✅ letras + espacios (incluye acentos/ñ). SIN números/signos.
    final nameInputFormatters = <TextInputFormatter>[
      FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÁÉÍÓÚÜÑáéíóúüñ\s]")),
      LengthLimitingTextInputFormatter(80),
    ];

    // Multi
    List<String> selectedGrades = teacher != null ? _teacherGrades(teacher) : [];
    List<String> selectedSubjects = teacher != null ? _teacherSubjects(teacher) : [];

    // Teléfono bonito
    String dialCode = (teacher?['phoneDialCode'] ?? '+1').toString();
    if (!_dialCodes.contains(dialCode)) dialCode = '+1';

    final phoneLocalCtrl = TextEditingController(text: (teacher?['phoneLocal'] ?? '').toString().trim());

    // compat si solo existe phone como "+1XXXXXXXX"
    final rawPhone = (teacher?['phone'] ?? '').toString().trim();
    if (phoneLocalCtrl.text.isEmpty && rawPhone.startsWith('+') && rawPhone.length > 2) {
      for (final dc in _dialCodes) {
        if (rawPhone.startsWith(dc)) {
          dialCode = dc;
          phoneLocalCtrl.text = rawPhone.substring(dc.length).replaceAll(RegExp(r'\D'), '');
          break;
        }
      }
    }

    String status = (teacher?['status'] ?? 'pending').toString();

    // Contraseña provisional (solo al crear)
    String tempPasswordPlain = _generateTempPassword(length: 10);

    await showDialog<void>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text(isNew ? 'Crear maestro' : 'Editar maestro'),
        content: StatefulBuilder(
          builder: (ctx, st) => SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ------------------ NOMBRE ------------------
                  TextField(
                    controller: nombreCtrl,
                    inputFormatters: nameInputFormatters,
                    keyboardType: TextInputType.name,
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo',
                      border: OutlineInputBorder(),
                      hintText: 'Ej: Juan Pérez',
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ------------------ CONTRASEÑA PROVISIONAL (solo crear) ------------------
                  if (isNew) ...[
                    TextField(
                      readOnly: true,
                      controller: TextEditingController(text: tempPasswordPlain),
                      decoration: InputDecoration(
                        labelText: 'Contraseña provisional',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: Wrap(
                          spacing: 0,
                          children: [
                            IconButton(
                              tooltip: 'Regenerar',
                              icon: const Icon(Icons.refresh),
                              onPressed: () {
                                st(() => tempPasswordPlain = _generateTempPassword(length: 10));
                              },
                            ),
                            IconButton(
                              tooltip: 'Copiar',
                              icon: const Icon(Icons.copy),
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: tempPasswordPlain));
                                if (!mounted) return;
                                _snack('Contraseña copiada');
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ------------------ GRADOS (popup multi-check) ------------------
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

                  // ------------------ ASIGNATURAS (popup multi-check) ------------------
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

                  // ------------------ TELÉFONO BONITO ------------------
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

                  // ------------------ ESTADO ------------------
                  DropdownButtonFormField<String>(
                    value: status,
                    items: const [
                      DropdownMenuItem(value: 'pending', child: Text('Pendiente')),
                      DropdownMenuItem(value: 'active', child: Text('Activo')),
                      DropdownMenuItem(value: 'blocked', child: Text('Bloqueado')),
                    ],
                    onChanged: (v) => st(() => status = v ?? status),
                    decoration: const InputDecoration(
                      labelText: 'Estado',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  if (!isNew) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: TextEditingController(text: (teacher?['loginKey'] ?? '—').toString()),
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Usuario (loginKey)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: TextEditingController(text: (teacher?['email'] ?? '—').toString()),
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Correo del maestro',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
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

              if (isNew && rawName.trim().isEmpty) {
                _snack('Para crear el maestro, escribe el Nombre completo.');
                return;
              }

              setState(() => _loading = true);

              String? createdEmail;
              String? createdUid;
              String tempPasswordToShow = tempPasswordPlain;
              String createdLoginKeyToShow = '';

              try {
                final safeName = _titleCasePreserveSpaces(rawName).trim();

                // ✅ loginKey robusto y único (sin acentos)
                String loginKey;
                if (isNew) {
                  final base = _normalizeTeacherLoginKey(safeName);
                  loginKey = await _makeUniqueLoginKey(base);
                } else {
                  // al editar: conserva el loginKey si existe; si no existe, créalo
                  final existing = (teacher?['loginKey'] ?? '').toString().trim();
                  loginKey = existing.isNotEmpty ? existing : _normalizeTeacherLoginKey(safeName);
                }
                createdLoginKeyToShow = loginKey;

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
                  'loginKey': loginKey,

                  // compat + nuevo
                  'grade': gradesFinal.isNotEmpty ? gradesFinal.first : '',
                  'grades': gradesFinal,
                  'subjects': subjectsFinal,

                  'status': status,

                  'phone': phoneFull,
                  'phoneDialCode': dialCode,
                  'phoneLocal': phoneLocal,

                  'lastEditedAt': FieldValue.serverTimestamp(),
                };

                final existingDocId = teacher?['__id']?.toString();

                if (isNew) {
                  // 🔐 Creamos Auth con la contraseña generada (en Cloud Function)
                  final created = await _createTeacherAuthAccount(
                    teacherName: safeName,
                    loginKey: loginKey,
                    tempPassword: tempPasswordPlain,
                  );

                  createdEmail = (created['email'] ?? '').toString();
                  createdUid = (created['uid'] ?? '').toString();

                  if (createdUid == null || createdUid!.isEmpty) {
                    throw Exception('La Cloud Function no devolvió uid.');
                  }
                  if (createdEmail == null || createdEmail!.isEmpty) {
                    throw Exception('La Cloud Function no devolvió email.');
                  }

                  // si la function devolvió otra pass, usamos esa para mostrar
                  final fromFnPass = (created['tempPassword'] ?? '').toString().trim();
                  if (fromFnPass.isNotEmpty) tempPasswordToShow = fromFnPass;

                  payload['email'] = createdEmail;
                  payload['authUid'] = createdUid;
                  payload['mustChangePassword'] = true;
                  payload['createdByUid'] = _auth.currentUser?.uid;
                  payload['createdAt'] = FieldValue.serverTimestamp();

                  // Guardamos SOLO hash + last4 (seguro). No texto plano.
                  payload['tempPasswordHash'] = _sha256(tempPasswordToShow);
                  payload['tempPasswordLast4'] = tempPasswordToShow.length >= 4
                      ? tempPasswordToShow.substring(tempPasswordToShow.length - 4)
                      : tempPasswordToShow;
                  payload['tempPasswordSetAt'] = FieldValue.serverTimestamp();

                  // ✅ Guardar teacher con docId = authUid (evita desorden)
                  await _saveTeacher(payload, docId: createdUid);
                } else {
                  payload['updatedAt'] = FieldValue.serverTimestamp();

                  // ✅ En edición: NO cambies docId si ya existe. Si el doc era el uid, se conserva.
                  await _saveTeacher(payload, docId: existingDocId);
                }

                if (mounted) Navigator.pop(dlgCtx);

                // Mostrar credenciales SOLO al crear
                if (isNew && createdEmail != null && createdEmail!.isNotEmpty) {
                  await _showCredentialsDialog(
                    userLoginKey: createdLoginKeyToShow,
                    email: createdEmail!,
                    tempPassword: tempPasswordToShow,
                  );
                }
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

  Future<void> _saveTeacher(Map<String, dynamic> teacher, {String? docId}) async {
    final coll = _db.collection('schools').doc(_teachersSchoolId).collection('teachers');

    String id;
    if (docId == null || docId.isEmpty) {
      final ref = coll.doc();
      id = ref.id;
      await ref.set(teacher, SetOptions(merge: true));
    } else {
      id = docId;
      await coll.doc(id).set(teacher, SetOptions(merge: true));
    }

    final row = Map<String, dynamic>.from(teacher)..['__id'] = id;

    if (!mounted) return;
    setState(() {
      final idx = _teachers.indexWhere((t) => t['__id'] == id);
      if (idx >= 0) _teachers[idx] = row;
      else _teachers.insert(0, row);
    });
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
      if (!mounted) return;
      setState(() => _teachers.removeWhere((t) => t['__id'] == docId));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setTeacherStatus(String docId, String status) async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      await _db.collection('schools').doc(_teachersSchoolId).collection('teachers').doc(docId).update({
        'status': status,
        'statusChangedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() {
        final idx = _teachers.indexWhere((t) => t['__id'] == docId);
        if (idx >= 0) _teachers[idx]['status'] = status;
      });
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
      return const Center(child: Text('No hay maestros. Usa "Agregar maestro".'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Nombre')),
            DataColumn(label: Text('Grados')),
            DataColumn(label: Text('Correo')),
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

            final status = (t['status'] ?? '—').toString();
            final email = (t['email'] ?? '—').toString();
            final phone = (t['phone'] ?? '—').toString();

            return DataRow(cells: [
              DataCell(Text((t['name'] ?? '—').toString())),
              DataCell(SizedBox(width: 240, child: Text(gradesText, overflow: TextOverflow.ellipsis))),
              DataCell(SizedBox(width: 260, child: Text(email, overflow: TextOverflow.ellipsis))),
              DataCell(Text(phone)),
              DataCell(SizedBox(width: 360, child: Text(subjectsText, overflow: TextOverflow.ellipsis))),
              DataCell(Text(status)),
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
                      if (v == 'block') return _setTeacherStatus(id, 'blocked');
                      if (v == 'activate') return _setTeacherStatus(id, 'active');
                      if (v == 'pending') return _setTeacherStatus(id, 'pending');
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'activate', child: Text('Activar')),
                      PopupMenuItem(value: 'block', child: Text('Bloquear')),
                      PopupMenuItem(value: 'pending', child: Text('Pendiente')),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: const SizedBox.shrink(),
        leadingWidth: 0,
        title: const SizedBox.shrink(),
        backgroundColor: Colors.blue.shade900,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar por nombre, grado(s), asignatura(s), correo o teléfono',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                const SizedBox(width: 12),
                if (_availableSubjects.isNotEmpty)
                  DropdownButton<String?>(
                    value: (_filterSubject != null && _availableSubjects.contains(_filterSubject)) ? _filterSubject : null,
                    hint: const Text('Filtrar asignatura'),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
                      ..._availableSubjects.map((s) => DropdownMenuItem<String?>(value: s, child: Text(s))),
                    ],
                    onChanged: (v) => setState(() => _filterSubject = v),
                  ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.person_add),
                  label: const Text('Agregar maestro'),
                  onPressed: _loading ? null : () => _openEditDialog(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }
}
