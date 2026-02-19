import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class EstudiantesDetalle extends StatelessWidget {
  final Escuela escuela;
  final String studentId;

  const EstudiantesDetalle({
    super.key,
    required this.escuela,
    required this.studentId,
  });

  // ✅ Tu escuela a veces es "QICMY6Q5", pero en Firestore el doc real es "eduproapp_admin_QICMY6Q5"
  // Este resolver busca el docId donde REALMENTE existe el alumno.
  String get _schoolCode => normalizeSchoolIdFromEscuela(escuela);

  // -------------------------
  // Status (ES como fuente de verdad)
  // -------------------------
  static const String _statusActivo = 'activo';
  static const String _statusPendiente = 'pendiente';
  static const String _statusBloqueado = 'bloqueado';

  String _normalizeStatus(dynamic raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    if (s.isEmpty) return _statusActivo;

    // EN -> ES
    if (s == 'active') return _statusActivo;
    if (s == 'pending' || s == 'pending_approval') return _statusPendiente;
    if (s == 'blocked') return _statusBloqueado;

    // ES
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
      default:
        return Colors.green.shade700;
    }
  }

  // -------------------------
  // Helpers (compat)
  // -------------------------
  String _pickString(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

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

  String _nombre(Map<String, dynamic> data) {
    final full = _pickString(data, [
      'nombreCompleto',
      'nombre',
      'fullName',
      'name',
      'nombreAlumno',
      'NombreCompleto',
      'Nombre',
    ]);
    if (full.isNotEmpty) return full;

    final nombres = _pickString(data, ['nombres', 'Nombres', 'primerNombre', 'PrimerNombre']);
    final apellidos = _pickString(data, ['apellidos', 'Apellidos', 'apellido', 'Apellido']);
    final armado = ('$nombres $apellidos').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (armado.isNotEmpty) return armado;

    if (apellidos.isNotEmpty) return apellidos;
    return 'Sin nombre';
  }

  String _grado(Map<String, dynamic> data) {
    final g = _pickString(data, ['grado', 'Grado', 'grade', 'curso', 'nivel']);
    if (g.isNotEmpty) return g;

    final gl = _normalizeStringList(data['grados']);
    if (gl.isNotEmpty) return gl.first;

    final gel = _normalizeStringList(data['grades']);
    if (gel.isNotEmpty) return gel.first;

    return '';
  }

  List<String> _teacherSubjects(Map<String, dynamic> t) {
    final list = _normalizeStringList(t['subjects']);
    if (list.isNotEmpty) return list;

    final list2 = _normalizeStringList(t['asignaturas']);
    if (list2.isNotEmpty) return list2;

    final list3 = _normalizeStringList(t['materias']);
    if (list3.isNotEmpty) return list3;

    final s = (t['subjects'] ?? t['asignaturas'] ?? t['materias'] ?? '').toString();
    if (s.contains(',')) return _parseCommaList(s);
    return s.trim().isEmpty ? const [] : [s.trim()];
  }

  String _normalizeTeacherStatus(dynamic raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    if (s == 'blocked' || s == 'bloqueado') return 'blocked';
    if (s == 'pending' || s == 'pending_approval' || s == 'pendiente') return 'pending';
    return 'active';
  }

  String _fmt(dynamic v) {
    if (v == null) return '—';
    if (v is Timestamp) {
      final d = v.toDate();
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}  '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    if (v is DateTime) {
      return '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
    }
    if (v is List) {
      final s = v.map((e) => e?.toString() ?? '').where((x) => x.trim().isNotEmpty).join(', ');
      return s.isEmpty ? '—' : s;
    }
    if (v is Map) {
      if (v.isEmpty) return '—';
      return v.entries.map((e) => '${e.key}: ${e.value}').join(' | ');
    }
    final s = v.toString().trim();
    return s.isEmpty ? '—' : s;
  }

  bool _isTechKey(String k) {
    final lk = k.toLowerCase();
    return lk.endsWith('key') ||
        lk.endsWith('id') ||
        lk.contains('token') ||
        lk.contains('createdat') ||
        lk.contains('updatedat') ||
        lk.contains('schoolref');
  }

  // -------------------------
  // ✅ Resolver docId correcto del school para este alumno
  // -------------------------
  Future<String> _resolveSchoolDocId(FirebaseFirestore db) async {
    final candidates = <String>[
      _schoolCode,
      'eduproapp_admin_$_schoolCode',
      'eduproapp_admin_${_schoolCode.toUpperCase()}',
      'eduproapp_admin_${_schoolCode.toLowerCase()}',
    ].toSet().toList();

    for (final sid in candidates) {
      try {
        final s = await db.collection('schools').doc(sid).collection('alumnos').doc(studentId).get();
        if (s.exists) return sid;
      } catch (_) {}
    }
    // fallback (aunque no exista, evitamos crash)
    return candidates.first;
  }

  DocumentReference<Map<String, dynamic>> _studentRef(FirebaseFirestore db, String schoolDocId) {
    return db.collection('schools').doc(schoolDocId).collection('alumnos').doc(studentId);
  }

  // -------------------------
  // ✅ Actualizar estado alumno (alumnos + alumnos_login best-effort)
  // -------------------------
  Future<void> _setStudentStatus(
    BuildContext context,
    FirebaseFirestore db,
    String schoolDocId,
    String status,
  ) async {
    final normalized = _normalizeStatus(status);
    final enabled = normalized != _statusBloqueado;

    final schoolDoc = db.collection('schools').doc(schoolDocId);
    final payload = <String, dynamic>{
      'status': normalized,
      'statusLower': normalized,
      'statusLabel': _statusLabel(normalized),
      'enabled': enabled,
      'statusAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      final batch = db.batch();
      batch.set(schoolDoc.collection('alumnos').doc(studentId), payload, SetOptions(merge: true));
      batch.set(schoolDoc.collection('alumnos_login').doc(studentId), payload, SetOptions(merge: true));
      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Estado actualizado: ${_statusLabel(normalized)}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error actualizando estado: $e')),
        );
      }
    }
  }

  // -------------------------
  // Docentes del grado (merge de queries + colecciones compat)
  // -------------------------
  Future<List<Map<String, dynamic>>> _fetchTeachersForGrade(
    FirebaseFirestore db,
    String schoolDocId,
    String grade,
  ) async {
    if (grade.trim().isEmpty) return [];

    final schoolDoc = db.collection('schools').doc(schoolDocId);
    final Map<String, Map<String, dynamic>> byId = {};

    Future<void> runQuery(String colName, Future<QuerySnapshot<Map<String, dynamic>>> Function(CollectionReference<Map<String, dynamic>> c) q) async {
      try {
        final c = schoolDoc.collection(colName);
        final snap = await q(c);
        for (final d in snap.docs) {
          final m = d.data();
          m['__id'] = d.id;
          m['__col'] = colName;
          byId['$colName:${d.id}'] = m;
        }
      } catch (_) {}
    }

    const teacherCols = ['teachers', 'docentes', 'profesores'];

    for (final col in teacherCols) {
      // arrayContains (nuevo)
      await runQuery(col, (c) => c.where('grades', arrayContains: grade).get());
      await runQuery(col, (c) => c.where('grados', arrayContains: grade).get());

      // equality (compat viejo)
      await runQuery(col, (c) => c.where('grade', isEqualTo: grade).get());
      await runQuery(col, (c) => c.where('grado', isEqualTo: grade).get());
    }

    final list = byId.values.toList();

    list.sort((a, b) {
      final sa = _normalizeTeacherStatus(a['status']);
      final sb = _normalizeTeacherStatus(b['status']);
      final pa = (sa == 'active') ? 0 : (sa == 'pending' ? 1 : 2);
      final pb = (sb == 'active') ? 0 : (sb == 'pending' ? 1 : 2);
      if (pa != pb) return pa.compareTo(pb);

      final na = (a['name'] ?? a['nombreCompleto'] ?? a['nombre'] ?? '—').toString().toLowerCase();
      final nb = (b['name'] ?? b['nombreCompleto'] ?? b['nombre'] ?? '—').toString().toLowerCase();
      return na.compareTo(nb);
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final azul = Colors.blue.shade900;
    final naranja = Colors.orange;

    return FutureBuilder<String>(
      future: _resolveSchoolDocId(db),
      builder: (context, schoolSnap) {
        if (schoolSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final schoolDocId = schoolSnap.data ?? _schoolCode;

        return Scaffold(
          backgroundColor: const Color(0xFFF7F9FC),
          appBar: AppBar(
            elevation: 0,
            backgroundColor: azul,
            foregroundColor: Colors.white,
            title: const Text('Detalle estudiante'),
          ),
          body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _studentRef(db, schoolDocId).snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}', style: const TextStyle(color: Colors.red)));
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snap.hasData || !snap.data!.exists) {
                return Center(
                  child: Text(
                    'No encontrado.\n(Probé school: $schoolDocId)',
                    textAlign: TextAlign.center,
                  ),
                );
              }

              final data = snap.data!.data() ?? {};
              final nombre = _nombre(data);
              final grado = _grado(data);
              final edad = _fmt(data['edad']);
              final aulaNombre = _pickString(data, ['aulaNombre', 'aula', 'seccion', 'AulaNombre']);
              final direccion = _pickString(data, ['direccion', 'Direccion', 'address']);

              final statusRaw = data['status'];
              final status = _normalizeStatus(statusRaw);
              final statusLabel = (data['statusLabel'] ?? '').toString().trim();
              final enabled = (data['enabled'] != false);

              final identidad = <String, dynamic>{
                'Nombre': nombre,
                if (_pickString(data, ['apellidos', 'Apellidos']).isNotEmpty) 'Apellidos': _pickString(data, ['apellidos', 'Apellidos']),
                if (_pickString(data, ['nombres', 'Nombres']).isNotEmpty) 'Nombres': _pickString(data, ['nombres', 'Nombres']),
                'Fecha Nacimiento': data['fechaNacimiento'] ?? data['FechaNacimiento'] ?? data['nacimiento'] ?? data['dob'],
                'Edad': data['edad'],
              };

              final escolar = <String, dynamic>{
                'Grado': data['grado'] ?? data['Grado'],
                'Aula': aulaNombre,
                'Turno': data['tanda'] ?? data['turno'] ?? data['Turno'],
                'Matrícula': data['matricula'] ?? data['Matricula'],
                'Nivel': data['nivelLabel'] ?? data['nivel'],
              };

              final contacto = <String, dynamic>{
                'Dirección': direccion,
                'Teléfono': data['telefono'] ?? data['Telefono'],
                'Correo': data['correo'] ?? data['email'] ?? data['Correo'],
              };

              final tutor = (data['tutor'] is Map) ? (data['tutor'] as Map) : null;
              final tutores = <String, dynamic>{
                if (tutor != null) 'Tutor': tutor,
                if (data['madreNombre'] != null || data['MadreNombre'] != null) 'Madre': data['madreNombre'] ?? data['MadreNombre'],
                if (data['madreTelefono'] != null || data['MadreTelefono'] != null) 'Teléfono madre': data['madreTelefono'] ?? data['MadreTelefono'],
                if (data['padreNombre'] != null || data['PadreNombre'] != null) 'Padre': data['padreNombre'] ?? data['PadreNombre'],
                if (data['padreTelefono'] != null || data['PadreTelefono'] != null) 'Teléfono padre': data['padreTelefono'] ?? data['PadreTelefono'],
              };

              final emergencia = <String, dynamic>{
                'Emergencia': data['emergencia'] ?? data['Emergencia'],
              };

              final notas = <String, dynamic>{
                'Observaciones': data['observaciones'] ?? data['Observaciones'] ?? data['nota'] ?? data['Nota'],
              };

              final tech = <String, dynamic>{};
              for (final k in data.keys) {
                if (_isTechKey(k)) tech[k] = data[k];
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // HEADER PRO
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(colors: [azul, Colors.blue.shade700]),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(.08), blurRadius: 14, offset: const Offset(0, 6)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: [Colors.white, naranja.withOpacity(.95)]),
                          ),
                          child: Center(
                            child: Text(
                              nombre.isNotEmpty ? nombre.trim()[0].toUpperCase() : '?',
                              style: TextStyle(color: azul, fontSize: 20, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nombre,
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _chip('Grado', grado.isEmpty ? '—' : grado, Colors.white),
                                  _chip('Edad', edad == '—' ? '—' : edad, Colors.white),
                                  if (aulaNombre.isNotEmpty) _chip('Aula', aulaNombre, Colors.white),
                                  _chip('Estado', statusLabel.isNotEmpty ? statusLabel : _statusLabel(status), Colors.white),
                                  _chip('Habilitado', enabled ? 'Sí' : 'No', Colors.white),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ✅ Acciones de estado (lo que pediste)
                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _setStudentStatus(context, db, schoolDocId, _statusActivo),
                            icon: const Icon(Icons.check_circle),
                            label: const Text('Activar'),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _setStudentStatus(context, db, schoolDocId, _statusPendiente),
                            icon: const Icon(Icons.hourglass_bottom),
                            label: const Text('Pendiente'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _setStudentStatus(context, db, schoolDocId, _statusBloqueado),
                            icon: const Icon(Icons.block),
                            label: const Text('Bloquear'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                          ),
                          Chip(
                            label: Text(
                              'Actual: ${_statusLabel(status)}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                            ),
                            backgroundColor: _statusColor(status),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  _section('Identidad', Icons.badge, azul, naranja, identidad),
                  _section('Escolar', Icons.school, azul, naranja, escolar),
                  _section('Contacto', Icons.home, azul, naranja, contacto),
                  _section('Padres / Tutores', Icons.family_restroom, azul, naranja, tutores),
                  _section('Emergencia', Icons.emergency, azul, naranja, emergencia),
                  _section('Notas', Icons.sticky_note_2, azul, naranja, notas),

                  // ✅ Docentes del grado
                  _teachersSection(db, schoolDocId, azul, naranja, grado),

                  if (tech.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _section('Sistema', Icons.settings, azul, naranja, tech, isTech: true),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _teachersSection(FirebaseFirestore db, String schoolDocId, Color azul, Color naranja, String grado) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey('teachers_${schoolDocId}_$grado'),
      future: _fetchTeachersForGrade(db, schoolDocId, grado),
      builder: (context, snap) {
        if (grado.trim().isEmpty) return const SizedBox.shrink();
        if (snap.connectionState == ConnectionState.waiting) {
          return _section('Docentes del grado', Icons.person_search, azul, naranja, {'Cargando': '...'});
        }

        final teachers = snap.data ?? [];
        if (teachers.isEmpty) {
          return _section(
            'Docentes del grado',
            Icons.person_search,
            azul,
            naranja,
            {'Info': 'No se encontraron docentes asignados a este grado.'},
          );
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 10, offset: const Offset(0, 5)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(colors: [azul.withOpacity(.12), naranja.withOpacity(.12)]),
                      ),
                      child: Icon(Icons.person_search, color: azul),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Docentes del grado',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: azul),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: Colors.grey.shade100,
                      ),
                      child: Text(
                        '${teachers.length}',
                        style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...teachers.map((t) {
                  final name = (t['name'] ?? t['nombreCompleto'] ?? t['nombre'] ?? '—').toString();
                  final subjects = _teacherSubjects(t);
                  final subjectsTxt = subjects.isEmpty ? '—' : subjects.join(', ');

                  final st = _normalizeTeacherStatus(t['status']);
                  final stLabel = (st == 'active') ? 'Activo' : (st == 'pending' ? 'Pendiente' : 'Bloqueado');
                  final stColor = (st == 'active') ? Colors.green : (st == 'pending' ? Colors.orange : Colors.red);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: const Color(0xFFF7F9FC),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(color: stColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: TextStyle(fontWeight: FontWeight.w900, color: azul)),
                              const SizedBox(height: 6),
                              Text('Asignaturas: $subjectsTxt', style: const TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              Text('Estado: $stLabel', style: TextStyle(color: stColor, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String label, String value, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.18)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: textColor, fontWeight: FontWeight.w800, fontSize: 12.5),
      ),
    );
  }

  Widget _section(
    String title,
    IconData icon,
    Color azul,
    Color naranja,
    Map<String, dynamic> fields, {
    bool isTech = false,
  }) {
    final entries = fields.entries.where((e) => _fmt(e.value) != '—').toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 10, offset: const Offset(0, 5)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(colors: [azul.withOpacity(.12), naranja.withOpacity(.12)]),
                  ),
                  child: Icon(icon, color: azul),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: azul),
                  ),
                ),
                if (isTech)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: Colors.grey.shade100,
                    ),
                    child: Text('técnico', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...entries.map((e) => _kv(e.key, _fmt(e.value), azul)),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, Color azul) {
    String cleanKey(String key) {
      final spaced = key.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
      return spaced.replaceAll('_', ' ').trim();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFFF7F9FC),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              cleanKey(k),
              style: TextStyle(fontWeight: FontWeight.w900, color: azul),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Text(
              v,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// ✅ Compat: si en algún lado todavía importabas AUsuarioDetalle, no se rompe.
/// (Puedes borrarlo más adelante cuando confirmes que ya nadie lo usa.)
@Deprecated('Usa EstudiantesDetalle')
class AUsuarioDetalle extends EstudiantesDetalle {
  const AUsuarioDetalle({
    super.key,
    required super.escuela,
    required String rol,
    required String userId,
  }) : super(studentId: userId);
}
