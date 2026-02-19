import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';

class CalendarioEscolarDocenteScreen extends StatefulWidget {
  final Escuela escuela;
  final String schoolId;

  /// Opcional: para abrir ya filtrado desde el panel docente
  final String? initialGradeLabel;
  final String? initialGradeKey; // puede ser docId o gradoKey (si lo usas)

  const CalendarioEscolarDocenteScreen({
    super.key,
    required this.escuela,
    required this.schoolId,
    this.initialGradeLabel,
    this.initialGradeKey,
  });

  @override
  State<CalendarioEscolarDocenteScreen> createState() =>
      _CalendarioEscolarDocenteScreenState();
}

class _CalendarioEscolarDocenteScreenState
    extends State<CalendarioEscolarDocenteScreen> with TickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // UI clara (consistente con panel docentes)
  static const Color _blue = Color.fromARGB(255, 21, 101, 192);
  static const Color _orange = Color.fromARGB(255, 255, 193, 7);

  // Estados (claros)
  static const Color _todayGreen = Color(0xFF2ECC71);
  static const Color _nextYellow = Color(0xFFFBC02D);
  static const Color _pastRed = Color(0xFFFF5252);

  Timer? _clockTimer;

  CollectionReference<Map<String, dynamic>> get _gradesCol =>
      _db.collection('schools').doc(widget.schoolId).collection('grados');

  CollectionReference<Map<String, dynamic>> get _itemsCol => _db
      .collection('schools')
      .doc(widget.schoolId)
      .collection('calendario_escolar_items');

  String? _selectedGradeDocId;
  String? _selectedGradeName;

  int _selectedDay = 1; // 1=Lun..5=Vie
  late final TabController _dayTabs;

  late final int _todayDay;
  late final int _nextDay;

  int _clampToSchoolWeek(int weekday) {
    if (weekday >= 1 && weekday <= 5) return weekday;
    return 1;
  }

  int _calcNextDay(int day) => (day == 5) ? 1 : (day + 1);

  int _nowMinutes() {
    final now = DateTime.now();
    return now.hour * 60 + now.minute;
  }

  String _pickString(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  @override
  void initState() {
    super.initState();

    _todayDay = _clampToSchoolWeek(DateTime.now().weekday);
    _nextDay = _calcNextDay(_todayDay);
    _selectedDay = _todayDay;

    _dayTabs =
        TabController(length: 5, vsync: this, initialIndex: _todayDay - 1);
    _dayTabs.addListener(() {
      if (_dayTabs.indexIsChanging) return;
      setState(() => _selectedDay = _dayTabs.index + 1);
    });

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
    if (day == _todayDay) return _todayGreen;
    if (day == _nextDay) return _nextYellow;
    return (day == _selectedDay) ? _blue : Colors.blueGrey.shade600;
  }

  FontWeight _tabFontWeight(int day) {
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
    final nombreEscuela = (widget.escuela.nombre ?? 'EduPro').trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: const Text(''),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _gradesCol.snapshots(),
        builder: (_, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                'Error cargando grados: ${snap.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final grades = snap.data!.docs.map((d) {
            final m = d.data();
            final label = _pickString(m, ['nombre', 'name', 'grado', 'label']);
            final gradoKey = (m['gradoKey'] ?? m['key'] ?? '').toString().trim();
            final orden = (m['orden'] is int) ? (m['orden'] as int) : 999999;

            return _GradeOpt(
              docId: d.id,
              label: label.isNotEmpty ? label : d.id,
              gradoKey: gradoKey,
              orden: orden,
            );
          }).toList();

          grades.sort((a, b) {
            final o = a.orden.compareTo(b.orden);
            if (o != 0) return o;
            return a.label.toLowerCase().compareTo(b.label.toLowerCase());
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

          // ✅ init robusto: intenta matchear initialGradeKey por docId o gradoKey; si no, por label
          if (_selectedGradeDocId == null ||
              !grades.any((g) => g.docId == _selectedGradeDocId)) {
            _GradeOpt found = grades.first;

            final initKey = (widget.initialGradeKey ?? '').trim();
            final initLabel = (widget.initialGradeLabel ?? '').trim();

            if (initKey.isNotEmpty) {
              found = grades.firstWhere(
                (g) =>
                    g.docId == initKey ||
                    (g.gradoKey.isNotEmpty && g.gradoKey == initKey),
                orElse: () => grades.first,
              );
            } else if (initLabel.isNotEmpty) {
              found = grades.firstWhere(
                (g) => g.label.toLowerCase() == initLabel.toLowerCase(),
                orElse: () => grades.first,
              );
            }

            _selectedGradeDocId = found.docId;
            _selectedGradeName = found.label;
          }

          final gradeId = _selectedGradeDocId!;
          final gradeName = _selectedGradeName ?? grades.first.label;

          final q = _itemsCol
              .where('gradeId', isEqualTo: gradeId)
              .where('day', isEqualTo: _selectedDay)
              .where('enabled', isEqualTo: true)
              .orderBy('startMin');

          final content = ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header
              Container(
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
                        gradient: LinearGradient(
                          colors: [Colors.white, _orange.withOpacity(.95)],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          nombreEscuela.isNotEmpty
                              ? nombreEscuela[0].toUpperCase()
                              : 'E',
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: _blue),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Horario de clases',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            nombreEscuela,
                            style: TextStyle(
                                color: Colors.white.withOpacity(.95),
                                fontWeight: FontWeight.w800),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    _chip('Solo lectura',
                        bg: Colors.white.withOpacity(.15), fg: Colors.white),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Selector grado
              Container(
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
                        color: _orange.withOpacity(.12),
                        border: Border.all(color: _orange.withOpacity(.25)),
                      ),
                      child: const Icon(Icons.class_, color: _blue),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: gradeId,
                        isExpanded: true,
                        items: grades
                            .map((g) => DropdownMenuItem(
                                  value: g.docId,
                                  child: Text(g.label,
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          final sel = grades.where((x) => x.docId == v).toList();
                          setState(() {
                            _selectedGradeDocId = v;
                            _selectedGradeName =
                                sel.isNotEmpty ? sel.first.label : gradeName;
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
              ),

              const SizedBox(height: 12),
              _daysTabs(),
              const SizedBox(height: 14),

              // Lista items
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: q.snapshots(),
                builder: (_, snapItems) {
                  if (snapItems.hasError) {
                    return _emptyState('Error cargando: ${snapItems.error}');
                  }
                  if (!snapItems.hasData) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  final docs = snapItems.data!.docs;
                  if (docs.isEmpty) {
                    return _emptyState(
                      'No tienes clases para este ${_dayLabelLong(_selectedDay)}.\nSelecciona otro día o grado.',
                    );
                  }

                  final isTodayView = _selectedDay == _todayDay;
                  final nowMin = _nowMinutes();

                  return Column(
                    children: docs.map((d) {
                      final m = d.data();
                      final start = (m['start'] ?? '').toString();
                      final end = (m['end'] ?? '').toString();
                      final subj =
                          (m['subjectName'] ?? m['subjectId'] ?? '—').toString();
                      final teacher = (m['teacherName'] ?? '—').toString();

                      final sMin = (m['startMin'] is int)
                          ? (m['startMin'] as int)
                          : null;
                      final eMin =
                          (m['endMin'] is int) ? (m['endMin'] as int) : null;

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
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
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
                                _chip('Grado: $gradeName',
                                    bg: _orange.withOpacity(.12), fg: _blue),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),

              const SizedBox(height: 90),
            ],
          );

          final isMobile = MediaQuery.of(context).size.width < 900;
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

class _GradeOpt {
  final String docId;
  final String label;
  final String gradoKey;
  final int orden;

  const _GradeOpt({
    required this.docId,
    required this.label,
    required this.gradoKey,
    required this.orden,
  });
}
