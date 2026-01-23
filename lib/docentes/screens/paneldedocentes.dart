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
  const PaneldedocentesScreen({Key? key, required this.escuela})
      : super(key: key);

  @override
  State<PaneldedocentesScreen> createState() => _PaneldedocentesScreenState();
}

class _PaneldedocentesScreenState extends State<PaneldedocentesScreen> {
  static const Color primaryColor = Color.fromARGB(255, 255, 193, 7);
  static const Color secondaryColor = Color.fromARGB(255, 21, 101, 192);

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _teacherName = '';
  List<String> _teacherGrades = [];
  List<String> _teacherSubjects = [];

  List<String> _schoolGrades = [];
  List<String> _schoolSubjects = [];

  String? _selectedGrade;
  String? _selectedSubject;

  DocumentReference<Map<String, dynamic>>? _teacherRef;

  // ✅ school doc id: eduproapp_admin_ITVB9J7T
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
    _bootstrap();
  }

  // -------------------------
  // Helpers (listas / maps)
  // -------------------------
  List<String> _asStringListOrMapKeys(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (v is Map) {
      return v.keys
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
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
    return _asStringListOrMapKeys(data['grades']);
  }

  List<String> _readSubjects(Map<String, dynamic> data) {
    final a = _asStringListOrMapKeys(data['subjects']);
    if (a.isNotEmpty) return a;
    return _asStringListOrMapKeys(data['materias']);
  }

  // -------------------------
  // Boot
  // -------------------------
  Future<void> _bootstrap() async {
    debugPrint('SCHOOL DOC => $_schoolDocId');

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1) catálogos del colegio (fallback)
    await Future.wait([
      _loadSchoolGrades(),
      _loadSchoolSubjects(),
    ]);

    // 2) resolver docente por emailLower dentro del colegio
    await _resolveTeacherDocByEmail(user.email);

    debugPrint('TEACHER REF RESOLVED => ${_teacherRef?.path}');

    // 3) cargar datos del docente
    await _loadTeacherDataOnce();
  }

  // -------------------------
  // Catálogos del colegio
  // -------------------------
  Future<void> _loadSchoolGrades() async {
    try {
      final ref =
          _db.collection('schools').doc(_schoolDocId).collection('grados');

      Query<Map<String, dynamic>> q = ref.limit(400);
      // Si "order" no existe, el try/catch evita que se rompa.
      q = q.orderBy('order', descending: false);

      final snap = await q.get();

      final out = <String>{};
      for (final d in snap.docs) {
        final m = d.data();
        final name = (m['name'] ?? m['gradoKey'] ?? m['nombre'] ?? d.id)
            .toString()
            .trim();
        if (name.isNotEmpty) out.add(name);
      }

      final list = out.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (!mounted) return;
      setState(() => _schoolGrades = list);

      debugPrint('GRADOS PATH => ${ref.path}');
      debugPrint('GRADOS COUNT => ${list.length}');
    } catch (e) {
      debugPrint('ERROR _loadSchoolGrades => $e');
      // fallback SIN orderBy por si el campo no existe
      try {
        final ref =
            _db.collection('schools').doc(_schoolDocId).collection('grados');
        final snap = await ref.limit(400).get();

        final out = <String>{};
        for (final d in snap.docs) {
          final m = d.data();
          final name = (m['name'] ?? m['gradoKey'] ?? m['nombre'] ?? d.id)
              .toString()
              .trim();
          if (name.isNotEmpty) out.add(name);
        }

        final list = out.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        if (!mounted) return;
        setState(() => _schoolGrades = list);
      } catch (e2) {
        debugPrint('ERROR _loadSchoolGrades fallback => $e2');
      }
    }
  }

  Future<void> _loadSchoolSubjects() async {
    try {
      final ref =
          _db.collection('schools').doc(_schoolDocId).collection('subjects');

      final snap = await ref.orderBy('order', descending: false).limit(600).get();

      final out = <String>{};
      for (final d in snap.docs) {
        final m = d.data();
        final name = (m['name'] ?? m['nombre'] ?? d.id).toString().trim();
        if (name.isNotEmpty) out.add(name);
      }

      final list = out.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (!mounted) return;
      setState(() => _schoolSubjects = list);

      debugPrint('SUBJECTS PATH => ${ref.path}');
      debugPrint('SUBJECTS COUNT => ${list.length}');
    } catch (e) {
      debugPrint('ERROR _loadSchoolSubjects => $e');
    }
  }

  // -------------------------
  // Resolver docente
  // -------------------------
  Future<void> _resolveTeacherDocByEmail(String? email) async {
    if (email == null || email.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tu sesión no tiene email. Revisa el login.')),
      );
      return;
    }

    final emailRaw = email.trim();
    final emailLower = emailRaw.toLowerCase();
    final schoolId = _schoolDocId;

    Future<QuerySnapshot<Map<String, dynamic>>> _q(
      String col,
      String field,
      String value,
    ) {
      return _db
          .collection('schools')
          .doc(schoolId)
          .collection(col)
          .where(field, isEqualTo: value)
          .limit(1)
          .get();
    }

    // 1) teachers por emailLower
    var snap = await _q('teachers', 'emailLower', emailLower);
    if (snap.docs.isNotEmpty) {
      _teacherRef = snap.docs.first.reference;
      return;
    }

    // 2) teachers por email exacto
    snap = await _q('teachers', 'email', emailRaw);
    if (snap.docs.isNotEmpty) {
      _teacherRef = snap.docs.first.reference;
      return;
    }

    // 3) teacher_directory por emailLower
    snap = await _q('teacher_directory', 'emailLower', emailLower);
    if (snap.docs.isNotEmpty) {
      _teacherRef = snap.docs.first.reference;
      return;
    }

    // 4) teacher_directory por email exacto
    snap = await _q('teacher_directory', 'email', emailRaw);
    if (snap.docs.isNotEmpty) {
      _teacherRef = snap.docs.first.reference;
      return;
    }

    // 5) teachers_public por emailLower (último recurso)
    snap = await _q('teachers_public', 'emailLower', emailLower);
    if (snap.docs.isNotEmpty) {
      _teacherRef = snap.docs.first.reference;
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'No encontré al docente.\n'
          'schoolId: $schoolId\n'
          'email: $emailLower',
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<DocumentReference<Map<String, dynamic>>?> _resolveRealTeacherRefFromPublic(
    Map<String, dynamic> publicData,
  ) async {
    final schoolId = _schoolDocId;

    // Caso ideal: public guarda teacherId
    final teacherId =
        (publicData['teacherId'] ?? publicData['teacherDocId'] ?? '')
            .toString()
            .trim();
    if (teacherId.isNotEmpty) {
      final ref = _db
          .collection('schools')
          .doc(schoolId)
          .collection('teachers')
          .doc(teacherId);
      final snap = await ref.get();
      if (snap.exists) return ref;
    }

    // Fallback: buscar en teachers por emailLower
    final emailLower = (publicData['emailLower'] ?? publicData['email'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (emailLower.isNotEmpty) {
      final q = await _db
          .collection('schools')
          .doc(schoolId)
          .collection('teachers')
          .where('emailLower', isEqualTo: emailLower)
          .limit(1)
          .get();

      if (q.docs.isNotEmpty) return q.docs.first.reference;
    }

    return null;
  }

  // -------------------------
  // Cargar docente
  // -------------------------
  Future<void> _loadTeacherDataOnce() async {
    if (_teacherRef == null) return;

    try {
      debugPrint('DOCENTE REF => ${_teacherRef!.path}');

      final snap = await _teacherRef!.get();
      var data = snap.data();
      if (data == null) {
        debugPrint('DOCENTE DATA => null');
        return;
      }

      debugPrint('DOCENTE RAW KEYS => ${data.keys.toList()}');

      // ✅ Si cayó en teachers_public, intenta ir al doc real
      if (snap.reference.parent.id == 'teachers_public') {
        final realRef = await _resolveRealTeacherRefFromPublic(data);
        if (realRef != null) {
          _teacherRef = realRef;
          final realSnap = await realRef.get();
          final realData = realSnap.data();
          if (realData != null) {
            data = realData;
            debugPrint('DOCENTE REAL REF => ${realRef.path}');
            debugPrint('DOCENTE REAL KEYS => ${data.keys.toList()}');
          }
        }
      }

      final name = _readName(data);
      final grados = _readGrades(data);
      final subjects = _readSubjects(data);

      // opciones finales (si docente no trae listas, usa catálogos)
      final gradesOptions = grados.isNotEmpty ? grados : _schoolGrades;
      final subjectOptions = subjects.isNotEmpty ? subjects : _schoolSubjects;

      // selección inicial
      final nextGrade = gradesOptions.isNotEmpty
          ? ((_selectedGrade != null && gradesOptions.contains(_selectedGrade))
              ? _selectedGrade
              : gradesOptions.first)
          : null;

      final nextSubject = subjectOptions.isNotEmpty
          ? ((_selectedSubject != null &&
                  subjectOptions.contains(_selectedSubject))
              ? _selectedSubject
              : subjectOptions.first)
          : null;

      if (!mounted) return;
      setState(() {
        _teacherName = name;
        _teacherGrades = grados;
        _teacherSubjects = subjects;
        _selectedGrade = nextGrade;
        _selectedSubject = nextSubject;
      });

      debugPrint(
          'DOCENTE FINAL => name=$name | grados=$grados | subjects=$subjects');
      debugPrint('UI SELECTED => grade=$_selectedGrade subject=$_selectedSubject');
    } catch (e) {
      debugPrint('ERROR _loadTeacherDataOnce => $e');
    }
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
        const SnackBar(
            content: Text('No hay sesión activa. Inicia sesión nuevamente.')),
      );
      return;
    }

    final schoolId = normalizeSchoolIdFromEscuela(widget.escuela);

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
  // UI
  // -------------------------
  @override
  Widget build(BuildContext context) {
    final nombreEscuela = (widget.escuela.nombre ?? 'EduPro').trim();

    final gradesOptions =
        _teacherGrades.isNotEmpty ? _teacherGrades : _schoolGrades;
    final subjectsOptions =
        _teacherSubjects.isNotEmpty ? _teacherSubjects : _schoolSubjects;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          nombreEscuela,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: secondaryColor,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Docente: ${_teacherName.isNotEmpty ? _teacherName : '--'}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),

                    // ✅ Grado
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Grado',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _selectedGrade,
                          hint: const Text('--'),
                          items: gradesOptions
                              .map((g) => DropdownMenuItem(
                                    value: g,
                                    child: Text(g,
                                        overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: gradesOptions.isEmpty
                              ? null
                              : (v) => setState(() => _selectedGrade = v),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ✅ Asignatura
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Asignatura',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _selectedSubject,
                          hint: const Text('--'),
                          items: subjectsOptions
                              .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s,
                                        overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: subjectsOptions.isEmpty
                              ? null
                              : (v) => setState(() => _selectedSubject = v),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                shape: const StadiumBorder(),
                              ),
                              onPressed: () => Navigator.pushNamed(
                                context,
                                '/evaluaciones',
                                arguments: widget.escuela,
                              ),
                              child: const Text('Evaluaciones'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: secondaryColor),
                                shape: const StadiumBorder(),
                                foregroundColor: secondaryColor,
                              ),
                              onPressed: _openCalendarioDocente,
                              child: const Text('Mi Calendario'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final crossAxisCount = width < 600 ? 2 : 4;
                  final childAspect = (width / crossAxisCount) / 180;

                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
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
                        'Períodos y Boletín',
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
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: secondaryColor.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: primaryColor),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
