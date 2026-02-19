import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

import 'estudiantes_detalle.dart';

class AEstudiantes extends StatefulWidget {
  final Escuela escuela;
  const AEstudiantes({Key? key, required this.escuela}) : super(key: key);

  @override
  State<AEstudiantes> createState() => _AEstudiantesState();
}

class _AEstudiantesState extends State<AEstudiantes> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Status (ES como fuente de verdad)
  static const String _statusActivo = 'activo';
  static const String _statusPendiente = 'pendiente';
  static const String _statusBloqueado = 'bloqueado';

  String _search = '';
  String? _filterGrade;
  String? _filterStatus;

  bool _loading = false;

  List<Map<String, dynamic>> _students = [];
  List<String> _availableGrades = [];

  late final String _schoolIdPrimary;
  late String _schoolIdResolved;

  @override
  void initState() {
    super.initState();
    _schoolIdPrimary = normalizeSchoolIdFromEscuela(widget.escuela);
    _schoolIdResolved = _schoolIdPrimary;

    _resolveSchoolIdFromUserThenLoad();
  }

  // -------------------------
  // Helpers
  // -------------------------
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  String _normalizeStatus(dynamic raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    if (s.isEmpty) return _statusActivo;

    // aceptamos EN y ES
    if (s == 'active') return _statusActivo;
    if (s == 'pending' || s == 'pending_approval') return _statusPendiente;
    if (s == 'blocked') return _statusBloqueado;

    if (s == _statusPendiente) return _statusPendiente;
    if (s == _statusBloqueado) return _statusBloqueado;
    return _statusActivo;
  }

  String _statusLabel(String s) {
    switch (_normalizeStatus(s)) {
      case _statusPendiente:
        return 'Pendiente';
      case _statusBloqueado:
        return 'Bloqueado';
      case _statusActivo:
      default:
        return 'Activo';
    }
  }

  Color _statusColor(String s) {
    switch (_normalizeStatus(s)) {
      case _statusPendiente:
        return Colors.orange.shade700;
      case _statusBloqueado:
        return Colors.red.shade700;
      case _statusActivo:
      default:
        return Colors.green.shade700;
    }
  }

  List<String> _normalizeStringList(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
  }

  String _pickString(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  String _studentNombre(Map<String, dynamic> s) {
    final full = _pickString(s, ['nombreCompleto', 'name', 'nombre', 'fullName']);
    if (full.isNotEmpty) return full;

    final nombres = _pickString(s, ['nombres', 'Nombres']);
    final apellidos = _pickString(s, ['apellidos', 'Apellidos', 'apellido', 'Apellido']);
    final armado = ('$nombres $apellidos').trim().replaceAll(RegExp(r'\s+'), ' ');
    return armado.isNotEmpty ? armado : 'Sin nombre';
  }

  String _studentGrado(Map<String, dynamic> s) {
    // compat: string en grado/Grado/grade
    final g = _pickString(s, ['grado', 'Grado', 'grade']);
    if (g.isNotEmpty) return g;

    // compat: lista en grados/grades
    final gl = _normalizeStringList(s['grados']);
    if (gl.isNotEmpty) return gl.first;
    final gel = _normalizeStringList(s['grades']);
    if (gel.isNotEmpty) return gel.first;

    return '';
  }

  // -------------------------
  // Resolve schoolId (evita permission-denied si user tiene schoolId)
  // -------------------------
  Future<void> _resolveSchoolIdFromUserThenLoad() async {
    setState(() => _loading = true);

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
            _schoolIdResolved = sid;
          }
        }
      }
    } catch (_) {
      // fallback silencioso
    }

    try {
      await Future.wait([
        _loadStudentsOnce(),
        _loadGradesOnce(),
      ]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------------
  // Data load
  // -------------------------
  Future<void> _loadStudentsOnce() async {
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _db
            .collection('schools')
            .doc(_schoolIdResolved)
            .collection('alumnos')
            .orderBy('createdAt', descending: true)
            .get();
      } catch (_) {
        snap = await _db.collection('schools').doc(_schoolIdResolved).collection('alumnos').get();
      }

      final list = snap.docs.map((d) {
        final m = d.data();
        m['__id'] = d.id;
        return m;
      }).toList();

      if (!mounted) return;
      setState(() => _students = list);

      // también extraemos grados desde alumnos (por si no hay en /grados)
      final gradeSet = <String>{};
      for (final s in list) {
        final g = _studentGrado(s).trim();
        if (g.isNotEmpty) gradeSet.add(g);
      }
      if (gradeSet.isNotEmpty) {
        final merged = {..._availableGrades, ...gradeSet}.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        setState(() => _availableGrades = merged);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _students = []);
    }
  }

  Future<void> _loadGradesOnce() async {
    try {
      final gradesSnap = await _db.collection('schools').doc(_schoolIdResolved).collection('grados').get();
      final names = gradesSnap.docs
          .map((d) => (d.data()['name'] ?? d.id).toString().trim())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (!mounted) return;

      final merged = {..._availableGrades, ...names}.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      setState(() => _availableGrades = merged);
    } catch (_) {}
  }

  // -------------------------
  // Update status
  // -------------------------
  Future<void> _setStudentStatus(String studentId, String status) async {
    final normalized = _normalizeStatus(status);
    final enabled = normalized != _statusBloqueado;

    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final schoolDoc = _db.collection('schools').doc(_schoolIdResolved);
      final batch = _db.batch();

      final payload = <String, dynamic>{
        'status': normalized, // ES
        'statusLower': normalized,
        'statusLabel': _statusLabel(normalized),
        'enabled': enabled,
        'statusAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // alumnos
      batch.set(
        schoolDoc.collection('alumnos').doc(studentId),
        payload,
        SetOptions(merge: true),
      );

      // best-effort alumnos_login (si existe doc con mismo id)
      batch.set(
        schoolDoc.collection('alumnos_login').doc(studentId),
        payload,
        SetOptions(merge: true),
      );

      await batch.commit();

      if (!mounted) return;
      setState(() {
        final idx = _students.indexWhere((s) => s['__id'] == studentId);
        if (idx >= 0) _students[idx] = {..._students[idx], ...payload};
      });
    } catch (e) {
      _snack('Error actualizando estado: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------------
  // Filtering (client-side)
  // -------------------------
  List<Map<String, dynamic>> get _filteredStudents {
    final q = _search.trim().toLowerCase();
    final gradeSel = (_filterGrade ?? '').trim();
    final statusSel = (_filterStatus ?? '').trim();

    return _students.where((s) {
      final st = _normalizeStatus(s['status']);
      if (statusSel.isNotEmpty && st != _normalizeStatus(statusSel)) return false;

      final g = _studentGrado(s);
      if (gradeSel.isNotEmpty && g.toLowerCase() != gradeSel.toLowerCase()) return false;

      if (q.isEmpty) return true;

      final nombre = _studentNombre(s).toLowerCase();
      final usuario = (s['usuario'] ?? '').toString().toLowerCase();
      final email = (s['emailLower'] ?? s['email'] ?? '').toString().toLowerCase();
      final matricula = (s['matricula'] ?? '').toString().toLowerCase();
      final grado = g.toLowerCase();
      final nombresKey = (s['nombresKey'] ?? '').toString().toLowerCase();
      final apellidosKey = (s['apellidosKey'] ?? '').toString().toLowerCase();
      final gradoKey = (s['gradoKey'] ?? '').toString().toLowerCase();

      return nombre.contains(q) ||
          usuario.contains(q) ||
          email.contains(q) ||
          matricula.contains(q) ||
          grado.contains(q) ||
          nombresKey.contains(q) ||
          apellidosKey.contains(q) ||
          gradoKey.contains(q);
    }).toList();
  }

  // -------------------------
  // UI
  // -------------------------
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
          const Icon(Icons.groups_2, color: Colors.white),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Estudiantes',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          TextButton.icon(
            onPressed: _loading
                ? null
                : () async {
                    setState(() => _loading = true);
                    try {
                      await Future.wait([_loadStudentsOnce(), _loadGradesOnce()]);
                    } finally {
                      if (mounted) setState(() => _loading = false);
                    }
                  },
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: const Text('Actualizar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final rows = _filteredStudents;
    if (rows.isEmpty) return const Center(child: Text('No hay alumnos registrados todavía.'));

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
              DataColumn(label: Text('Grado')),
              DataColumn(label: Text('Matrícula')),
              DataColumn(label: Text('Tutor')),
              DataColumn(label: Text('Estado')),
              DataColumn(label: Text('Acciones')),
            ],
            rows: rows.map((s) {
              final id = (s['__id'] ?? '').toString();
              final nombre = _studentNombre(s);
              final usuario = (s['usuario'] ?? '—').toString();
              final grado = _studentGrado(s);
              final matricula = (s['matricula'] ?? '—').toString();

              final tutor = (s['tutor'] is Map) ? (s['tutor'] as Map) : null;
              final tutorNombre = (tutor?['nombre'] ?? '').toString().trim();
              final tutorTelefono = (tutor?['telefono'] ?? '').toString().trim();
              final tutorTxt = tutorNombre.isNotEmpty
                  ? (tutorTelefono.isNotEmpty ? '$tutorNombre • $tutorTelefono' : tutorNombre)
                  : '—';

              final status = _normalizeStatus(s['status']);

              return DataRow(cells: [
                DataCell(Text(nombre)),
                DataCell(Text(usuario)),
                DataCell(Text(grado.isEmpty ? '—' : grado)),
                DataCell(Text(matricula)),
                DataCell(SizedBox(width: 220, child: Text(tutorTxt, overflow: TextOverflow.ellipsis))),
                DataCell(
                  Chip(
                    label: Text(
                      _statusLabel(status),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                    backgroundColor: _statusColor(status),
                  ),
                ),
                DataCell(Row(
                  children: [
                    IconButton(
                      tooltip: 'Ver detalle',
                      icon: const Icon(Icons.visibility),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EstudiantesDetalle(
                              escuela: widget.escuela,
                              studentId: id,
                            ),
                          ),
                        );
                      },
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'activate') return _setStudentStatus(id, _statusActivo);
                        if (v == 'pending') return _setStudentStatus(id, _statusPendiente);
                        if (v == 'block') return _setStudentStatus(id, _statusBloqueado);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'activate', child: Text('Activar')),
                        PopupMenuItem(value: 'pending', child: Text('Marcar Pendiente')),
                        PopupMenuItem(value: 'block', child: Text('Bloquear')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: Colors.indigo.shade900,
        title: const Text('Estudiantes'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading
                ? null
                : () async {
                    setState(() => _loading = true);
                    try {
                      await Future.wait([_loadStudentsOnce(), _loadGradesOnce()]);
                    } finally {
                      if (mounted) setState(() => _loading = false);
                    }
                  },
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
                          hintText: 'Buscar por nombre, usuario, correo, matrícula o grado',
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
                        DropdownMenuItem<String?>(value: _statusActivo, child: Text('Activo')),
                        DropdownMenuItem<String?>(value: _statusPendiente, child: Text('Pendiente')),
                        DropdownMenuItem<String?>(value: _statusBloqueado, child: Text('Bloqueado')),
                      ],
                      onChanged: (v) => setState(() => _filterStatus = v),
                    ),
                    const SizedBox(width: 12),
                    if (_availableGrades.isNotEmpty)
                      DropdownButton<String?>(
                        value: (_filterGrade != null && _availableGrades.contains(_filterGrade))
                            ? _filterGrade
                            : null,
                        hint: const Text('Grado'),
                        items: <DropdownMenuItem<String?>>[
                          const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                          ..._availableGrades.map((g) => DropdownMenuItem<String?>(value: g, child: Text(g))),
                        ],
                        onChanged: (v) => setState(() => _filterGrade = v),
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
/// ✅ Compat: si en algún lado llamas Estudiantes(...) no se rompe.
/// Puedes borrarlo luego cuando confirmes que ya nadie lo usa.
@Deprecated('Usa AEstudiantes')
class Estudiantes extends AEstudiantes {
  const Estudiantes({super.key, required super.escuela});
}
