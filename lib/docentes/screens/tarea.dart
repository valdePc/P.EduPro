import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:edupro/docentes/widgets/docente_app_bar.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class TareaScreen extends StatefulWidget {
  final Escuela escuela;
  const TareaScreen({super.key, required this.escuela});

  @override
  State<TareaScreen> createState() => _TareaScreenState();
}

class _TareaScreenState extends State<TareaScreen> {
  static const cPrimary = Color(0xFF0F4C81);
  static const cAccent = Color(0xFF18A0FB);
  static const cBg = Color(0xFFF4F7FB);
  static const cCard = Colors.white;
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  late final String _schoolId;
  bool _loading = true;
  String? _error;

  String _teacherDocId = '';
  List<_Opt> _grades = const [];
  List<_Opt> _subjects = const [];
  String _gradeId = '';
  String _subjectId = '';
  Map<String, String> _students = const {};

  CollectionReference<Map<String, dynamic>> get _tasks =>
      _db.collection('schools').doc(_schoolId).collection('tareas_docentes');

  void _log(String msg) {
    if (kDebugMode) {
    }
  }

  @override
  void initState() {
    super.initState();
    _schoolId = normalizeSchoolIdFromEscuela(widget.escuela).toString().trim();
    _boot();
  }

  Future<void> _boot() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final uid = _auth.currentUser?.uid;
      if (uid == null) throw Exception('Debes iniciar sesión.');

      final uidDoc = await _db.collection('schools').doc(_schoolId).collection('teachers_uid').doc(uid).get();
      final memDoc = await _db.collection('schools').doc(_schoolId).collection('members').doc(uid).get();
      _teacherDocId = (uidDoc.data()?['teacherDocId'] ?? memDoc.data()?['teacherDocId'] ?? '').toString().trim();
      if (_teacherDocId.isEmpty) throw Exception('No se encontró teacherDocId.');

      final t = (await _db.collection('schools').doc(_schoolId).collection('teachers').doc(_teacherDocId).get()).data() ?? {};
      final gIds = _uniq(_asList(t['gradeIds']) + _asList(t['gradoIds']) + _asList(t['gradosIds']) + _asList(t['gradesIds']) + _asList(t['gradoKeys']) + _asList(t['gradosKeys']));
      final sIds = _uniq(_asList(t['subjectIds']) + _asList(t['subjectsIds']) + _asList(t['asignaturaIds']) + _asList(t['asignaturasIds']) + _asList(t['materiaIds']) + _asList(t['materiasIds']));

      final gMap = <String, String>{};
      for (final d in (await _db.collection('schools').doc(_schoolId).collection('grados').get()).docs) {
        gMap[d.id] = (d.data()['name'] ?? d.data()['nombre'] ?? d.id).toString();
      }
      final sMap = <String, String>{};
      for (final col in ['subjects', 'asignaturas', 'materias']) {
        for (final d in (await _db.collection('schools').doc(_schoolId).collection(col).get()).docs) {
          sMap[d.id] = (d.data()['name'] ?? d.data()['nombre'] ?? d.id).toString();
        }
      }

      _grades = _dedupeOptions(gIds.map((e) => _Opt(e, gMap[e] ?? e)).toList())
        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      _subjects = _dedupeOptions(sIds.map((e) => _Opt(e, sMap[e] ?? e)).toList())
        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      _gradeId = _grades.isEmpty ? '' : _grades.first.id;
      _subjectId = _subjects.isEmpty ? '' : _subjects.first.id;
      await _loadStudents();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadStudents() async {
    if (_gradeId.isEmpty) {
      _students = const {};
      return;
    }
    final snap = await _db.collection('schools').doc(_schoolId).collection('alumnos').where('gradeId', isEqualTo: _gradeId).get();
    final m = <String, String>{};
    for (final d in snap.docs) {
      final x = d.data();
      final n = (x['nombres'] ?? x['nombre'] ?? '').toString().trim();
      final a = (x['apellidos'] ?? x['apellido'] ?? '').toString().trim();
      m[d.id] = ('$n $a').trim().isEmpty ? d.id : ('$n $a').trim();
    }
    _students = m;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: buildDocenteBackAppBar(context),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center)))
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _hero(),
                      const SizedBox(height: 8),
                      _filters(),
                      const SizedBox(height: 8),
                      _pointsBoard(),
                      const SizedBox(height: 8),
                      Expanded(child: _taskList()),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cPrimary,
        foregroundColor: Colors.white,
        onPressed: (_gradeId.isEmpty || _subjectId.isEmpty) ? null : _newTask,
        icon: const Icon(Icons.add_task),
        label: const Text('Nueva tarea'),
      ),
    );
  }

  Widget _hero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [cPrimary, cAccent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cPrimary.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gestor de tareas',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Filtra por grado y asignatura, crea actividades tipo formulario y controla entregas.',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _filters() => Card(
        color: cCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: cPrimary.withValues(alpha: 0.15)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _gradeId.isEmpty ? null : _gradeId,
                    decoration: const InputDecoration(labelText: 'Grado', border: OutlineInputBorder()),
                    items: _grades.map((g) => DropdownMenuItem(value: g.id, child: Text(g.label))).toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      _gradeId = v;
                      await _loadStudents();
                      if (mounted) setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _subjectId.isEmpty ? null : _subjectId,
                    decoration: const InputDecoration(labelText: 'Asignatura', border: OutlineInputBorder()),
                    items: _subjects.map((s) => DropdownMenuItem(value: s.id, child: Text(s.label))).toList(),
                    onChanged: (v) => setState(() => _subjectId = v ?? ''),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Text(
                  'Alumnos del grado: ${_students.length}',
                  style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton.icon(onPressed: _boot, icon: const Icon(Icons.refresh), label: const Text('Refrescar'))
              ]),
            ],
          ),
        ),
      );

  Widget _taskList() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _tasks.where('createdByUid', isEqualTo: uid).snapshots(),
      builder: (_, s) {
        if (s.hasError) return Center(child: Text('Error: ${s.error}'));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final docs = s.data!.docs.where((d) {
          final x = d.data();
          return (_gradeId.isEmpty || x['gradeId'] == _gradeId) && (_subjectId.isEmpty || x['subjectId'] == _subjectId);
        }).toList()
          ..sort((a, b) => _ts(b.data()['createdAt']).compareTo(_ts(a.data()['createdAt'])));
        if (docs.isEmpty) return const Center(child: Text('No hay tareas para este filtro.'));
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _taskTile(docs[i]),
        );
      },
    );
  }

  Widget _taskTile(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data();
    final due = _dt(x['dueAt']);
    final sch = _dt(x['scheduleAt']);
    final qCount = (x['questions'] is List) ? (x['questions'] as List).length : 0;
    return Card(
      color: cCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text((x['title'] ?? 'Tarea').toString(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
            _pill(due != null && DateTime.now().isAfter(due) ? 'Cerrada' : 'Activa'),
          ]),
          const SizedBox(height: 4),
          Text(
            (x['description'] ?? '').toString(),
            style: TextStyle(color: Colors.grey.shade800),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (sch != null) _pill('Envio: ${_fmt(sch)}'),
            if (due != null) _pill('Limite: ${_fmt(due)}'),
            _pill('Preguntas: $qCount'),
          ]),
          const SizedBox(height: 6),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _tasks.doc(d.id).collection('submissions').snapshots(),
            builder: (_, s) {
              final delivered = s.data?.docs ?? const [];
              final pending = (_students.length - delivered.length).clamp(0, 9999);
              return Row(children: [
                Text('Entregadas: ${delivered.length}'),
                const SizedBox(width: 10),
                Text('Pendientes: $pending'),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _deliveries(d.id, x),
                  icon: const Icon(Icons.list_alt),
                  label: const Text('Ver entregas'),
                ),
              ]);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _newTask() async {
    final t = TextEditingController();
    final d = TextEditingController();
    final v = TextEditingController();
    final f = TextEditingController();
    final questions = <Map<String, dynamic>>[];
    DateTime? scheduleAt;
    DateTime? dueAt;
    bool auto = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (context, setD) {
        return AlertDialog(
          title: const Text('Crear tarea'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: t, decoration: const InputDecoration(labelText: 'Titulo *')),
                TextField(controller: d, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Descripción')),
                TextField(controller: v, decoration: const InputDecoration(labelText: 'Video URL (opcional)')),
                TextField(controller: f, decoration: const InputDecoration(labelText: 'Archivo URL (opcional)')),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final v = await _pickDateTime(scheduleAt);
                        setD(() => scheduleAt = v);
                      },
                      child: Text(scheduleAt == null ? 'Programar envío' : _fmt(scheduleAt!)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final v = await _pickDateTime(dueAt);
                        setD(() => dueAt = v);
                      },
                      child: Text(dueAt == null ? 'Fecha límite' : _fmt(dueAt!)),
                    ),
                  ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-calificación'),
                  subtitle: const Text('La nota se publica cuando el docente la aprueba.'),
                  value: auto,
                  onChanged: (x) => setD(() => auto = x),
                ),
                const Divider(),
                Row(children: [
                  const Expanded(child: Text('Preguntas (estilo formulario)', style: TextStyle(fontWeight: FontWeight.w800))),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final q = await _buildQuestionDialog();
                      if (q != null) setD(() => questions.add(q));
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar'),
                  ),
                ]),
                const SizedBox(height: 6),
                if (questions.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('No hay preguntas. Puedes usar: selección múltiple, falso/verdadero, pareo y respuesta corta.'),
                  ),
                ...questions.map(
                  (q) => Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: ListTile(
                      title: Text(q['text'].toString()),
                      subtitle: Text('${_questionTypeLabel(q['type']?.toString() ?? '')} • Puntos: ${q['points']}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setD(() => questions.remove(q)),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Crear'))],
        );
      }),
    );
    if (ok != true || t.text.trim().isEmpty) return;
    if (scheduleAt != null && dueAt != null && dueAt!.isBefore(scheduleAt!)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La fecha límite no puede ser antes del envío.')));
      return;
    }
    final grade = _grades.firstWhere((e) => e.id == _gradeId, orElse: () => _Opt(_gradeId, _gradeId));
    final subject = _subjects.firstWhere((e) => e.id == _subjectId, orElse: () => _Opt(_subjectId, _subjectId));
    final uid = _auth.currentUser?.uid ?? '';

    _log('SAVE_TASK_START schoolId=$_schoolId uid=$uid teacherDocId=$_teacherDocId gradeId=${grade.id} subjectId=${subject.id}');

    // Preflight de diagnóstico para reglas.
    try {
      final tRef = _db.collection('schools').doc(_schoolId).collection('teachers').doc(_teacherDocId);
      final tSnap = await tRef.get();
      _log('PRECHECK teachers.exists=${tSnap.exists} teachers.path=${tRef.path}');
      if (tSnap.exists) {
        final td = tSnap.data() ?? {};
        final gradePool = _asList(td['gradeIds']) +
            _asList(td['gradoIds']) +
            _asList(td['gradosIds']) +
            _asList(td['gradesIds']) +
            _asList(td['gradoKeys']) +
            _asList(td['gradosKeys']);
        final subPool = _asList(td['subjectIds']) +
            _asList(td['subjectsIds']) +
            _asList(td['asignaturaIds']) +
            _asList(td['asignaturasIds']) +
            _asList(td['materiaIds']) +
            _asList(td['materiasIds']);
        _log(
          'PRECHECK gradeInTeacher=${gradePool.contains(grade.id)} '
          'subjectInTeacher=${subPool.isEmpty ? "EMPTY_LIST_ALLOW_ALL" : subPool.contains(subject.id)}',
        );
      }
    } catch (e) {
      _log('PRECHECK_ERROR $e');
    }

    final payload = <String, dynamic>{
      'title': t.text.trim(),
      'description': d.text.trim(),
      'schoolId': _schoolId,
      'teacherDocId': _teacherDocId,
      'createdByUid': _auth.currentUser?.uid,
      'gradeId': grade.id,
      'gradeName': grade.label,
      'subjectId': subject.id,
      'subjectName': subject.label,
      'resources': {
        'videoUrls': v.text.trim().isEmpty ? <String>[] : [v.text.trim()],
        'fileUrls': f.text.trim().isEmpty ? <String>[] : [f.text.trim()]
      },
      'blockAfterDue': true,
      'autoGradeEnabled': auto,
      'questions': questions,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (scheduleAt != null) payload['scheduleAt'] = Timestamp.fromDate(scheduleAt!);
    if (dueAt != null) payload['dueAt'] = Timestamp.fromDate(dueAt!);

    try {
      _log('SAVE_TASK_PAYLOAD_KEYS ${payload.keys.toList()}');
      await _tasks.add(payload);
      _log('SAVE_TASK_OK');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tarea guardada correctamente.')),
      );
    } on FirebaseException catch (e) {
      _log('SAVE_TASK_FIREBASE_ERROR code=${e.code} message=${e.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar (${e.code}): ${e.message ?? "sin detalle"}')),
      );
    } catch (e) {
      _log('SAVE_TASK_ERROR $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar la tarea: $e')),
      );
    }
  }

  Future<void> _deliveries(String taskId, Map<String, dynamic> task) async {
    final ref = _tasks.doc(taskId);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.82,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ref.collection('submissions').snapshots(),
              builder: (_, s) {
                final docs = s.data?.docs ?? const [];
                final delivered = {for (final d in docs) d.id: d.data()};
                final pending = _students.entries.where((e) => !delivered.containsKey(e.key)).toList();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((task['title'] ?? 'Entregas').toString(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 6),
                  Text('Entregadas: ${docs.length} • Pendientes: ${pending.length}'),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(children: [
                      const Text('Entregadas', style: TextStyle(fontWeight: FontWeight.w800)),
                      ...docs.map((d) => _deliveryTile(taskId, task, d.id, d.data())),
                      const SizedBox(height: 8),
                      const Text('Pendientes', style: TextStyle(fontWeight: FontWeight.w800)),
                      ...pending.map((e) => ListTile(dense: true, leading: const Icon(Icons.hourglass_bottom, color: Colors.orange), title: Text(e.value))),
                    ]),
                  ),
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>?> _buildQuestionDialog() async {
    String type = 'multiple_choice';
    final textCtrl = TextEditingController();
    final pointsCtrl = TextEditingController(text: '10');
    final shortAnswerCtrl = TextEditingController();
    final optionsCtrl = TextEditingController();
    bool tfAnswer = true;
    final matchingCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setD) {
          return AlertDialog(
            title: const Text('Agregar pregunta'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: type,
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'multiple_choice', child: Text('Selección múltiple')),
                        DropdownMenuItem(value: 'true_false', child: Text('Falso / Verdadero')),
                        DropdownMenuItem(value: 'matching', child: Text('Pareo')),
                        DropdownMenuItem(value: 'short_text', child: Text('Respuesta corta')),
                      ],
                      onChanged: (v) => setD(() => type = v ?? 'multiple_choice'),
                    ),
                    const SizedBox(height: 8),
                    TextField(controller: textCtrl, decoration: const InputDecoration(labelText: 'Pregunta', border: OutlineInputBorder())),
                    const SizedBox(height: 8),
                    TextField(
                      controller: pointsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Puntos', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    if (type == 'multiple_choice') ...[
                      TextField(
                        controller: optionsCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Opciones (separadas por coma)',
                          hintText: 'A, B, C, D',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: shortAnswerCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Respuesta correcta (texto exacto)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    if (type == 'true_false') ...[
                      SwitchListTile(
                        value: tfAnswer,
                        contentPadding: EdgeInsets.zero,
                        title: Text('Respuesta correcta: ${tfAnswer ? "Verdadero" : "Falso"}'),
                        onChanged: (v) => setD(() => tfAnswer = v),
                      ),
                    ],
                    if (type == 'short_text') ...[
                      TextField(
                        controller: shortAnswerCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Respuesta correcta',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    if (type == 'matching') ...[
                      TextField(
                        controller: matchingCtrl,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Pares (uno por línea, formato: izquierda|derecha)',
                          hintText: 'Capital de Francia|París',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
              ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Agregar')),
            ],
          );
        },
      ),
    );

    if (ok != true) return null;
    final qText = textCtrl.text.trim();
    final points = int.tryParse(pointsCtrl.text.trim()) ?? 0;
    if (qText.isEmpty || points <= 0) return null;

    final base = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'type': type,
      'text': qText,
      'points': points,
    };

    if (type == 'multiple_choice') {
      final options = optionsCtrl.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (options.length < 2) return null;
      base['options'] = options;
      base['correctAnswer'] = shortAnswerCtrl.text.trim();
    } else if (type == 'true_false') {
      base['correctBoolean'] = tfAnswer;
    } else if (type == 'short_text') {
      base['correctAnswer'] = shortAnswerCtrl.text.trim();
    } else if (type == 'matching') {
      final lines = matchingCtrl.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final pairs = <Map<String, String>>[];
      for (final l in lines) {
        final parts = l.split('|');
        if (parts.length != 2) continue;
        final left = parts[0].trim();
        final right = parts[1].trim();
        if (left.isEmpty || right.isEmpty) continue;
        pairs.add({'left': left, 'right': right});
      }
      if (pairs.isEmpty) return null;
      base['pairs'] = pairs;
    }

    return base;
  }

  Widget _deliveryTile(String taskId, Map<String, dynamic> task, String sid, Map<String, dynamic> sub) {
    final name = _students[sid] ?? (sub['studentName'] ?? sid).toString();
    final submittedAt = _dt(sub['submittedAt']);
    final auto = _num(sub['autoPoints']);
    final fin = _num(sub['finalPoints']);
    final approved = sub['gradeApproved'] == true;
    return Card(
      child: ListTile(
        leading: Icon(approved ? Icons.verified : Icons.assignment_turned_in, color: approved ? Colors.green : Colors.blueGrey),
        title: Text(name),
        subtitle: Text('Entrega: ${submittedAt == null ? "-" : _fmt(submittedAt)}\nAuto: ${auto?.toStringAsFixed(1) ?? "-"} • Final: ${fin?.toStringAsFixed(1) ?? "-"}'),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'view') await _reviewSubmission(taskId, task, sid, sub);
            if (v == 'auto') await _autoGrade(taskId, task, sid, sub);
            if (v == 'edit') await _editPoints(taskId, sid, fin ?? auto);
            if (v == 'approve') await _tasks.doc(taskId).collection('submissions').doc(sid).set({'gradeApproved': true, 'approvedByUid': _auth.currentUser?.uid, 'approvedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'view', child: Text('Ver respuestas')),
            PopupMenuItem(value: 'auto', child: Text('Auto-calificar')),
            PopupMenuItem(value: 'edit', child: Text('Editar puntos')),
            PopupMenuItem(value: 'approve', child: Text('Aprobar y publicar')),
          ],
        ),
      ),
    );
  }

  Future<void> _reviewSubmission(
    String taskId,
    Map<String, dynamic> task,
    String sid,
    Map<String, dynamic> sub,
  ) async {
    final qs = (task['questions'] is List) ? (task['questions'] as List) : const [];
    final ans = (sub['answers'] is Map) ? (sub['answers'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    final prevScoresRaw = sub['questionScores'];
    final prevById = <String, Map<String, dynamic>>{};
    if (prevScoresRaw is Map) {
      final mm = prevScoresRaw.cast<String, dynamic>();
      for (final e in mm.entries) {
        if (e.value is Map) {
          prevById[e.key] = (e.value as Map).cast<String, dynamic>();
        }
      }
    } else if (prevScoresRaw is List) {
      for (final it in prevScoresRaw) {
        if (it is! Map) continue;
        final m = it.cast<String, dynamic>();
        final qid = (m['qid'] ?? m['id'] ?? '').toString();
        if (qid.isEmpty) continue;
        prevById[qid] = m;
      }
    }
    final earned = <String, double>{};
    for (final q in qs) {
      if (q is! Map) continue;
      final m = q.cast<String, dynamic>();
      final id = (m['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final prev = prevById[id] ?? const <String, dynamic>{};
      earned[id] = _num(prev['earned']) ?? 0;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: const Text('Respuestas del alumno'),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final q in qs)
                    if (q is Map)
                      _reviewQuestionTile(
                        q.cast<String, dynamic>(),
                        ans,
                        earned,
                        setD,
                      ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cerrar')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar calificacion'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final questionScores = <Map<String, dynamic>>[];
    double finalTotal = 0;
    for (final q in qs) {
      if (q is! Map) continue;
      final m = q.cast<String, dynamic>();
      final id = (m['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final max = (_num(m['points']) ?? 0).clamp(0, 1000000);
      final e = (earned[id] ?? 0).clamp(0, max);
      final gotRaw = ans[id];
      questionScores.add({
        'qid': id,
        'earned': e,
        'max': max,
        'correct': (max > 0) && (e >= max),
        'answerView': _answerAsText((m['type'] ?? 'short_text').toString(), gotRaw),
        'expectedView': _expectedAsText(m),
      });
      finalTotal += e;
    }

    await _tasks.doc(taskId).collection('submissions').doc(sid).set({
      'questionScores': questionScores,
      'finalPoints': finalTotal,
      'gradeApproved': false,
      'gradedByUid': _auth.currentUser?.uid,
      'gradedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Widget _reviewQuestionTile(
    Map<String, dynamic> q,
    Map<String, dynamic> ans,
    Map<String, double> earned,
    void Function(void Function()) setD,
  ) {
    final id = (q['id'] ?? '').toString();
    final text = (q['text'] ?? 'Pregunta').toString();
    final type = (q['type'] ?? 'short_text').toString();
    final max = (_num(q['points']) ?? 0).clamp(0, 1000000);
    final gotRaw = ans[id];
    final current = earned[id] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Respuesta: ${_answerAsText(type, gotRaw)}'),
          const SizedBox(height: 2),
          Text('Esperada: ${_expectedAsText(q)}'),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Puntos (max ${max.toStringAsFixed(1)}):'),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextFormField(
                  initialValue: current.toStringAsFixed(1),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) => setD(() {
                    final n = double.tryParse(v.trim()) ?? 0;
                    earned[id] = n.clamp(0.0, max).toDouble();
                  }),
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _autoGrade(String taskId, Map<String, dynamic> task, String sid, Map<String, dynamic> sub) async {
    final qs = (task['questions'] is List) ? (task['questions'] as List) : const [];
    final ans = (sub['answers'] is Map) ? (sub['answers'] as Map).cast<String, dynamic>() : const <String, dynamic>{};
    double total = 0;
    final questionScores = <Map<String, dynamic>>[];
    for (final q in qs) {
      if (q is! Map) continue;
      final m = q.cast<String, dynamic>();
      final id = (m['id'] ?? '').toString();
      final p = _num(m['points']) ?? 0;
      if (id.isEmpty) continue;
      final type = (m['type'] ?? 'short_text').toString();
      final gotRaw = ans[id];
      double earned = 0;
      bool correct = false;
      if (type == 'true_false') {
        final expected = m['correctBoolean'] == true;
        final gotBool = (gotRaw is bool)
            ? gotRaw
            : (_norm(gotRaw?.toString() ?? '') == 'true' || _norm(gotRaw?.toString() ?? '') == 'verdadero');
        if (gotBool == expected) {
          earned = p;
          correct = true;
        }
      } else if (type == 'matching') {
        final pairs = (m['pairs'] is List) ? (m['pairs'] as List) : const [];
        final gotMap = (ans[id] is Map) ? (ans[id] as Map).cast<String, dynamic>() : const <String, dynamic>{};
        if (pairs.isEmpty) continue;
        int correctCount = 0;
        for (final pr in pairs) {
          if (pr is! Map) continue;
          final pm = pr.cast<String, dynamic>();
          final left = (pm['left'] ?? '').toString();
          final right = _norm((pm['right'] ?? '').toString());
          final got = _norm((gotMap[left] ?? gotMap[_matchKey(left)] ?? '').toString());
          if (left.isNotEmpty && right.isNotEmpty && got == right) correctCount++;
        }
        earned = (p * (correctCount / pairs.length));
        correct = earned >= p;
      } else {
        final expected = _norm((m['correctAnswer'] ?? '').toString());
        final got = _norm((gotRaw ?? '').toString());
        if (expected.isNotEmpty && got == expected) {
          earned = p;
          correct = true;
        }
      }
      total += earned;
      questionScores.add({
        'qid': id,
        'earned': earned,
        'max': p,
        'correct': correct,
        'answerView': _answerAsText(type, gotRaw),
        'expectedView': _expectedAsText(m),
      });
    }
    try {
      _log('AUTO_GRADE_PATH ${_tasks.doc(taskId).collection('submissions').doc(sid).path} uid=${_auth.currentUser?.uid}');
      await _tasks.doc(taskId).collection('submissions').doc(sid).set({
        'questionScores': questionScores,
        'autoPoints': total,
        'finalPoints': sub['finalPoints'] ?? total,
        'gradeApproved': sub['gradeApproved'] == true,
        'gradedByUid': _auth.currentUser?.uid,
        'gradedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Auto-calificacion guardada: ${total.toStringAsFixed(1)} pts')),
        );
      }
    } on FirebaseException catch (e) {
      _log('AUTO_GRADE_FIREBASE_ERROR code=${e.code} message=${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo auto-calificar (${e.code}): ${e.message ?? "sin detalle"}')),
        );
      }
    } catch (e) {
      _log('AUTO_GRADE_ERROR $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error auto-calificando: $e')),
        );
      }
    }
  }

  Future<void> _editPoints(String taskId, String sid, double? current) async {
    final c = TextEditingController(text: current?.toStringAsFixed(1) ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Editar puntos finales'),
        content: TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Puntos')),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar'))],
      ),
    );
    if (ok != true) return;
    final v = double.tryParse(c.text.trim());
    if (v == null) return;
    await _tasks.doc(taskId).collection('submissions').doc(sid).set({'finalPoints': v, 'gradeApproved': false, 'gradedByUid': _auth.currentUser?.uid, 'gradedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Widget _pointsBoard() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || _gradeId.isEmpty || _subjectId.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<Map<String, double>>(
      future: _loadApprovedTotals(uid),
      builder: (_, s) {
        if (!s.hasData) return const SizedBox.shrink();
        final rows = s.data!.entries
            .map((e) => (id: e.key, name: _students[e.key] ?? e.key, points: e.value))
            .toList()
          ..sort((a, b) => b.points.compareTo(a.points));
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Puntos acumulados (aprobados)', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                if (rows.isEmpty)
                  Text('Aún no hay calificaciones aprobadas.', style: TextStyle(color: Colors.grey.shade700))
                else
                  ...rows.take(6).map(
                        (r) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.stars_rounded, color: Colors.amber),
                          title: Text(r.name),
                          trailing: Text(r.points.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, double>> _loadApprovedTotals(String uid) async {
    final tSnap = await _tasks
        .where('createdByUid', isEqualTo: uid)
        .where('gradeId', isEqualTo: _gradeId)
        .where('subjectId', isEqualTo: _subjectId)
        .get();
    final totals = <String, double>{};
    for (final t in tSnap.docs) {
      final subs = await t.reference.collection('submissions').where('gradeApproved', isEqualTo: true).get();
      for (final s in subs.docs) {
        final d = s.data();
        final p = _num(d['finalPoints']) ?? _num(d['autoPoints']) ?? 0;
        totals[s.id] = (totals[s.id] ?? 0) + p;
      }
    }
    return totals;
  }

  Future<DateTime?> _pickDateTime(DateTime? current) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 3), initialDate: current ?? now);
    if (d == null) return current;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current ?? now));
    if (t == null) return current;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  static List<String> _asList(dynamic v) => (v is List) ? v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() : const [];
  static List<String> _uniq(List<String> v) {
    final s = <String>{};
    return v.where((e) => s.add(e)).toList();
  }

  static List<_Opt> _dedupeOptions(List<_Opt> input) {
    final seenByLabel = <String>{};
    final out = <_Opt>[];
    for (final o in input) {
      final key = _normLabel(o.label);
      if (key.isEmpty) continue;
      if (seenByLabel.contains(key)) continue;
      seenByLabel.add(key);
      out.add(_Opt(o.id, _titleCase(o.label)));
    }
    return out;
  }

  static String _normLabel(String x) =>
      x.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static String _titleCase(String x) {
    final parts = _normLabel(x).split(' ');
    return parts.map((p) => p.isEmpty ? '' : '${p[0].toUpperCase()}${p.substring(1)}').join(' ');
  }

  static Widget _pill(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.blueGrey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(999)),
        child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      );
  static Timestamp _ts(dynamic v) => v is Timestamp ? v : Timestamp(0, 0);
  static DateTime? _dt(dynamic v) => v is Timestamp ? v.toDate() : null;
  static double? _num(dynamic v) => v is num ? v.toDouble() : null;
  static String _norm(String s) => s.trim().toLowerCase();
  static String _answerAsText(String type, dynamic gotRaw) {
    if (gotRaw == null) return '-';
    if (type == 'true_false') {
      if (gotRaw is bool) return gotRaw ? 'Verdadero' : 'Falso';
      final v = _norm(gotRaw.toString());
      if (v == 'true' || v == 'verdadero') return 'Verdadero';
      if (v == 'false' || v == 'falso') return 'Falso';
    }
    if (type == 'matching' && gotRaw is Map) {
      final m = gotRaw.cast<String, dynamic>();
      if (m.isEmpty) return '-';
      return m.entries.map((e) => '${e.key} -> ${e.value}').join(' | ');
    }
    return gotRaw.toString().trim().isEmpty ? '-' : gotRaw.toString();
  }
  static String _expectedAsText(Map<String, dynamic> q) {
    final type = (q['type'] ?? 'short_text').toString();
    if (type == 'true_false') return q['correctBoolean'] == true ? 'Verdadero' : 'Falso';
    if (type == 'matching') {
      final pairs = (q['pairs'] is List) ? (q['pairs'] as List) : const [];
      if (pairs.isEmpty) return '-';
      return pairs.whereType<Map>().map((e) => '${e['left']} -> ${e['right']}').join(' | ');
    }
    final v = (q['correctAnswer'] ?? '').toString().trim();
    return v.isEmpty ? '-' : v;
  }
  static String _matchKey(String raw) {
    final bytes = utf8.encode(raw.trim().toLowerCase());
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
  static String _questionTypeLabel(String t) {
    switch (t) {
      case 'multiple_choice':
        return 'Selección múltiple';
      case 'true_false':
        return 'Falso/Verdadero';
      case 'matching':
        return 'Pareo';
      case 'short_text':
        return 'Respuesta corta';
      default:
        return 'Pregunta';
    }
  }
  static String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _Opt {
  final String id;
  final String label;
  const _Opt(this.id, this.label);
}
