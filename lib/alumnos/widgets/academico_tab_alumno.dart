import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AcademicoTabAlumno extends StatefulWidget {
  /// ✅ Debe ser ref tipo: schools/{schoolId}/alumnos/{alumnoId}
  final DocumentReference<Map<String, dynamic>> alumnoRef;

  const AcademicoTabAlumno({
    super.key,
    required this.alumnoRef,
  });

  @override
  State<AcademicoTabAlumno> createState() => _AcademicoTabAlumnoState();
}

class _AcademicoTabAlumnoState extends State<AcademicoTabAlumno>
    with TickerProviderStateMixin {
  // UI consistente
  static const Color _blue = Color.fromARGB(255, 21, 101, 192);
  static const Color _orange = Color.fromARGB(255, 255, 193, 7);

  static const Color _todayGreen = Color(0xFF2ECC71);
  static const Color _nextYellow = Color(0xFFFBC02D);
  static const Color _pastRed = Color(0xFFFF5252);

  Timer? _clockTimer;

  int _selectedDay = 1; // 1=Lun..5=Vie
  late final TabController _dayTabs;
  late final int _todayDay;
  late final int _nextDay;

  // 📌 Tu Firestore (según screenshot): schools/{schoolId}/calendario_escolar_items
  static const String _calendarCollection = 'calendario_escolar_items';

  // 📌 Campos esperados en calendario_escolar_items
  // - gradeId: docId del grado (string)
  // - day: 1..5 (int)
  // - startMin/endMin: int
  static const String _gradeField = 'gradeId'; // si usas "gradoId", cámbialo aquí
  static const String _dayField = 'day';       // si usas "dia", cámbialo aquí

  int _clampToSchoolWeek(int weekday) {
    if (weekday >= 1 && weekday <= 5) return weekday;
    return 1;
  }

  int _calcNextDay(int day) => (day == 5) ? 1 : (day + 1);

  int _nowMinutes() {
    final now = DateTime.now();
    return now.hour * 60 + now.minute;
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
        overflow: TextOverflow.ellipsis,
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
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _readString(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  static bool _isEnabled(Map<String, dynamic> data) {
    final v = data['enabled'];
    if (v is bool) return v == true;
    return true; // si no existe, asumimos TRUE
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Detecta doc de escuela desde schools/{schoolId}/alumnos/{alumnoId}
    final schoolDocDynamic = widget.alumnoRef.parent.parent;
    if (schoolDocDynamic == null) {
      return const Center(
        child: Text('No se pudo detectar la escuela del alumno.'),
      );
    }

    final DocumentReference schoolDoc = schoolDocDynamic;

    final calendarCol = schoolDoc.collection(_calendarCollection);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: widget.alumnoRef.snapshots(),
      builder: (context, alumnoSnap) {
        if (alumnoSnap.hasError) {
          return Center(
            child: Text('Error cargando alumno: ${alumnoSnap.error}'),
          );
        }
        if (!alumnoSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final alumnoData = alumnoSnap.data!.data() ?? {};

        // ✅ Prioridad: gradoId real (docId del grado) si existe
        final gradoId = _readString(alumnoData, const [
          'gradoId',
          'gradeId',
          'gradoDocId',
          'gradeDocId',
        ]);

        // ✅ Solo para mostrar en UI (nombre)
        final gradoNombre = _readString(alumnoData, const [
          'grado',
          'grade',
          'gradoName',
          'gradeName',
        ]);

        if (gradoId.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: _emptyState(
              'Este alumno no tiene "gradeId/gradoId" guardado.\n\n'
              'Solución:\n'
              '• Al registrar alumno guarda:\n'
              '  - gradeId = docId real del grado\n'
              '  - (y si quieres también gradoId = mismo valor)\n\n'
              'No borres "grado" ni "gradoKey".',
            ),
          );
        }

        // ✅ Query por gradeId + day, ordenado por startMin
        // ⚠️ No filtramos enabled aquí, porque si el doc no tiene enabled, la query no lo devuelve.
        final q = calendarCol
            .where(_gradeField, isEqualTo: gradoId)
            .where(_dayField, isEqualTo: _selectedDay)
            .orderBy('startMin');

        final isTodayView = _selectedDay == _todayDay;
        final nowMin = _nowMinutes();

        return ListView(
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
                    offset: const Offset(0, 6),
                  ),
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
                    child: const Center(
                      child: Icon(Icons.schedule, color: _blue),
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
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          gradoNombre.isNotEmpty ? gradoNombre : 'Grado asignado',
                          style: TextStyle(
                            color: Colors.white.withOpacity(.95),
                            fontWeight: FontWeight.w800,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _chip(
                    'Solo lectura',
                    bg: Colors.white.withOpacity(.15),
                    fg: Colors.white,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            _daysTabs(),
            const SizedBox(height: 14),

            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: q.snapshots(),
              builder: (context, calSnap) {
                if (calSnap.hasError) {
                  return _emptyState(
                    'Error cargando horario.\n${calSnap.error}',
                  );
                }
                if (!calSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = calSnap.data!.docs;

                // ✅ Filtrar enabled en memoria (si falta enabled, se asume true)
                final filtered =
                    docs.where((d) => _isEnabled(d.data())).toList();

                if (filtered.isEmpty) {
                  return _emptyState(
                    'No tienes clases para este ${_dayLabelLong(_selectedDay)}.',
                  );
                }

                return Column(
                  children: filtered.map((d) {
                    final m = d.data();

                    final start = (m['start'] ?? '').toString().trim();
                    final end = (m['end'] ?? '').toString().trim();

                    final subj =
                        (m['subjectName'] ?? m['subjectId'] ?? '—').toString();
                    final teacher =
                        (m['teacherName'] ?? m['teacherId'] ?? '—').toString();

                    final sMin = (m['startMin'] is int) ? (m['startMin'] as int) : null;
                    final eMin = (m['endMin'] is int) ? (m['endMin'] as int) : null;

                    final bool isRunning = isTodayView &&
                        sMin != null &&
                        eMin != null &&
                        nowMin >= sMin &&
                        nowMin < eMin;

                    final bool isPast = isTodayView && eMin != null && nowMin >= eMin;

                    final Color leadColor =
                        isRunning ? _todayGreen : (isPast ? _pastRed : _orange);

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
                            offset: const Offset(0, 5),
                          ),
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
                          child: Icon(Icons.class_, color: leadColor),
                        ),
                        title: Text(
                          '${start.isEmpty ? "—" : start} - ${end.isEmpty ? "—" : end}   •   $subj',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _chip(
                                'Docente: $teacher',
                                bg: Colors.blue.shade50,
                                fg: _blue,
                              ),
                              if (gradoNombre.isNotEmpty)
                                _chip(
                                  'Grado: $gradoNombre',
                                  bg: _orange.withOpacity(.12),
                                  fg: _blue,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
