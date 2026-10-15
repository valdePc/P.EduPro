import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

const Color _kBlue = Color(0xFF0F4C81);
const Color _kAccent = Color(0xFF18A0FB);
const Color _kBg = Color(0xFFF4F7FB);

class TareasTab extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> estRef;
  const TareasTab({super.key, required this.estRef});

  @override
  State<TareasTab> createState() => _TareasTabState();
}

class _TareasTabState extends State<TareasTab> {
  String _filter = 'active'; // active | delivered | graded | all
  String _subjectFilter = ''; // '' => todas

  String get _schoolId => widget.estRef.parent.parent?.id ?? '';
  String get _studentId => widget.estRef.id;

  CollectionReference<Map<String, dynamic>> get _tasksCol => FirebaseFirestore.instance
      .collection('schools')
      .doc(_schoolId)
      .collection('tareas_docentes');

  void _log(String msg) {
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kBg,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: widget.estRef.snapshots(),
        builder: (context, estSnap) {
          if (!estSnap.hasData) return const Center(child: CircularProgressIndicator());
          final est = estSnap.data!.data() ?? <String, dynamic>{};
          final gradeKeys = _studentGradeKeys(est);
          final primaryGradeId = _pickPrimaryGradeId(est);
          final studentName = _studentName(est);

          if (primaryGradeId.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No encontramos tu grado asignado para cargar tareas.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _tasksCol
                .where('gradeId', isEqualTo: primaryGradeId)
                .limit(300)
                .snapshots(),
            builder: (context, taskSnap) {
              if (taskSnap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error cargando tareas:\n${taskSnap.error}', textAlign: TextAlign.center),
                  ),
                );
              }
              if (!taskSnap.hasData) return const Center(child: CircularProgressIndicator());

              final all = taskSnap.data!.docs
                  .map((d) => _TaskDoc.fromFirestore(d))
                  .where((t) => gradeKeys.contains(t.gradeId))
                  .where((t) => t.isScheduledOpen)
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

              final subjects = _uniqueSubjects(all);
              if (_subjectFilter.isNotEmpty &&
                  !subjects.any((s) => s.id == _subjectFilter)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _subjectFilter = '');
                });
              }

              final bySubject = _subjectFilter.isEmpty
                  ? all
                  : all.where((t) => t.subjectId == _subjectFilter).toList();

              return Column(
                children: [
                  _hero(),
                  const SizedBox(height: 10),
                  _filtersRow(bySubject, subjects),
                  const SizedBox(height: 8),
                  _performancePanel(bySubject),
                  const SizedBox(height: 8),
                  Expanded(
                    child: bySubject.isEmpty
                        ? const Center(child: Text('No hay tareas para ese filtro.'))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                            itemCount: bySubject.length,
                            itemBuilder: (_, i) => _taskCard(bySubject[i], studentName),
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _hero() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [_kBlue, _kAccent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tus tareas',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
          ),
          SizedBox(height: 4),
          Text(
            'Responde, entrega a tiempo y mejora tu puntaje acumulado.',
            style: TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _filtersRow(List<_TaskDoc> tasks, List<_SubjOpt> subjects) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('Activas', 'active'),
              _chip('Entregadas', 'delivered'),
              _chip('Calificadas', 'graded'),
              _chip('Todas', 'all'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _subjectFilter.isEmpty ? null : _subjectFilter,
                  decoration: InputDecoration(
                    labelText: 'Filtrar por asignatura',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: subjects
                      .map((s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(s.name),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _subjectFilter = v ?? ''),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() => _subjectFilter = ''),
                child: const Text('Quitar'),
              ),
              Text(
                '${tasks.length}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String v) {
    final on = _filter == v;
    return ChoiceChip(
      label: Text(label),
      selected: on,
      onSelected: (_) => setState(() => _filter = v),
      selectedColor: _kBlue.withValues(alpha: 0.15),
      labelStyle: TextStyle(color: on ? _kBlue : Colors.black87, fontWeight: FontWeight.w800),
    );
  }

  Widget _performancePanel(List<_TaskDoc> tasks) {
    return FutureBuilder<_PerfData>(
      future: _computePerformance(tasks),
      builder: (_, s) {
        if (!s.hasData) return const SizedBox.shrink();
        final d = s.data!;
        final c = _perfColor(d.percent);
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white,
            border: Border.all(color: c.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Rendimiento', style: TextStyle(fontWeight: FontWeight.w900, color: c)),
                  const Spacer(),
                  Text(_motivation(d.percent), style: TextStyle(fontWeight: FontWeight.w800, color: c)),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (d.percent / 100).clamp(0, 1),
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(c),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  _meta('Promedio: ${d.percent.toStringAsFixed(1)}%'),
                  _meta('Entregadas: ${d.delivered}/${d.total}'),
                  _meta('Calificadas: ${d.graded}'),
                  _meta('Ranking: ${d.rankLabel}'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _taskCard(_TaskDoc task, String studentName) {
    final subRef = _tasksCol.doc(task.id).collection('submissions').doc(_studentId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: subRef.snapshots(),
      builder: (context, subSnap) {
        final sub = subSnap.data?.data();
        final delivered = subSnap.data?.exists == true;
        final gradedApproved = sub != null && sub['gradeApproved'] == true;

        if (_filter == 'active' && delivered) return const SizedBox.shrink();
        if (_filter == 'delivered' && !delivered) return const SizedBox.shrink();
        if (_filter == 'graded' && !gradedApproved) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                      ),
                      _stateBadge(task, delivered, gradedApproved),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (task.description.isNotEmpty) Text(task.description),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _meta('Asignatura: ${task.subjectName}'),
                      _meta('Grado: ${task.gradeName}'),
                      if (task.dueAt != null) _meta('Límite: ${_fmt(task.dueAt!)}'),
                      _meta('Preguntas: ${task.questions.length}'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (gradedApproved)
                    _gradeStripDetailed(task, sub)
                  else if (delivered)
                    const Text(
                      'Tu tarea fue entregada. Esperando aprobación del docente.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    )
                  else if (task.isClosed)
                    const Text(
                      'La fecha límite venció. Ya no se puede entregar.',
                      style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red),
                    )
                  else
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: () => _openAnswerSheet(task, sub, subRef, studentName),
                        icon: const Icon(Icons.edit_note),
                        label: Text(delivered ? 'Editar entrega' : 'Responder'),
                        style: FilledButton.styleFrom(backgroundColor: _kBlue),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _stateBadge(_TaskDoc t, bool delivered, bool gradedApproved) {
    String label;
    Color color;
    if (gradedApproved) {
      label = 'Calificada';
      color = Colors.green;
    } else if (delivered) {
      label = 'Entregada';
      color = Colors.blueGrey;
    } else if (t.isClosed) {
      label = 'Cerrada';
      color = Colors.red;
    } else {
      label = 'Pendiente';
      color = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900)),
    );
  }


  Widget _gradeStripDetailed(_TaskDoc task, Map<String, dynamic>? sub) {
    final p = _asNum(sub?['finalPoints']) ?? _asNum(sub?['autoPoints']) ?? 0.0;
    final maxTask = _taskMaxPoints(task);
    final percent = maxTask <= 0 ? 0.0 : ((p / maxTask) * 100).clamp(0, 100).toDouble();
    final pColor = _perfColor(percent);
    final scores = <String, Map<String, dynamic>>{};
    final raw = sub?['questionScores'];
    if (raw is Map) {
      final mm = raw.cast<String, dynamic>();
      for (final e in mm.entries) {
        if (e.value is Map) {
          scores[e.key] = (e.value as Map).cast<String, dynamic>();
        }
      }
    } else if (raw is List) {
      for (final it in raw) {
        if (it is! Map) continue;
        final m = it.cast<String, dynamic>();
        final qid = (m['qid'] ?? m['id'] ?? '').toString();
        if (qid.isEmpty) continue;
        scores[qid] = m;
      }
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.green.withValues(alpha: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Calificacion publicada: ${p.toStringAsFixed(1)} puntos',
            style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: (percent / 100).clamp(0, 1),
                  minHeight: 7,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(pColor),
                ),
              ),
              const SizedBox(width: 8),
              Text('${percent.toStringAsFixed(0)}%', style: TextStyle(fontWeight: FontWeight.w900, color: pColor)),
            ],
          ),
          const SizedBox(height: 4),
          Text(_motivation(percent), style: TextStyle(fontWeight: FontWeight.w700, color: pColor)),
          if (scores.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Detalle por pregunta', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            ...task.questions.map((q) {
              final row = scores[q.id] ?? const <String, dynamic>{};
              final earned = _asNum(row['earned']) ?? 0;
              final max = _asNum(row['max']) ?? q.points.toDouble();
              final ok = row['correct'] == true;
              final answerView = (row['answerView'] ?? '').toString();
              final expectedView = (row['expectedView'] ?? '').toString();
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(ok ? Icons.check_circle : Icons.cancel, size: 16, color: ok ? Colors.green : Colors.red),
                        const SizedBox(width: 6),
                        Expanded(child: Text(q.text, style: const TextStyle(fontWeight: FontWeight.w700))),
                        Text('${earned.toStringAsFixed(1)}/${max.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                      ],
                    ),
                    if (answerView.isNotEmpty) Text('Tu respuesta: $answerView', style: const TextStyle(fontSize: 12)),
                    if (expectedView.isNotEmpty) Text('Esperada: $expectedView', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _meta(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: Colors.blueGrey.withValues(alpha: 0.10),
        ),
        child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      );

  Future<void> _openAnswerSheet(
    _TaskDoc task,
    Map<String, dynamic>? currentSub,
    DocumentReference<Map<String, dynamic>> subRef,
    String studentName,
  ) async {
    if (task.isClosed) return;

    final initial = (currentSub?['answers'] is Map)
        ? (currentSub!['answers'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final answers = Map<String, dynamic>.from(initial);

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setS) {
          Widget qWidget(_Question q, int idx) {
            if (q.type == 'multiple_choice') {
              final opts = q.options;
              final selected = (answers[q.id] ?? '').toString();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final o in opts)
                    RadioListTile<String>(
                      value: o,
                      groupValue: selected,
                      title: Text(o),
                      onChanged: (v) => setS(() => answers[q.id] = v ?? ''),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              );
            }
            if (q.type == 'true_false') {
              final raw = answers[q.id];
              bool? selected;
              if (raw is bool) {
                selected = raw;
              } else {
                final txt = _norm((raw ?? '').toString());
                if (txt == 'true' || txt == 'verdadero') {
                  selected = true;
                } else if (txt == 'false' || txt == 'falso') {
                  selected = false;
                } else {
                  selected = null;
                }
              }
              return Row(
                children: [
                  Expanded(
                    child: RadioListTile<bool>(
                      value: true,
                      groupValue: selected,
                      title: const Text('Verdadero'),
                      onChanged: (v) => setS(() => answers[q.id] = v == true),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<bool>(
                      value: false,
                      groupValue: selected,
                      title: const Text('Falso'),
                      onChanged: (v) => setS(() => answers[q.id] = v == true),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              );
            }
            if (q.type == 'matching') {
              final m = (answers[q.id] is Map)
                  ? (answers[q.id] as Map).cast<String, dynamic>()
                  : <String, dynamic>{};
              final rights = q.pairs.map((e) => e.right).toList();
              return Column(
                children: q.pairs
                    .map(
                      (p) => Row(
                        children: [
                          Expanded(child: Text(p.left)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: m[_matchKey(p.left)]?.toString(),
                              decoration: const InputDecoration(border: OutlineInputBorder()),
                              items: rights
                                  .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                                  .toList(),
                              onChanged: (v) {
                                m[_matchKey(p.left)] = v ?? '';
                                setS(() => answers[q.id] = m);
                              },
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              );
            }

            return TextFormField(
              initialValue: (answers[q.id] ?? '').toString(),
              onChanged: (v) => answers[q.id] = v,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Escribe tu respuesta',
              ),
            );
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 10, 14, MediaQuery.of(context).viewInsets.bottom + 14),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.9,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(height: 4),
                    Text('Completa las respuestas y envía antes de ${task.dueAt == null ? "sin fecha límite" : _fmt(task.dueAt!)}'),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: task.questions.length,
                        itemBuilder: (_, i) {
                          final q = task.questions[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.black12),
                              color: Colors.white,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${i + 1}. ${q.text}',
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_qTypeLabel(q.type)} • ${q.points} pts',
                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                                ),
                                const SizedBox(height: 8),
                                qWidget(q, i),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Row(
                      children: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: () => Navigator.pop(context, true),
                          icon: const Icon(Icons.send),
                          label: const Text('Enviar tarea'),
                          style: FilledButton.styleFrom(backgroundColor: _kBlue),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (ok != true) return;
    final safeAnswers = _sanitizeAnswers(answers);
    _log('SUBMIT_START schoolId=$_schoolId taskId=${task.id} studentId=$_studentId');
    _log('SUBMIT_KEYS ${safeAnswers.keys.toList()}');
    try {
      await subRef.set({
        'studentId': _studentId,
        'studentName': studentName,
        'answers': safeAnswers,
        'status': 'submitted',
        'submittedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tarea enviada correctamente.')),
      );
    } catch (e) {
      _log('SUBMIT_ERROR $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo entregar la tarea: $e')),
      );
    }
  }

  static Map<String, dynamic> _sanitizeAnswers(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    for (final e in raw.entries) {
      final key = e.key.trim();
      if (key.isEmpty) continue;
      final v = e.value;
      if (v == null || v is String || v is bool || v is num) {
        out[key] = v;
        continue;
      }
      if (v is Map) {
        final clean = <String, dynamic>{};
        for (final me in v.entries) {
          final mk = me.key.toString().trim();
          if (mk.isEmpty) continue;
          final mv = me.value;
          if (mv == null || mv is String || mv is bool || mv is num) {
            clean[mk] = mv;
          } else {
            clean[mk] = mv.toString();
          }
        }
        out[key] = clean;
        continue;
      }
      out[key] = v.toString();
    }
    return out;
  }

  static Set<String> _studentGradeKeys(Map<String, dynamic> d) {
    final out = <String>{};
    void add(dynamic v) {
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty) out.add(s);
    }

    add(d['gradeId']);
    add(d['gradoId']);
    add(d['gradeKey']);
    add(d['gradoKey']);
    if (d['gradeIds'] is List) {
      for (final e in d['gradeIds']) add(e);
    }
    if (d['gradoIds'] is List) {
      for (final e in d['gradoIds']) add(e);
    }
    if (d['gradeKeys'] is List) {
      for (final e in d['gradeKeys']) add(e);
    }
    if (d['gradosKeys'] is List) {
      for (final e in d['gradosKeys']) add(e);
    }
    return out;
  }

  static String _pickPrimaryGradeId(Map<String, dynamic> d) {
    final candidates = [
      d['gradeId'],
      d['gradoId'],
      d['gradeKey'],
      d['gradoKey'],
    ];
    for (final c in candidates) {
      final s = (c ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static String _studentName(Map<String, dynamic> d) {
    final n = (d['nombres'] ?? d['nombre'] ?? '').toString().trim();
    final a = (d['apellidos'] ?? d['apellido'] ?? '').toString().trim();
    final s = ('$n $a').trim();
    return s.isEmpty ? 'Estudiante' : s;
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _norm(String x) => x.trim().toLowerCase();
  static String _matchKey(String raw) {
    final bytes = utf8.encode(raw.trim().toLowerCase());
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
  static double? _asNum(dynamic v) => v is num ? v.toDouble() : null;

  static String _qTypeLabel(String t) {
    switch (t) {
      case 'multiple_choice':
        return 'Selección múltiple';
      case 'true_false':
        return 'Falso/Verdadero';
      case 'matching':
        return 'Pareo';
      default:
        return 'Respuesta corta';
    }
  }

  static List<_SubjOpt> _uniqueSubjects(List<_TaskDoc> tasks) {
    final seen = <String>{};
    final out = <_SubjOpt>[];
    for (final t in tasks) {
      final id = t.subjectId.trim();
      final name = t.subjectName.trim().isEmpty ? id : t.subjectName.trim();
      if (id.isEmpty || seen.contains(id)) continue;
      seen.add(id);
      out.add(_SubjOpt(id: id, name: name));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  double _taskMaxPoints(_TaskDoc task) {
    double sum = 0;
    for (final q in task.questions) {
      sum += q.points.toDouble();
    }
    return sum;
  }

  Future<_PerfData> _computePerformance(List<_TaskDoc> tasks) async {
    if (tasks.isEmpty) return const _PerfData(total: 0, delivered: 0, graded: 0, percent: 0, rankLabel: '-');
    int delivered = 0;
    int graded = 0;
    double mePoints = 0;
    double meMax = 0;
    final byStudent = <String, double>{};
    for (final t in tasks) {
      final tRef = _tasksCol.doc(t.id);
      final my = await tRef.collection('submissions').doc(_studentId).get();
      if (my.exists) delivered++;
      final myData = my.data() ?? <String, dynamic>{};
      if (myData['gradeApproved'] == true) {
        graded++;
        final p = _asNum(myData['finalPoints']) ?? _asNum(myData['autoPoints']) ?? 0;
        mePoints += p;
        meMax += _taskMaxPoints(t);
      }
      final allApproved = await tRef.collection('submissions').where('gradeApproved', isEqualTo: true).get();
      for (final s in allApproved.docs) {
        final sd = s.data();
        final p = _asNum(sd['finalPoints']) ?? _asNum(sd['autoPoints']) ?? 0;
        byStudent[s.id] = (byStudent[s.id] ?? 0) + p;
      }
    }
    final percent = meMax <= 0 ? 0.0 : ((mePoints / meMax) * 100).clamp(0, 100).toDouble();
    var rankLabel = '-';
    if (byStudent.isNotEmpty) {
      final sorted = byStudent.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final idx = sorted.indexWhere((e) => e.key == _studentId);
      if (idx >= 0) rankLabel = '${idx + 1}/${sorted.length}';
    }
    return _PerfData(total: tasks.length, delivered: delivered, graded: graded, percent: percent, rankLabel: rankLabel);
  }

  static Color _perfColor(double pct) {
    if (pct >= 85) return Colors.green;
    if (pct >= 70) return Colors.blue;
    if (pct >= 55) return Colors.orange;
    return Colors.red;
  }

  static String _motivation(double pct) {
    if (pct >= 90) return 'Excelente ritmo';
    if (pct >= 75) return 'Vas muy bien';
    if (pct >= 60) return 'Buen progreso';
    if (pct >= 40) return 'Sigue esforzandote';
    return 'Tu puedes mejorar';
  }
}

class _TaskDoc {
  final String id;
  final String title;
  final String description;
  final String gradeId;
  final String gradeName;
  final String subjectId;
  final String subjectName;
  final DateTime createdAt;
  final DateTime? scheduleAt;
  final DateTime? dueAt;
  final List<_Question> questions;

  _TaskDoc({
    required this.id,
    required this.title,
    required this.description,
    required this.gradeId,
    required this.gradeName,
    required this.subjectId,
    required this.subjectName,
    required this.createdAt,
    required this.scheduleAt,
    required this.dueAt,
    required this.questions,
  });

  bool get isScheduledOpen => scheduleAt == null || DateTime.now().isAfter(scheduleAt!);
  bool get isClosed => dueAt != null && DateTime.now().isAfter(dueAt!);

  static _TaskDoc fromFirestore(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data();
    DateTime? dt(dynamic v) => v is Timestamp ? v.toDate() : null;

    final qList = (x['questions'] is List) ? (x['questions'] as List) : const [];
    final questions = qList.map((e) => _Question.fromMap((e is Map) ? e.cast<String, dynamic>() : const {})).toList();

    return _TaskDoc(
      id: d.id,
      title: (x['title'] ?? 'Tarea').toString(),
      description: (x['description'] ?? '').toString(),
      gradeId: (x['gradeId'] ?? '').toString(),
      gradeName: (x['gradeName'] ?? '').toString(),
      subjectId: (x['subjectId'] ?? '').toString(),
      subjectName: (x['subjectName'] ?? '').toString(),
      createdAt: dt(x['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      scheduleAt: dt(x['scheduleAt']),
      dueAt: dt(x['dueAt']),
      questions: questions,
    );
  }
}

class _Question {
  final String id;
  final String type;
  final String text;
  final int points;
  final List<String> options;
  final List<_PairItem> pairs;

  _Question({
    required this.id,
    required this.type,
    required this.text,
    required this.points,
    required this.options,
    required this.pairs,
  });

  static _Question fromMap(Map<String, dynamic> m) {
    final opts = (m['options'] is List)
        ? (m['options'] as List).map((e) => e.toString()).toList()
        : const <String>[];
    final prs = (m['pairs'] is List)
        ? (m['pairs'] as List)
            .whereType<Map>()
            .map((e) => _PairItem(left: (e['left'] ?? '').toString(), right: (e['right'] ?? '').toString()))
            .toList()
        : const <_PairItem>[];
    return _Question(
      id: (m['id'] ?? '').toString(),
      type: (m['type'] ?? 'short_text').toString(),
      text: (m['text'] ?? '').toString(),
      points: (m['points'] is int) ? m['points'] as int : 0,
      options: opts,
      pairs: prs,
    );
  }
}

class _PairItem {
  final String left;
  final String right;
  const _PairItem({required this.left, required this.right});
}

class _SubjOpt {
  final String id;
  final String name;
  const _SubjOpt({required this.id, required this.name});
}

class _PerfData {
  final int total;
  final int delivered;
  final int graded;
  final double percent;
  final String rankLabel;
  const _PerfData({
    required this.total,
    required this.delivered,
    required this.graded,
    required this.percent,
    required this.rankLabel,
  });
}
