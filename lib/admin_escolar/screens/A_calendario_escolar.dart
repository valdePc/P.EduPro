// lib/admin_escolar/screens/A_calendario_escolar.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class ACalendarioEscolar extends StatefulWidget {
  final Escuela escuela;

  const ACalendarioEscolar({
    Key? key,
    required this.escuela,
  }) : super(key: key);

  @override
  State<ACalendarioEscolar> createState() => _ACalendarioEscolarState();
}

class _ACalendarioEscolarState extends State<ACalendarioEscolar>
    with TickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Color _blue = Color(0xFF0D47A1);
  static const Color _orange = Color(0xFFFFA000);

  // ✅ Colores claros (UI)
  static const Color _todayGreen = Color(0xFF2ECC71); // verde claro
  static const Color _nextYellow = Color(0xFFFBC02D); // amarillo visible
  static const Color _pastRed = Color(0xFFFF5252); // rojo claro (redAccent)

  Timer? _clockTimer;

  String get _schoolId => normalizeSchoolIdFromEscuela(widget.escuela);

  CollectionReference<Map<String, dynamic>> get _gradesCol =>
      _db.collection('schools').doc(_schoolId).collection('grados');

  CollectionReference<Map<String, dynamic>> get _teachersCol =>
      _db.collection('schools').doc(_schoolId).collection('teachers');

  CollectionReference<Map<String, dynamic>> get _asignaturasCol =>
      _db.collection('schools').doc(_schoolId).collection('asignaturas');

  CollectionReference<Map<String, dynamic>> get _subjectsCol =>
      _db.collection('schools').doc(_schoolId).collection('subjects');

  CollectionReference<Map<String, dynamic>> get _itemsCol => _db
      .collection('schools')
      .doc(_schoolId)
      .collection('calendario_escolar_items');

  String? _selectedGradeId;
  String? _selectedGradeName;

  // 1=Lun ... 5=Vie (puedes ampliar a 6=Sáb, 7=Dom si lo necesitas)
  int _selectedDay = 1;

  late final TabController _dayTabs;

  late final Future<List<_Option>> _teachersFuture;
  late final Future<List<_Option>> _subjectsFuture;

  // ✅ Día real de hoy dentro del rango Lun..Vie (si es fin de semana -> Lun)
  late final int _todayDay;
  // ✅ Próximo día (si hoy es Vie -> Lun)
  late final int _nextDay;

  int _clampToSchoolWeek(int weekday) {
    // DateTime.weekday: 1=Lun ... 7=Dom
    if (weekday >= 1 && weekday <= 5) return weekday;
    return 1; // Sáb/Dom -> Lunes
  }

  int _calcNextDay(int day) {
    // En tabs Lun..Vie: si hoy es Vie, el próximo es Lun
    return (day == 5) ? 1 : (day + 1);
  }

  int _nowMinutes() {
    final now = DateTime.now();
    return now.hour * 60 + now.minute;
  }

  @override
  void initState() {
    super.initState();

    _todayDay = _clampToSchoolWeek(DateTime.now().weekday);
    _nextDay = _calcNextDay(_todayDay);

    // ✅ Abrir por defecto en el día de hoy
    _selectedDay = _todayDay;

    _dayTabs = TabController(length: 5, vsync: this, initialIndex: _todayDay - 1);
    _dayTabs.addListener(() {
      if (_dayTabs.indexIsChanging) return;
      setState(() => _selectedDay = _dayTabs.index + 1);
    });

    _teachersFuture = _loadTeachers();
    _subjectsFuture = _loadSubjects();

    // ✅ Refrescar colores según pasa el tiempo
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _dayTabs.dispose();
    super.dispose();
  }

  // -------------------------
  // Loaders (compat)
  // -------------------------
  String _pickString(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  Future<List<_Option>> _loadTeachers() async {
    try {
      final snap = await _teachersCol.get();
      final list = <_Option>[];
      for (final d in snap.docs) {
        final m = d.data();
        final name = _pickString(m, ['name', 'nombre', 'Nombre', 'fullName']);
        if (name.isEmpty) continue;
        list.add(_Option(id: d.id, name: name));
      }
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    } catch (_) {
      return <_Option>[];
    }
  }

  Future<List<_Option>> _loadSubjects() async {
    final map = <String, _Option>{};

    Future<void> addFrom(CollectionReference<Map<String, dynamic>> col) async {
      try {
        final snap = await col.get();
        for (final d in snap.docs) {
          final m = d.data();
          final name = _pickString(m, ['nombre', 'name', 'titulo', 'title']);
          if (name.isEmpty) continue;
          map[d.id] = _Option(id: d.id, name: name);
        }
      } catch (_) {}
    }

    await addFrom(_asignaturasCol);
    await addFrom(_subjectsCol);

    final list = map.values.toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  // -------------------------
  // Time helpers
  // -------------------------
  static final RegExp _hhmm = RegExp(r'^(\d{1,2}):(\d{2})$');

  int? _parseMinutes(String input) {
    final s = input.trim();
    final m = _hhmm.firstMatch(s);
    if (m == null) return null;
    final hh = int.tryParse(m.group(1)!);
    final mm = int.tryParse(m.group(2)!);
    if (hh == null || mm == null) return null;
    if (hh < 0 || hh > 23) return null;
    if (mm < 0 || mm > 59) return null;
    return hh * 60 + mm;
  }

  String _fmtMinutes(int minutes) {
    final hh = (minutes ~/ 60).toString().padLeft(2, '0');
    final mm = (minutes % 60).toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  List<String> _timeOptions({
    int startHour = 7,
    int endHour = 18,
    int stepMinutes = 15,
  }) {
    final list = <String>[];
    var cur = startHour * 60;
    final end = endHour * 60;
    while (cur <= end) {
      list.add(_fmtMinutes(cur));
      cur += stepMinutes;
    }
    return list;
  }

  // -------------------------
  // Conflict checks
  // -------------------------
  bool _overlaps(int aStart, int aEnd, int bStart, int bEnd) {
    return aStart < bEnd && aEnd > bStart;
  }

  Future<List<_Conflict>> _findConflicts({
    required String gradeId,
    required int day,
    required int startMin,
    required int endMin,
    required String? teacherId,
    required String? editingDocId,
  }) async {
    final conflicts = <_Conflict>[];

    // 1) Choque dentro del MISMO grado (solapamiento)
    try {
      final q = await _itemsCol
          .where('gradeId', isEqualTo: gradeId)
          .where('day', isEqualTo: day)
          .where('enabled', isEqualTo: true)
          .get();

      for (final d in q.docs) {
        if (editingDocId != null && d.id == editingDocId) continue;
        final m = d.data();
        final s = (m['startMin'] is int) ? (m['startMin'] as int) : -1;
        final e = (m['endMin'] is int) ? (m['endMin'] as int) : -1;
        if (s < 0 || e < 0) continue;
        if (_overlaps(startMin, endMin, s, e)) {
          conflicts.add(
            _Conflict(
              type: 'grado',
              message:
                  'Choque en el mismo grado (${m['gradeName'] ?? ''}) con ${m['start'] ?? _fmtMinutes(s)}-${m['end'] ?? _fmtMinutes(e)}',
            ),
          );
        }
      }
    } catch (_) {}

    // 2) Choque del MISMO docente en OTRO grado
    if (teacherId != null && teacherId.trim().isNotEmpty) {
      try {
        final q = await _itemsCol
            .where('teacherId', isEqualTo: teacherId)
            .where('day', isEqualTo: day)
            .where('enabled', isEqualTo: true)
            .get();

        for (final d in q.docs) {
          if (editingDocId != null && d.id == editingDocId) continue;
          final m = d.data();
          final s = (m['startMin'] is int) ? (m['startMin'] as int) : -1;
          final e = (m['endMin'] is int) ? (m['endMin'] as int) : -1;
          if (s < 0 || e < 0) continue;

          if (_overlaps(startMin, endMin, s, e)) {
            final otherGrade =
                (m['gradeName'] ?? m['gradeId'] ?? 'otro grado').toString();
            conflicts.add(
              _Conflict(
                type: 'docente',
                message:
                    'El docente ya está asignado en "$otherGrade" (${m['start'] ?? _fmtMinutes(s)}-${m['end'] ?? _fmtMinutes(e)})',
              ),
            );
          }
        }
      } catch (_) {}
    }

    return conflicts;
  }

  // -------------------------
  // UI
  // -------------------------
  String _dayLabel(int day) {
    switch (day) {
      case 1:
        return 'Lun';
      case 2:
        return 'Mar';
      case 3:
        return 'Mié';
      case 4:
        return 'Jue';
      case 5:
        return 'Vie';
      default:
        return 'Día';
    }
  }

  String _dayLabelLong(int day) {
    switch (day) {
      case 1:
        return 'Lunes';
      case 2:
        return 'Martes';
      case 3:
        return 'Miércoles';
      case 4:
        return 'Jueves';
      case 5:
        return 'Viernes';
      default:
        return 'Día';
    }
  }

  Color _tabTextColor(int day) {
    // Prioridad: HOY verde, PRÓXIMO amarillo, luego el comportamiento normal
    if (day == _todayDay) return _todayGreen;
    if (day == _nextDay) return _nextYellow;
    return (day == _selectedDay) ? _blue : Colors.blueGrey.shade600;
  }

  FontWeight _tabFontWeight(int day) {
    // Que se note un poco más el seleccionado, sin romper el verde/amarillo.
    if (day == _selectedDay) return FontWeight.w900;
    return FontWeight.w800;
  }

  Widget _chip(String text, {Color? bg, Color? fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg ?? Colors.grey.shade800,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Future<void> _openEditor({
    required String gradeId,
    required String gradeName,
    String? docId,
    Map<String, dynamic>? existing,
  }) async {
    final timeOpts = _timeOptions();

    final startCtrl = TextEditingController(
      text: existing != null ? (existing['start'] ?? '').toString() : '08:00',
    );
    final endCtrl = TextEditingController(
      text: existing != null ? (existing['end'] ?? '').toString() : '08:45',
    );

    int day = existing != null && existing['day'] is int
        ? (existing['day'] as int)
        : _selectedDay;

    String? teacherId =
        existing != null ? (existing['teacherId'] as String?) : null;
    String? teacherName =
        existing != null ? (existing['teacherName'] as String?) : null;

    String? subjectId =
        existing != null ? (existing['subjectId'] as String?) : null;
    String? subjectName =
        existing != null ? (existing['subjectName'] as String?) : null;

    // ✅ Aula eliminado del UI, pero conservamos el valor anterior si existía (no perder data)
    final String preservedRoom =
        existing != null ? (existing['room'] ?? '').toString().trim() : '';

    bool saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> pickTime(TextEditingController ctrl) async {
              final parsed = _parseMinutes(ctrl.text) ?? 8 * 60;
              final initial = TimeOfDay(hour: parsed ~/ 60, minute: parsed % 60);

              final picked = await showTimePicker(
                context: ctx,
                initialTime: initial,
                helpText: 'Selecciona hora',
              );

              if (picked != null) {
                final mins = picked.hour * 60 + picked.minute;
                setLocal(() => ctrl.text = _fmtMinutes(mins));
              }
            }

            Future<void> save() async {
              final startMin = _parseMinutes(startCtrl.text);
              final endMin = _parseMinutes(endCtrl.text);

              if (startMin == null || endMin == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Hora inválida. Usa formato HH:mm')),
                );
                return;
              }
              if (endMin <= startMin) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content:
                          Text('La hora final debe ser mayor que la inicial')),
                );
                return;
              }

              // subject requerido (puedes aflojar esto si quieres)
              if ((subjectName == null || subjectName!.trim().isEmpty) &&
                  (subjectId == null || subjectId!.trim().isEmpty)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Selecciona una asignatura')),
                );
                return;
              }

              setLocal(() => saving = true);

              // Conflictos
              final conflicts = await _findConflicts(
                gradeId: gradeId,
                day: day,
                startMin: startMin,
                endMin: endMin,
                teacherId: teacherId,
                editingDocId: docId,
              );

              if (conflicts.isNotEmpty) {
                setLocal(() => saving = false);
                final msg = conflicts.map((c) => '• ${c.message}').join('\n');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('No se puede guardar:\n$msg'),
                    duration: const Duration(seconds: 5),
                  ),
                );
                return;
              }

              final now = FieldValue.serverTimestamp();

              final payload = <String, dynamic>{
                'gradeId': gradeId,
                'gradeName': gradeName,
                'day': day,
                'start': _fmtMinutes(startMin),
                'end': _fmtMinutes(endMin),
                'startMin': startMin,
                'endMin': endMin,
                'teacherId': teacherId,
                'teacherName': teacherName,
                'subjectId': subjectId,
                'subjectName': subjectName,

                // ✅ Conservado (no se muestra en UI)
                'room': preservedRoom,

                'enabled': true,
                'updatedAt': now,
              };

              try {
                if (docId == null) {
                  payload['createdAt'] = now;
                  await _itemsCol.add(payload);
                } else {
                  await _itemsCol.doc(docId).update(payload);
                }

                if (mounted) Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Calendario guardado')),
                );
              } catch (e) {
                setLocal(() => saving = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error guardando: $e')),
                );
              }
            }

            return AlertDialog(
              title: Text(docId == null ? 'Agregar bloque' : 'Editar bloque'),
              content: SizedBox(
                width: 620,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // Grado fijo
                      Row(
                        children: [
                          _chip('Grado: $gradeName',
                              bg: Colors.blue.shade50, fg: _blue),
                          const SizedBox(width: 8),
                          _chip('Día: ${_dayLabelLong(day)}',
                              bg: Colors.orange.shade50, fg: _orange),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Día
                      Row(
                        children: [
                          const SizedBox(
                              width: 110,
                              child: Text('Día',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w800))),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: day,
                              items: List.generate(5, (i) {
                                final d = i + 1;
                                return DropdownMenuItem(
                                  value: d,
                                  child: Text(_dayLabelLong(d)),
                                );
                              }),
                              onChanged: saving
                                  ? null
                                  : (v) => setLocal(() => day = v ?? day),
                              decoration: const InputDecoration(
                                  border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Horas
                      Row(
                        children: [
                          const SizedBox(
                            width: 110,
                            child: Text('Inicio',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                          Expanded(
                            child: TextFormField(
                              controller: startCtrl,
                              enabled: !saving,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: 'HH:mm (ej. 08:15)',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          DropdownButton<String>(
                            value: timeOpts.contains(startCtrl.text)
                                ? startCtrl.text
                                : null,
                            hint: const Text('15m'),
                            items: timeOpts
                                .map((t) => DropdownMenuItem(
                                    value: t, child: Text(t)))
                                .toList(),
                            onChanged: saving
                                ? null
                                : (v) {
                                    if (v == null) return;
                                    setLocal(() => startCtrl.text = v);
                                  },
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Selector',
                            onPressed: saving ? null : () => pickTime(startCtrl),
                            icon: const Icon(Icons.access_time),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          const SizedBox(
                            width: 110,
                            child: Text('Fin',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                          Expanded(
                            child: TextFormField(
                              controller: endCtrl,
                              enabled: !saving,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: 'HH:mm (ej. 09:00)',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          DropdownButton<String>(
                            value: timeOpts.contains(endCtrl.text)
                                ? endCtrl.text
                                : null,
                            hint: const Text('15m'),
                            items: timeOpts
                                .map((t) => DropdownMenuItem(
                                    value: t, child: Text(t)))
                                .toList(),
                            onChanged: saving
                                ? null
                                : (v) {
                                    if (v == null) return;
                                    setLocal(() => endCtrl.text = v);
                                  },
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Selector',
                            onPressed: saving ? null : () => pickTime(endCtrl),
                            icon: const Icon(Icons.access_time),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Asignatura
                      FutureBuilder<List<_Option>>(
                        future: _subjectsFuture,
                        builder: (_, snap) {
                          final items = snap.data ?? const <_Option>[];
                          return Row(
                            children: [
                              const SizedBox(
                                width: 110,
                                child: Text('Asignatura',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w800)),
                              ),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: (subjectId != null &&
                                          items.any((x) => x.id == subjectId))
                                      ? subjectId
                                      : null,
                                  items: items
                                      .map((s) => DropdownMenuItem(
                                            value: s.id,
                                            child: Text(s.name,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ))
                                      .toList(),
                                  onChanged: saving
                                      ? null
                                      : (v) {
                                          final sel = items
                                              .where((x) => x.id == v)
                                              .toList();
                                          setLocal(() {
                                            subjectId = v;
                                            subjectName = sel.isNotEmpty
                                                ? sel.first.name
                                                : subjectName;
                                          });
                                        },
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    hintText: 'Selecciona asignatura',
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),

                      // Docente
                      FutureBuilder<List<_Option>>(
                        future: _teachersFuture,
                        builder: (_, snap) {
                          final items = snap.data ?? const <_Option>[];
                          return Row(
                            children: [
                              const SizedBox(
                                width: 110,
                                child: Text('Docente',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w800)),
                              ),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: (teacherId != null &&
                                          items.any((x) => x.id == teacherId))
                                      ? teacherId
                                      : null,
                                  items: items
                                      .map((t) => DropdownMenuItem(
                                            value: t.id,
                                            child: Text(t.name,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ))
                                      .toList(),
                                  onChanged: saving
                                      ? null
                                      : (v) {
                                          final sel = items
                                              .where((x) => x.id == v)
                                              .toList();
                                          setLocal(() {
                                            teacherId = v;
                                            teacherName = sel.isNotEmpty
                                                ? sel.first.name
                                                : teacherName;
                                          });
                                        },
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    hintText: 'Selecciona docente (anti-choque)',
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),

                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.blueGrey.withOpacity(0.15)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.grey.shade700),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Regla: se bloquea si el mismo docente se solapa en otra clase (cualquier grado) o si el grado se solapa consigo mismo.',
                                style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(saving ? 'Guardando...' : 'Guardar'),
                  style: FilledButton.styleFrom(backgroundColor: _blue),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _disableItem(String docId) async {
    try {
      await _itemsCol.doc(docId).update({
        'enabled': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bloque deshabilitado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Widget _headerCard() {
    final name = (widget.escuela.nombre ?? '—').toString().trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(colors: [_blue, Colors.blue.shade700]),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.08),
              blurRadius: 14,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient:
                  LinearGradient(colors: [Colors.white, _orange.withOpacity(.95)]),
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'E',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900, color: _blue),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Calendario Escolar',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  name,
                  style: TextStyle(
                      color: Colors.white.withOpacity(.95),
                      fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _chip('Anti-choques',
              bg: Colors.white.withOpacity(.15), fg: Colors.white),
        ],
      ),
    );
  }

  Widget _gradeSelector(List<_Grade> grades) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.04),
              blurRadius: 10,
              offset: const Offset(0, 5)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                  colors: [_blue.withOpacity(.12), _orange.withOpacity(.12)]),
            ),
            child: const Icon(Icons.class_, color: _blue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedGradeId,
              items: grades
                  .map((g) => DropdownMenuItem(
                        value: g.id,
                        child: Text(g.name, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) {
                final sel = grades.where((x) => x.id == v).toList();
                setState(() {
                  _selectedGradeId = v;
                  _selectedGradeName =
                      sel.isNotEmpty ? sel.first.name : _selectedGradeName;
                });
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Selecciona el grado',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _daysTabs() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TabBar(
        controller: _dayTabs,
        indicatorColor: _orange,
        indicatorWeight: 3,
        tabs: List.generate(5, (i) {
          final day = i + 1;
          return Tab(
            child: Text(
              _dayLabel(day),
              style: TextStyle(
                color: _tabTextColor(day),
                fontWeight: _tabFontWeight(day),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _itemsList() {
    final gradeId = _selectedGradeId;
    final gradeName = _selectedGradeName;
    if (gradeId == null || gradeName == null) {
      return const SizedBox.shrink();
    }

    final q = _itemsCol
        .where('gradeId', isEqualTo: gradeId)
        .where('day', isEqualTo: _selectedDay)
        .where('enabled', isEqualTo: true)
        .orderBy('startMin');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (_, snap) {
        if (snap.hasError) {
          return _emptyState('Error cargando: ${snap.error}');
        }
        if (!snap.hasData) {
          return const Center(
              child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ));
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return _emptyState(
            'Sin bloques para ${_dayLabelLong(_selectedDay)}.\nUsa “Agregar” para crear el horario.',
          );
        }

        return Column(
          children: docs.map((d) {
            final m = d.data();
            final start = (m['start'] ?? '').toString();
            final end = (m['end'] ?? '').toString();
            final subj = (m['subjectName'] ?? m['subjectId'] ?? '—').toString();
            final teacher = (m['teacherName'] ?? '—').toString();

            // ✅ Colores por estado SOLO cuando se ve el día de hoy
            final isTodayView = _selectedDay == _todayDay;
            final sMin = (m['startMin'] is int) ? (m['startMin'] as int) : null;
            final eMin = (m['endMin'] is int) ? (m['endMin'] as int) : null;
            final nowMin = _nowMinutes();

            final bool isRunning = isTodayView &&
                sMin != null &&
                eMin != null &&
                nowMin >= sMin &&
                nowMin < eMin;

            final bool isPast =
                isTodayView && eMin != null && nowMin >= eMin;

            final Color leadColor = isRunning
                ? _todayGreen
                : (isPast ? _pastRed : _orange);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(.04),
                      blurRadius: 10,
                      offset: const Offset(0, 5)),
                ],
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                leading: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: leadColor.withOpacity(.14),
                  ),
                  child: Icon(Icons.schedule, color: leadColor),
                ),
                title: Text(
                  '$start - $end   •   $subj',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip('Docente: $teacher',
                          bg: Colors.blue.shade50, fg: _blue),
                      // ✅ Aula eliminado (no mostramos nada aquí)
                    ],
                  ),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') {
                      await _openEditor(
                        gradeId: gradeId,
                        gradeName: gradeName,
                        docId: d.id,
                        existing: m,
                      );
                    } else if (v == 'disable') {
                      await _disableItem(d.id);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(value: 'disable', child: Text('Deshabilitar')),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _emptyState(String msg) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(
                  color: Colors.grey.shade700, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: const Text(''), // Back, Atras
      ),
      floatingActionButton:
          (_selectedGradeId == null || _selectedGradeName == null)
              ? null
              : FloatingActionButton.extended(
                  backgroundColor: _orange,
                  onPressed: () => _openEditor(
                    gradeId: _selectedGradeId!,
                    gradeName: _selectedGradeName!,
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar'),
                ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _gradesCol.snapshots(),
        builder: (_, snap) {
          if (snap.hasError) {
            return Center(
                child: Text('Error: ${snap.error}',
                    style: const TextStyle(color: Colors.red)));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final grades = snap.data!.docs
              .map((d) {
                final m = d.data();
                final name =
                    _pickString(m, ['nombre', 'name', 'grado', 'Grado']);
                if (name.isEmpty) return null;
                final orden =
                    (m['orden'] is int) ? (m['orden'] as int) : 999999;
                return _Grade(id: d.id, name: name, orden: orden);
              })
              .whereType<_Grade>()
              .toList();

          grades.sort((a, b) {
            final o = a.orden.compareTo(b.orden);
            if (o != 0) return o;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });

          if (grades.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'No hay grados en esta escuela.\nCrea grados primero en "Grados".',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                ),
              ),
            );
          }

          // inicializar selección si está vacía
          if (_selectedGradeId == null ||
              !grades.any((g) => g.id == _selectedGradeId)) {
            final first = grades.first;
            _selectedGradeId = first.id;
            _selectedGradeName = first.name;
          }

          final content = ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _headerCard(),
              const SizedBox(height: 14),
              _gradeSelector(grades),
              const SizedBox(height: 12),
              _daysTabs(),
              const SizedBox(height: 14),
              _itemsList(),
              const SizedBox(height: 90),
            ],
          );

          if (isMobile) return content;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: content,
            ),
          );
        },
      ),
    );
  }
}

// -------------------------
// Small models
// -------------------------
class _Option {
  final String id;
  final String name;

  const _Option({required this.id, required this.name});
}

class _Grade {
  final String id;
  final String name;
  final int orden;

  const _Grade({required this.id, required this.name, required this.orden});
}

class _Conflict {
  final String type; // 'grado' | 'docente'
  final String message;

  const _Conflict({required this.type, required this.message});
}
