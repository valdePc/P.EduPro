import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class AvisosAlumnoScreen extends StatefulWidget {
  final Escuela escuela;
  const AvisosAlumnoScreen({super.key, required this.escuela});

  @override
  State<AvisosAlumnoScreen> createState() => _AvisosAlumnoScreenState();
}

class _AvisosAlumnoScreenState extends State<AvisosAlumnoScreen> {
  static const Color _blue = Color.fromARGB(255, 21, 101, 192);
  static const Color _bg = Color(0xFFF6F7FB);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late final String _schoolIdLegacy; // /escuelas (avisos legacy)
  late final String _schoolId; // /schools (notificaciones + alumnos)

  bool _loadingCtx = true;
  String? _ctxError;

  // Contexto login/alumno
  String _loginKey = ''; // emailLower/email usado para encontrar alumnos_login
  List<String> _studentFxIds = <String>[]; // studentIds (fx)
  List<String> _gradeIds = <String>[]; // gradeIds/gradoIds
  final Map<String, String> _gradeLabelById = <String, String>{}; // gradeId -> "1 de Inicial" etc.

  User? get _user => _auth.currentUser;
  String get _uid => _user?.uid ?? '';
  String get _emailLower => (_user?.email ?? '').trim().toLowerCase();
  String get _email => (_user?.email ?? '').trim();
  String get _phoneRaw => (_user?.phoneNumber ?? '').trim();

  @override
  void initState() {
    super.initState();
    final raw = normalizeSchoolIdFromEscuela(widget.escuela).toString().trim();
    _schoolIdLegacy = raw;
    _schoolId = raw.replaceAll('/', '_'); // consistente con tu admin/notificaciones
    _loadStudentContext();
  }


  // =========================
  // Notificaciones nuevas
  // =========================
  Stream<QuerySnapshot<Map<String, dynamic>>> _notifAllStudentsStream() {
    return _db
        .collection('schools')
        .doc(_schoolId)
        .collection('notificaciones_alumnos')
        .where('targetType', isEqualTo: 'all_students')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();
  }

  // whereIn máximo 10 (sin orderBy para evitar índices compuestos; ordenamos en app)
  Stream<QuerySnapshot<Map<String, dynamic>>> _notifByGradeIdsStreamWhereIn(List<String> gradeIds) {
    return _db
        .collection('schools')
        .doc(_schoolId)
        .collection('notificaciones_alumnos')
        .where('gradeId', whereIn: gradeIds)
        .limit(200)
        .snapshots();
  }

  // Fallback cuando hay >10 grados: traemos recientes "grade" y filtramos local
  Stream<QuerySnapshot<Map<String, dynamic>>> _notifRecentGradeStreamUnfiltered() {
    return _db
        .collection('schools')
        .doc(_schoolId)
        .collection('notificaciones_alumnos')
        .where('targetType', isEqualTo: 'grade')
        .limit(250)
        .snapshots();
  }

  // =========================
  // Contexto alumno (SIN members)
  // schools/{schoolId}/alumnos_login/{email} => studentIds, gradeIds
  // schools/{schoolId}/alumnos/{fx} => gradeId, grado
  // =========================
  Future<void> _loadStudentContext() async {
    setState(() {
      _loadingCtx = true;
      _ctxError = null;
      _loginKey = '';
      _studentFxIds = <String>[];
      _gradeIds = <String>[];
      _gradeLabelById.clear();
    });

    try {
      if (_user == null || _uid.isEmpty) {
        setState(() {
          _loadingCtx = false;
          _ctxError = 'No hay sesión activa.';
        });
        return;
      }

      final loginDoc = await _findAlumnosLoginDoc();
      if (loginDoc == null || !loginDoc.exists) {
        setState(() {
          _loadingCtx = false;
          _ctxError =
              'No pude identificar tu login en alumnos_login.\n\n'
              'Verifica que exista:\n'
              'schools/{schoolId}/alumnos_login/{email}\n'
              'o que el doc tenga emailLower/email para poder encontrarlo.';
        });
        return;
      }

      final loginData = loginDoc.data() ?? <String, dynamic>{};
      _loginKey = loginDoc.id;

      // studentIds (fx)
      final studentIds = _asStringList(loginData['studentIds']) ??
          _asStringList(loginData['studentsIds']) ??
          _asStringList(loginData['alumnosIds']) ??
          <String>[];

      // gradeIds/gradoIds (pueden venir en ambos)
      final gradeIds = <String>{
        ...(_asStringList(loginData['gradeIds']) ?? const <String>[]),
        ...(_asStringList(loginData['gradoIds']) ?? const <String>[]),
      }.toList();

      // Si faltan gradeIds pero hay studentIds, los derivamos desde alumnos/{fx}
      final resolved = await _resolveGradesAndLabelsFromStudents(studentIds);

      final finalStudentIds = studentIds.isNotEmpty ? studentIds : resolved.studentFxIds;
      final finalGradeIds = gradeIds.isNotEmpty ? gradeIds : resolved.gradeIds;

      // Labels: priorizamos "grado" desde alumnos/{fx}
      _gradeLabelById.addAll(resolved.gradeLabelById);

      setState(() {
        _studentFxIds = finalStudentIds;
        _gradeIds = _uniqueNonEmpty(finalGradeIds);
        _loadingCtx = false;
      });
    } catch (e) {
      setState(() {
        _loadingCtx = false;
        _ctxError = 'No pude cargar el contexto del alumno: $e';
      });
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _findAlumnosLoginDoc() async {
    final col = _db.collection('schools').doc(_schoolId).collection('alumnos_login');

    // 1) docId directo por emailLower/email (tu screenshot: docId == email)
    if (_emailLower.isNotEmpty) {
      final s = await col.doc(_emailLower).get();
      if (s.exists) return s;
    }
    if (_email.isNotEmpty) {
      final s = await col.doc(_email).get();
      if (s.exists) return s;
    }

    // 2) Fallback: query por campos
    if (_emailLower.isNotEmpty) {
      final qs = await col.where('emailLower', isEqualTo: _emailLower).limit(1).get();
      if (qs.docs.isNotEmpty) return qs.docs.first;
    }
    if (_email.isNotEmpty) {
      final qs = await col.where('email', isEqualTo: _email).limit(1).get();
      if (qs.docs.isNotEmpty) return qs.docs.first;
    }

    // 3) Phone (por si algún login fuera por teléfono)
    final phoneDigits = _digitsOnly(_phoneRaw);
    if (phoneDigits.isNotEmpty) {
      final s = await col.doc(phoneDigits).get();
      if (s.exists) return s;

      final qs = await col.where('phone', isEqualTo: phoneDigits).limit(1).get();
      if (qs.docs.isNotEmpty) return qs.docs.first;

      final qs2 = await col.where('telefono', isEqualTo: phoneDigits).limit(1).get();
      if (qs2.docs.isNotEmpty) return qs2.docs.first;
    }

    return null;
  }

  String _digitsOnly(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');

  List<String>? _asStringList(dynamic v) {
    if (v is List) {
      return v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    return null;
  }

  List<String> _uniqueNonEmpty(List<String> input) {
    final set = <String>{};
    for (final s in input) {
      final t = s.trim();
      if (t.isNotEmpty) set.add(t);
    }
    return set.toList();
  }

  // Resuelve (gradeIds + labels) desde alumnos/{fx}
  Future<_ResolvedStudentContext> _resolveGradesAndLabelsFromStudents(List<String> studentFxIds) async {
    final outGradeIds = <String>{};
    final outLabels = <String, String>{};
    final outStudents = <String>{};

    if (studentFxIds.isEmpty) {
      return _ResolvedStudentContext(studentFxIds: const <String>[], gradeIds: const <String>[], gradeLabelById: const {});
    }

    final col = _db.collection('schools').doc(_schoolId).collection('alumnos');

    // Traemos en paralelo (normalmente pocos)
    final futures = studentFxIds.map((fx) async {
      final id = fx.trim();
      if (id.isEmpty) return;

      outStudents.add(id);

      final snap = await col.doc(id).get();
      if (!snap.exists) return;

      final d = snap.data() ?? <String, dynamic>{};

      final gradeId = (d['gradeId'] ?? d['gradoId'] ?? '').toString().trim();
      if (gradeId.isNotEmpty) outGradeIds.add(gradeId);

      final label = (d['grado'] ?? d['gradoKey'] ?? '').toString().trim();
      if (gradeId.isNotEmpty && label.isNotEmpty && !outLabels.containsKey(gradeId)) {
        outLabels[gradeId] = label;
      }
    });

    await Future.wait(futures);

    return _ResolvedStudentContext(
      studentFxIds: outStudents.toList(),
      gradeIds: outGradeIds.toList(),
      gradeLabelById: outLabels,
    );
  }

  // =========================
  // UI helpers
  // =========================
  DateTime? _asDateTime(dynamic v) => (v is Timestamp) ? v.toDate().toLocal() : null;

  String _fmtDateTime(DateTime? dt) {
    if (dt == null) return '';
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yy = dt.year.toString();
    final h24 = dt.hour;
    final h = (h24 % 12 == 0) ? 12 : (h24 % 12);
    final mi = dt.minute.toString().padLeft(2, '0');
    final ampm = h24 >= 12 ? 'PM' : 'AM';
    return '$dd/$mm/$yy • $h:$mi $ampm';
  }

  bool _isUnread(Map<String, dynamic> d) {
    final readBy = d['readBy'];
    if (_uid.isEmpty) return false;
    if (readBy is List) return !readBy.contains(_uid);
    return true;
  }

  Future<void> _markRead(DocumentReference<Map<String, dynamic>> ref) async {
    if (_uid.isEmpty) return;
    try {
      await ref.update({
        'readBy': FieldValue.arrayUnion([_uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // no bloqueamos UI
    }
  }

  Widget _pill({required IconData icon, required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  void _openNotifDetail(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    final title = (data['title'] ?? 'Notificación').toString().trim();
    final body = (data['body'] ?? '').toString().trim();
    final dt = _fmtDateTime(_asDateTime(data['createdAt']));
    final targetType = (data['targetType'] ?? '').toString().trim();
    final gradeName = (data['gradeName'] ?? '').toString().trim();

    await _markRead(doc.reference);
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                if (dt.isNotEmpty)
                  Text(dt, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _pill(
                      icon: Icons.campaign,
                      text: targetType == 'grade'
                          ? 'Por grado${gradeName.isNotEmpty ? ': $gradeName' : ''}'
                          : 'General',
                      color: _blue,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(body.isEmpty ? 'Sin contenido.' : body, style: const TextStyle(height: 1.35)),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // =========================
  // Tabs
  // =========================

  Widget _notificacionesTab() {
    if (_user == null || _uid.isEmpty) {
      return const Center(child: Text('No hay sesión activa.'));
    }

    if (_loadingCtx) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_ctxError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_ctxError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: _blue),
                onPressed: _loadStudentContext,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    // Banner
    Widget banner() {
      final gradesText = _gradeIds.isEmpty
          ? 'Sin grados'
          : _gradeIds
              .map((g) => _gradeLabelById[g]?.isNotEmpty == true ? _gradeLabelById[g]! : g)
              .join(' • ');

      return Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.badge_outlined, color: Colors.grey.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Login: $_loginKey\nGrados: $gradesText',
                style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _loadStudentContext,
              icon: Icon(Icons.refresh, color: Colors.grey.shade700),
            ),
          ],
        ),
      );
    }

    final allStream = _notifAllStudentsStream();

    // Caso sin grado: solo generales
    if (_gradeIds.isEmpty) {
      return Column(
        children: [
          banner(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: allStream,
              builder: (context, snap) {
                if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());

                final docs = snap.data!.docs;
                if (docs.isEmpty) return const Center(child: Text('No hay notificaciones'));

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _notifCard(docs[i]),
                );
              },
            ),
          ),
        ],
      );
    }

    // Si <=10: whereIn (eficiente)
    final gradeIds = _gradeIds.length <= 10 ? _gradeIds : _gradeIds.take(10).toList();
    final gradeStream = _gradeIds.length <= 10 ? _notifByGradeIdsStreamWhereIn(gradeIds) : _notifRecentGradeStreamUnfiltered();

    // Merge all_students + grade
    return Column(
      children: [
        banner(),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: allStream,
            builder: (context, snapAll) {
              if (snapAll.hasError) return Center(child: Text('Error: ${snapAll.error}'));
              if (!snapAll.hasData) return const Center(child: CircularProgressIndicator());

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: gradeStream,
                builder: (context, snapGrade) {
                  if (snapGrade.hasError) return Center(child: Text('Error: ${snapGrade.error}'));
                  if (!snapGrade.hasData) return const Center(child: CircularProgressIndicator());

                  final map = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

                  // Generales
                  for (final d in snapAll.data!.docs) {
                    map[d.id] = d;
                  }

                  // Por grado (filtrado lógico)
                  for (final d in snapGrade.data!.docs) {
                    final data = d.data();
                    final tt = (data['targetType'] ?? '').toString().trim();
                    final gid = (data['gradeId'] ?? '').toString().trim();

                    if (tt != 'grade') continue;

                    // si estamos en fallback (>10), filtramos local
                    if (_gradeIds.length > 10) {
                      if (!_gradeIds.contains(gid)) continue;
                    }

                    map[d.id] = d;
                  }

                  final merged = map.values.toList();
                  merged.sort((a, b) {
                    final adt = _asDateTime(a.data()['createdAt']);
                    final bdt = _asDateTime(b.data()['createdAt']);
                    final aMillis = adt?.millisecondsSinceEpoch ?? 0;
                    final bMillis = bdt?.millisecondsSinceEpoch ?? 0;
                    return bMillis.compareTo(aMillis);
                  });

                  if (merged.isEmpty) return const Center(child: Text('No hay notificaciones'));

                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: merged.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _notifCard(merged[i]),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _notifCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final title = (d['title'] ?? 'Notificación').toString().trim();
    final body = (d['body'] ?? '').toString().trim();
    final dt = _fmtDateTime(_asDateTime(d['createdAt']));
    final unread = _isUnread(d);

    final targetType = (d['targetType'] ?? '').toString().trim();
    final gradeId = (d['gradeId'] ?? '').toString().trim();
    final gradeName = (d['gradeName'] ?? '').toString().trim();
    final gradeLabel = _gradeLabelById[gradeId];

    String audienceText;
    if (targetType == 'grade') {
      final label = gradeName.isNotEmpty
          ? gradeName
          : (gradeLabel?.isNotEmpty == true ? gradeLabel! : gradeId);
      audienceText = 'Por grado: $label';
    } else {
      audienceText = 'General';
    }

    return InkWell(
      onTap: () => _openNotifDetail(doc),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: _blue.withOpacity(0.10),
              child: Icon(Icons.notifications, color: _blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w900, color: Colors.grey.shade900),
                        ),
                      ),
                      if (unread)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.red.withOpacity(0.25)),
                          ),
                          child: const Text(
                            'No leída',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.red),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (dt.isNotEmpty)
                    Text(
                      dt,
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey.shade700),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    body.isEmpty ? 'Toca para ver detalles.' : body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade800),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _pill(icon: Icons.campaign, text: audienceText, color: _blue),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // Build
  // =========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _blue,
        title: Row(
          children: const [
            Icon(Icons.notifications_active_outlined, color: Colors.white, size: 24),
            SizedBox(width: 10),
            Text('Notificaciones'),
          ],
        ),
      ),
      body: _notificacionesTab(),
    );
  }
} // ✅ ESTE CIERRA la clase _AvisosAlumnoScreenState

// ✅ ESTA clase va FUERA (top-level), NO dentro del State
class _ResolvedStudentContext {
  final List<String> studentFxIds;
  final List<String> gradeIds;
  final Map<String, String> gradeLabelById;

  const _ResolvedStudentContext({
    required this.studentFxIds,
    required this.gradeIds,
    required this.gradeLabelById,
  });
}
