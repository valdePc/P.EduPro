import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart'
    show normalizeSchoolIdFromEscuela;

import 'estudiantes_detalle.dart';

class AEstudiantes extends StatefulWidget {
  final Escuela escuela;
  const AEstudiantes({Key? key, required this.escuela}) : super(key: key);

  @override
  State<AEstudiantes> createState() => _AEstudiantesState();
}

class _AEstudiantesState extends State<AEstudiantes> {
  static const int _studentPageSize = 50;
  static const Color _blue = Color(0xFF1A237E);
  static const Color _ink = Color(0xFF17243A);
  static const Color _muted = Color(0xFF5C687A);
  static const Color _page = Color(0xFFF4F6FB);

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
  bool _loadingMore = false;
  bool _hasMoreStudents = false;
  int? _totalStudents;
  String? _lastStudentId;

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
    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  String _pickString(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  String _studentNombre(Map<String, dynamic> s) {
    final full = _pickString(s, [
      'nombreCompleto',
      'name',
      'nombre',
      'fullName',
    ]);
    if (full.isNotEmpty) return full;

    final nombres = _pickString(s, ['nombres', 'Nombres']);
    final apellidos = _pickString(s, [
      'apellidos',
      'Apellidos',
      'apellido',
      'Apellido',
    ]);
    final armado = ('$nombres $apellidos').trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
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
        DocumentSnapshot<Map<String, dynamic>> u =
            await _db.collection('users').doc(uid).get();
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
      await Future.wait([_loadStudentsOnce(), _loadGradesOnce()]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // -------------------------
  // Data load
  // -------------------------
  Future<void> _loadStudentsOnce() async {
    final studentsRef = _db
        .collection('schools')
        .doc(_schoolIdResolved)
        .collection('alumnos');
    final firstPageFuture =
        studentsRef
            .orderBy(FieldPath.documentId)
            .limit(_studentPageSize + 1)
            .get();
    final totalFuture = studentsRef.count().get().then<int?>(
      (snapshot) => snapshot.count,
      onError: (_) => null,
    );

    try {
      final snap = await firstPageFuture;
      final visibleDocs = snap.docs.take(_studentPageSize).toList();
      final list =
          visibleDocs.map((d) {
            final m = d.data();
            m['__id'] = d.id;
            return m;
          }).toList();

      if (!mounted) return;
      setState(() {
        _students = list;
        _lastStudentId = visibleDocs.isEmpty ? null : visibleDocs.last.id;
        _hasMoreStudents = snap.docs.length > _studentPageSize;
      });

      final total = await totalFuture;
      if (mounted) setState(() => _totalStudents = total);

      // también extraemos grados desde alumnos (por si no hay en /grados)
      final gradeSet = <String>{};
      for (final s in list) {
        final g = _studentGrado(s).trim();
        if (g.isNotEmpty) gradeSet.add(g);
      }
      if (gradeSet.isNotEmpty) {
        final merged =
            {..._availableGrades, ...gradeSet}.toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        setState(() => _availableGrades = merged);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _students = [];
        _lastStudentId = null;
        _hasMoreStudents = false;
      });
      _snack('No se pudo cargar la lista de estudiantes. Intenta actualizar.');
    }
  }

  Future<void> _loadMoreStudents() async {
    final lastId = _lastStudentId;
    if (_loadingMore || !_hasMoreStudents || lastId == null) return;

    setState(() => _loadingMore = true);
    try {
      final ref = _db
          .collection('schools')
          .doc(_schoolIdResolved)
          .collection('alumnos');
      final snap =
          await ref
              .orderBy(FieldPath.documentId)
              .startAfter([lastId])
              .limit(_studentPageSize + 1)
              .get();
      final visibleDocs = snap.docs.take(_studentPageSize).toList();
      final nextStudents =
          visibleDocs.map((doc) {
            final data = doc.data();
            data['__id'] = doc.id;
            return data;
          }).toList();

      if (!mounted) return;
      setState(() {
        _students = [..._students, ...nextStudents];
        _lastStudentId = visibleDocs.isEmpty ? lastId : visibleDocs.last.id;
        _hasMoreStudents = snap.docs.length > _studentPageSize;
      });
    } catch (_) {
      if (mounted)
        _snack('No se pudieron cargar más estudiantes. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _loadGradesOnce() async {
    try {
      final gradesSnap =
          await _db
              .collection('schools')
              .doc(_schoolIdResolved)
              .collection('grados')
              .get();
      final names =
          gradesSnap.docs
              .map((d) => (d.data()['name'] ?? d.id).toString().trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (!mounted) return;

      final merged =
          {..._availableGrades, ...names}.toList()
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
      if (statusSel.isNotEmpty && st != _normalizeStatus(statusSel))
        return false;

      final g = _studentGrado(s);
      if (gradeSel.isNotEmpty && g.toLowerCase() != gradeSel.toLowerCase())
        return false;

      if (q.isEmpty) return true;

      final nombre = _studentNombre(s).toLowerCase();
      final usuario = (s['usuario'] ?? '').toString().toLowerCase();
      final email =
          (s['emailLower'] ?? s['email'] ?? '').toString().toLowerCase();
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
  Widget _buildStudentCard(Map<String, dynamic> student) {
    final id = (student['__id'] ?? '').toString();
    final name = _studentNombre(student);
    final grade = _studentGrado(student);
    final status = _normalizeStatus(student['status']);
    final matricula = (student['matricula'] ?? '').toString().trim();
    final tutor = student['tutor'] is Map ? student['tutor'] as Map : null;
    final tutorName = (tutor?['nombre'] ?? '').toString().trim();
    final color = _statusColor(status);
    final initials =
        name
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .take(2)
            .map((part) => part[0].toUpperCase())
            .join();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFFE5EAF2)),
        boxShadow: [
          BoxShadow(
            color: _blue.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: const Color(0xFFE9EDFB),
                child: Text(
                  initials.isEmpty ? 'E' : initials,
                  style: const TextStyle(
                    color: _blue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusLabel(status),
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (grade.isNotEmpty)
                _studentInfoTag(Icons.school_outlined, grade),
              if (matricula.isNotEmpty)
                _studentInfoTag(Icons.badge_outlined, 'Matrícula $matricula'),
            ],
          ),
          if (tutorName.isNotEmpty) ...[
            const SizedBox(height: 11),
            Row(
              children: [
                const Icon(
                  Icons.support_agent_rounded,
                  size: 17,
                  color: _muted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Tutor: $tutorName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 11),
          const Divider(height: 1, color: Color(0xFFEEF1F6)),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => EstudiantesDetalle(
                              escuela: widget.escuela,
                              studentId: id,
                            ),
                      ),
                    ),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Ver perfil'),
                style: TextButton.styleFrom(foregroundColor: _blue),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: 'Cambiar estado',
                icon: const Icon(Icons.more_horiz_rounded, color: _muted),
                onSelected: (value) async {
                  if (value == 'activate')
                    return _setStudentStatus(id, _statusActivo);
                  if (value == 'pending')
                    return _setStudentStatus(id, _statusPendiente);
                  if (value == 'block')
                    return _setStudentStatus(id, _statusBloqueado);
                },
                itemBuilder:
                    (_) => const [
                      PopupMenuItem(value: 'activate', child: Text('Activar')),
                      PopupMenuItem(
                        value: 'pending',
                        child: Text('Marcar pendiente'),
                      ),
                      PopupMenuItem(value: 'block', child: Text('Bloquear')),
                    ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _studentInfoTag(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4FC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: _blue),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: _blue,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentsFooter(bool searchOrFilterActive, int visibleCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Column(
        children: [
          Text(
            _totalStudents == null
                ? 'Cargados ${_students.length} estudiantes · total no disponible'
                : 'Cargados ${_students.length} de $_totalStudents estudiantes',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
          ),
          if (searchOrFilterActive) ...[
            const SizedBox(height: 5),
            Text(
              '$visibleCount coincidencias visibles. La búsqueda y los filtros se aplican a los estudiantes cargados.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.4),
            ),
          ],
          if (_hasMoreStudents) ...[
            const SizedBox(height: 11),
            OutlinedButton.icon(
              onPressed: _loadingMore ? null : _loadMoreStudents,
              icon:
                  _loadingMore
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.expand_more_rounded),
              label: Text(_loadingMore ? 'Cargando…' : 'Cargar 50 más'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _blue,
                side: const BorderSide(color: Color(0xFFC9D1EA)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final rows = _filteredStudents;
    if (_students.isEmpty && MediaQuery.sizeOf(context).width >= 700) {
      return const Center(
        child: Text('No hay estudiantes registrados todavía.'),
      );
    }
    final searchOrFilterActive =
        _search.trim().isNotEmpty ||
        (_filterGrade ?? '').isNotEmpty ||
        (_filterStatus ?? '').isNotEmpty;

    if (MediaQuery.sizeOf(context).width < 700) {
      final itemCount = (rows.isEmpty ? 1 : rows.length) + 1;
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: 11),
        itemBuilder: (context, index) {
          if (rows.isEmpty) {
            if (index == 0) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 28,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE5EAF2)),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.person_search_rounded,
                      color: _blue,
                      size: 38,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _students.isEmpty
                          ? 'Aún no hay estudiantes registrados'
                          : 'No hay coincidencias con estos filtros',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Prueba con otra búsqueda o cambia los filtros.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted, height: 1.4),
                    ),
                  ],
                ),
              );
            }
            return _buildStudentsFooter(searchOrFilterActive, rows.length);
          }
          if (index == rows.length) {
            return _buildStudentsFooter(searchOrFilterActive, rows.length);
          }
          return _buildStudentCard(rows[index]);
        },
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 3, 14, 16),
      child: Column(
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFE5EAF2)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              scrollDirection: Axis.horizontal,
              child:
                  rows.isEmpty
                      ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No hay coincidencias entre los estudiantes cargados.',
                        ),
                      )
                      : DataTable(
                        headingRowHeight: 52,
                        headingRowColor: MaterialStatePropertyAll(
                          Colors.indigo.shade50,
                        ),
                        columns: const [
                          DataColumn(label: Text('Nombre')),
                          DataColumn(label: Text('Usuario')),
                          DataColumn(label: Text('Grado')),
                          DataColumn(label: Text('Matrícula')),
                          DataColumn(label: Text('Tutor')),
                          DataColumn(label: Text('Estado')),
                          DataColumn(label: Text('Acciones')),
                        ],
                        rows:
                            rows.map((s) {
                              final id = (s['__id'] ?? '').toString();
                              final nombre = _studentNombre(s);
                              final usuario = (s['usuario'] ?? '—').toString();
                              final grado = _studentGrado(s);
                              final matricula =
                                  (s['matricula'] ?? '—').toString();

                              final tutor =
                                  (s['tutor'] is Map)
                                      ? (s['tutor'] as Map)
                                      : null;
                              final tutorNombre =
                                  (tutor?['nombre'] ?? '').toString().trim();
                              final tutorTelefono =
                                  (tutor?['telefono'] ?? '').toString().trim();
                              final tutorTxt =
                                  tutorNombre.isNotEmpty
                                      ? (tutorTelefono.isNotEmpty
                                          ? '$tutorNombre • $tutorTelefono'
                                          : tutorNombre)
                                      : '—';

                              final status = _normalizeStatus(s['status']);

                              return DataRow(
                                cells: [
                                  DataCell(Text(nombre)),
                                  DataCell(Text(usuario)),
                                  DataCell(Text(grado.isEmpty ? '—' : grado)),
                                  DataCell(Text(matricula)),
                                  DataCell(
                                    SizedBox(
                                      width: 220,
                                      child: Text(
                                        tutorTxt,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Chip(
                                      label: Text(
                                        _statusLabel(status),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      backgroundColor: _statusColor(status),
                                    ),
                                  ),
                                  DataCell(
                                    Row(
                                      children: [
                                        IconButton(
                                          tooltip: 'Ver detalle',
                                          icon: const Icon(Icons.visibility),
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder:
                                                    (_) => EstudiantesDetalle(
                                                      escuela: widget.escuela,
                                                      studentId: id,
                                                    ),
                                              ),
                                            );
                                          },
                                        ),
                                        PopupMenuButton<String>(
                                          onSelected: (v) async {
                                            if (v == 'activate')
                                              return _setStudentStatus(
                                                id,
                                                _statusActivo,
                                              );
                                            if (v == 'pending')
                                              return _setStudentStatus(
                                                id,
                                                _statusPendiente,
                                              );
                                            if (v == 'block')
                                              return _setStudentStatus(
                                                id,
                                                _statusBloqueado,
                                              );
                                          },
                                          itemBuilder:
                                              (_) => const [
                                                PopupMenuItem(
                                                  value: 'activate',
                                                  child: Text('Activar'),
                                                ),
                                                PopupMenuItem(
                                                  value: 'pending',
                                                  child: Text(
                                                    'Marcar Pendiente',
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'block',
                                                  child: Text('Bloquear'),
                                                ),
                                              ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                      ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  Text(
                    _totalStudents == null
                        ? 'Cargados ${_students.length} estudiantes${searchOrFilterActive ? ' · ${rows.length} coincidencias visibles' : ''} · total no disponible'
                        : 'Cargados ${_students.length} de $_totalStudents estudiantes${searchOrFilterActive ? ' · ${rows.length} coincidencias visibles' : ''}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.blueGrey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (searchOrFilterActive) ...[
                    const SizedBox(height: 4),
                    Text(
                      'La búsqueda y los filtros se aplican a los registros cargados. Carga más para ampliar los resultados.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.blueGrey.shade600,
                      ),
                    ),
                  ],
                  if (_hasMoreStudents) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _loadingMore ? null : _loadMoreStudents,
                      icon:
                          _loadingMore
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.expand_more),
                      label: Text(_loadingMore ? 'Cargando…' : 'Cargar 50 más'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: const Text('Estudiantes'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed:
                _loading
                    ? null
                    : () async {
                      setState(() => _loading = true);
                      try {
                        await Future.wait([
                          _loadStudentsOnce(),
                          _loadGradesOnce(),
                        ]);
                      } finally {
                        if (mounted) setState(() => _loading = false);
                      }
                    },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 14 : 26,
                16,
                compact ? 14 : 26,
                12,
              ),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(compact ? 18 : 23),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_blue, Color(0xFF3949AB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: _blue.withOpacity(0.16),
                      blurRadius: 22,
                      offset: const Offset(0, 9),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: compact ? 48 : 56,
                      height: compact ? 48 : 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: const Icon(
                        Icons.groups_rounded,
                        color: Colors.white,
                        size: 29,
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Directorio de estudiantes',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 19 : 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _totalStudents == null
                                ? 'Consulta perfiles y administra el acceso de tus estudiantes.'
                                : '$_totalStudents estudiantes registrados en esta escuela.',
                            style: const TextStyle(
                              color: Color(0xFFE5E9FF),
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 14 : 26,
                0,
                compact ? 14 : 26,
                12,
              ),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(19),
                  side: const BorderSide(color: Color(0xFFE5EAF2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final searchWidth =
                          constraints.maxWidth >= 720
                              ? 360.0
                              : constraints.maxWidth;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: searchWidth,
                            child: TextField(
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search),
                                hintText:
                                    'Buscar por nombre, usuario, correo, matrícula o grado',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (v) => setState(() => _search = v),
                            ),
                          ),
                          DropdownButton<String?>(
                            value: _filterStatus,
                            hint: const Text('Estado'),
                            items: const [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Todos'),
                              ),
                              DropdownMenuItem<String?>(
                                value: _statusActivo,
                                child: Text('Activo'),
                              ),
                              DropdownMenuItem<String?>(
                                value: _statusPendiente,
                                child: Text('Pendiente'),
                              ),
                              DropdownMenuItem<String?>(
                                value: _statusBloqueado,
                                child: Text('Bloqueado'),
                              ),
                            ],
                            onChanged: (v) => setState(() => _filterStatus = v),
                          ),
                          if (_availableGrades.isNotEmpty)
                            DropdownButton<String?>(
                              value:
                                  (_filterGrade != null &&
                                          _availableGrades.contains(
                                            _filterGrade,
                                          ))
                                      ? _filterGrade
                                      : null,
                              hint: const Text('Grado'),
                              items: <DropdownMenuItem<String?>>[
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Todos'),
                                ),
                                ..._availableGrades.map(
                                  (g) => DropdownMenuItem<String?>(
                                    value: g,
                                    child: Text(g),
                                  ),
                                ),
                              ],
                              onChanged:
                                  (v) => setState(() => _filterGrade = v),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            Expanded(child: _buildList()),
          ],
        ),
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
