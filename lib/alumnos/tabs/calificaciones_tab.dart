import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CalificacionesTab extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> estRef;

  const CalificacionesTab({super.key, required this.estRef});

  @override
  State<CalificacionesTab> createState() => _CalificacionesTabState();
}

class _CalificacionesTabState extends State<CalificacionesTab> {
  String? _selectedSchoolYear;
  bool _useLegacyFallback = false;

  @override
  Widget build(BuildContext context) {
    final schoolId = widget.estRef.parent.parent?.id ?? '';

    if (_useLegacyFallback) {
      return _LegacyCalificacionesView(estRef: widget.estRef);
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: widget.estRef.get(),
      builder: (context, estSnap) {
        if (!estSnap.hasData && estSnap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final aliases = _studentAliases(widget.estRef.id, estSnap.data?.data());

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _gradesStream(schoolId, aliases),
          builder: (context, snap) {
            if (snap.hasError) {
              final message = '${snap.error}';
              if (message.contains('permission-denied')) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || _useLegacyFallback) return;
                  setState(() => _useLegacyFallback = true);
                });
                return const Center(child: CircularProgressIndicator());
              }
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Error cargando calificaciones:\n$message',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snap.data!.docs.toList()
              ..sort((a, b) =>
                  _safeTs(b.data()['updatedAt']).compareTo(_safeTs(a.data()['updatedAt'])));

            if (docs.isEmpty) {
              return _LegacyCalificacionesView(estRef: widget.estRef);
            }

            final items = docs.map((d) => _fromDoc(d.data())).toList();
            final availableYears = _availableSchoolYears(items);
            final effectiveYear = _resolveSelectedYear(availableYears);
            final filteredItems = items
                .where((item) => item.schoolYearLabel == effectiveYear)
                .toList();
            final summary = _buildSummary(filteredItems);

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
              itemCount: filteredItems.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Column(
                    children: [
                      if (availableYears.isNotEmpty)
                        _YearFilterCard(
                          selectedYear: effectiveYear,
                          availableYears: availableYears,
                          onChanged: (value) {
                            setState(() => _selectedSchoolYear = value);
                          },
                        ),
                      if (availableYears.isNotEmpty) const SizedBox(height: 10),
                      _SummaryCard(
                        summary: summary,
                        schoolYearLabel: effectiveYear,
                      ),
                    ],
                  );
                }
                final item = filteredItems[i - 1];
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(milliseconds: 260 + (i * 45)),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, child) {
                      return Opacity(
                        opacity: t,
                        child: Transform.translate(
                          offset: Offset(0, (1 - t) * 12),
                          child: child,
                        ),
                      );
                    },
                    child: _SubjectCard(item: item),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _resolveSelectedYear(List<String> availableYears) {
    if (availableYears.isEmpty) return '';
    if (_selectedSchoolYear != null && availableYears.contains(_selectedSchoolYear)) {
      return _selectedSchoolYear!;
    }
    final latest = availableYears.first;
    if (_selectedSchoolYear != latest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedSchoolYear = latest);
      });
    }
    return latest;
  }
}

Stream<QuerySnapshot<Map<String, dynamic>>> _gradesStream(
  String schoolId,
  List<String> aliases,
) {
  final clean = aliases.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
  final col = FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('calificaciones_v2');

  if (clean.length <= 1) {
    final studentId = clean.isEmpty ? '' : clean.first;
    return col.where('studentId', isEqualTo: studentId).limit(300).snapshots();
  }

  return col.where('studentId', whereIn: clean.take(10).toList()).limit(300).snapshots();
}

List<String> _studentAliases(String primaryId, Map<String, dynamic>? data) {
  final out = <String>{
    primaryId.trim(),
    (data?['idGlobal'] ?? '').toString().trim(),
    (data?['fx'] ?? '').toString().trim(),
    (data?['studentId'] ?? '').toString().trim(),
    (data?['alumnoId'] ?? '').toString().trim(),
  };
  out.removeWhere((e) => e.isEmpty);
  return out.toList();
}

class _LegacyCalificacionesView extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;

  const _LegacyCalificacionesView({required this.estRef});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: estRef
          .collection('calificaciones')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Error cargando calificaciones:\n${snap.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('Aun no hay calificaciones.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final d = docs[i].data();
            final titulo = (d['titulo'] ??
                    d['asignatura'] ??
                    d['materia'] ??
                    d['subjectName'] ??
                    'Calificacion')
                .toString();
            final p = d['puntuacion'];
            final mx = d['max'];

            String nota = 'Sin nota';
            if (p is num && mx is num && mx > 0) {
              final pct = (p.toDouble() / mx.toDouble()) * 100.0;
              nota = '${pct.toStringAsFixed(1)}%';
            } else if (p != null) {
              nota = p.toString();
            }

            final fecha = _safeTs(d['createdAt']);

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: _gradeColor(_toDouble(p)).withValues(alpha: 0.12),
                    child: Icon(
                      Icons.grade_rounded,
                      color: _gradeColor(_toDouble(p)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Actualizado: ${_fmtDate(fecha.toDate())}',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _gradeColor(_toDouble(p)).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      nota,
                      style: TextStyle(
                        color: _gradeColor(_toDouble(p)),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _GradeItem {
  final String subject;
  final String gradeName;
  final int? year;
  final String schoolYearLabel;
  final DateTime updatedAt;
  final double? finalGrade;
  final Map<int, double> periodAverages;

  _GradeItem({
    required this.subject,
    required this.gradeName,
    required this.year,
    required this.schoolYearLabel,
    required this.updatedAt,
    required this.finalGrade,
    required this.periodAverages,
  });
}

class _SummaryData {
  final double? globalAverage;
  final int subjects;
  final String bestSubject;
  final double? bestValue;
  final String weakestSubject;
  final double? weakestValue;

  const _SummaryData({
    required this.globalAverage,
    required this.subjects,
    required this.bestSubject,
    required this.bestValue,
    required this.weakestSubject,
    required this.weakestValue,
  });
}

_GradeItem _fromDoc(Map<String, dynamic> d) {
  final subject = (d['subjectName'] ?? d['asignatura'] ?? d['materia'] ?? d['titulo'] ?? 'Asignatura')
      .toString();
  final gradeName = (d['gradeName'] ?? '').toString();
  final year = d['yearEnd'] is int
      ? d['yearEnd'] as int
      : (d['year'] is int ? d['year'] as int : null);
  final schoolYearLabel = _schoolYearFromDoc(d);
  final updatedAt = _safeTs(d['updatedAt']).toDate();

  final scores = (d['scores'] is Map)
      ? (d['scores'] as Map).cast<String, dynamic>()
      : const <String, dynamic>{};
  final computed = (d['computed'] is Map)
      ? (d['computed'] as Map).cast<String, dynamic>()
      : const <String, dynamic>{};

  final periodAverages = _computePeriodAverages(scores);
  final finalFromComputed = _toDouble(computed['final']);
  final finalFromPeriods =
      periodAverages.isEmpty ? null : _avg(periodAverages.values.toList());

  return _GradeItem(
    subject: subject,
    gradeName: gradeName,
    year: year,
    schoolYearLabel: schoolYearLabel,
    updatedAt: updatedAt,
    finalGrade: finalFromComputed ?? finalFromPeriods,
    periodAverages: periodAverages,
  );
}

String _schoolYearFromDoc(Map<String, dynamic> d) {
  final schoolYear = (d['schoolYear'] ?? '').toString().trim();
  if (schoolYear.isNotEmpty) return schoolYear;

  final year = d['year'];
  if (year is String && year.contains('-')) return year;
  if (year is int) return '${year - 1}-$year';

  final yearEnd = d['yearEnd'];
  if (yearEnd is int) return '${yearEnd - 1}-$yearEnd';

  return 'Sin periodo';
}

List<String> _availableSchoolYears(List<_GradeItem> items) {
  final years = items.map((e) => e.schoolYearLabel).toSet().toList();
  years.sort((a, b) => _schoolYearSortKey(b).compareTo(_schoolYearSortKey(a)));
  return years;
}

int _schoolYearSortKey(String value) {
  final match = RegExp(r'(\d{4})\s*-\s*(\d{4})').firstMatch(value);
  if (match != null) {
    return int.tryParse(match.group(2) ?? '') ?? -1;
  }
  return int.tryParse(value) ?? -1;
}

Map<int, double> _computePeriodAverages(Map<String, dynamic> scores) {
  final byPeriod = <int, List<double>>{};

  scores.forEach((_, compVal) {
    if (compVal is! Map) return;
    final comp = compVal.cast<String, dynamic>();

    for (final e in comp.entries) {
      if (!e.key.startsWith('p')) continue;
      final pNum = int.tryParse(e.key.substring(1));
      if (pNum == null) continue;

      final p = _toDouble(e.value);
      final rp = _toDouble(comp['rp$pNum']);
      final effective = _effectiveScore(p, rp);
      if (effective == null) continue;

      byPeriod.putIfAbsent(pNum, () => <double>[]).add(effective);
    }
  });

  final out = <int, double>{};
  for (final e in byPeriod.entries) {
    if (e.value.isNotEmpty) {
      out[e.key] = _avg(e.value);
    }
  }

  final keys = out.keys.toList()..sort();
  return {for (final k in keys) k: out[k]!};
}

double? _effectiveScore(double? p, double? rp) {
  if (p == null) return rp;
  if (p >= 70) return p;
  if (rp != null && rp > p) return rp;
  return p;
}

_SummaryData _buildSummary(List<_GradeItem> items) {
  final valid = items.where((e) => e.finalGrade != null).toList();
  final global = valid.isEmpty ? null : _avg(valid.map((e) => e.finalGrade!).toList());

  valid.sort((a, b) => (b.finalGrade!).compareTo(a.finalGrade!));
  final best = valid.isEmpty ? null : valid.first;
  final weak = valid.isEmpty ? null : valid.last;

  return _SummaryData(
    globalAverage: global,
    subjects: items.length,
    bestSubject: best?.subject ?? '-',
    bestValue: best?.finalGrade,
    weakestSubject: weak?.subject ?? '-',
    weakestValue: weak?.finalGrade,
  );
}

class _YearFilterCard extends StatelessWidget {
  final String selectedYear;
  final List<String> availableYears;
  final ValueChanged<String?> onChanged;

  const _YearFilterCard({
    required this.selectedYear,
    required this.availableYears,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_month_rounded, color: Colors.blue.shade700),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Periodo escolar',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedYear,
              borderRadius: BorderRadius.circular(14),
              items: availableYears
                  .map(
                    (year) => DropdownMenuItem<String>(
                      value: year,
                      child: Text(year),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final _SummaryData summary;
  final String schoolYearLabel;

  const _SummaryCard({
    required this.summary,
    required this.schoolYearLabel,
  });

  @override
  Widget build(BuildContext context) {
    final avg = summary.globalAverage;
    final title = _motivationTitle(avg);
    final subtitle = _motivationText(avg);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF0B5BA8), Color(0xFF2A8EDB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatChip(
                label: 'Periodo',
                value: schoolYearLabel,
              ),
              _StatChip(
                label: 'Promedio general',
                value: avg == null ? '-' : avg.toStringAsFixed(1),
              ),
              _StatChip(
                label: 'Asignaturas',
                value: summary.subjects.toString(),
              ),
              _StatChip(
                label: 'Mejor',
                value: summary.bestValue == null
                    ? '-'
                    : '${summary.bestSubject} ${summary.bestValue!.toStringAsFixed(1)}',
              ),
              _StatChip(
                label: 'A mejorar',
                value: summary.weakestValue == null
                    ? '-'
                    : '${summary.weakestSubject} ${summary.weakestValue!.toStringAsFixed(1)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.17),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  final _GradeItem item;

  const _SubjectCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final finalGrade = item.finalGrade;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _gradeColor(finalGrade).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.menu_book_rounded, color: _gradeColor(finalGrade)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.subject,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.gradeName.isEmpty ? 'Sin grado' : item.gradeName,
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _FinalBadge(value: finalGrade),
            ],
          ),
          const SizedBox(height: 10),
          if (item.periodAverages.isEmpty)
            const Text('No hay periodos registrados aun.')
          else
            Column(
              children: item.periodAverages.entries
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PeriodBar(period: e.key, value: e.value),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _FinalBadge extends StatelessWidget {
  final double? value;

  const _FinalBadge({required this.value});

  @override
  Widget build(BuildContext context) {
    final c = _gradeColor(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value == null ? 'Final -' : 'Final ${value!.toStringAsFixed(1)}',
        style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }
}

class _PeriodBar extends StatelessWidget {
  final int period;
  final double value;

  const _PeriodBar({required this.period, required this.value});

  @override
  Widget build(BuildContext context) {
    final color = _gradeColor(value);
    final normalized = (value.clamp(0, 100)) / 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Periodo $period', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            const Spacer(),
            Text(value.toStringAsFixed(1), style: TextStyle(fontWeight: FontWeight.w900, color: color)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: normalized),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, t, __) {
              return LinearProgressIndicator(
                value: t,
                minHeight: 9,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              );
            },
          ),
        ),
      ],
    );
  }
}

Timestamp _safeTs(dynamic v) {
  if (v is Timestamp) return v;
  return Timestamp(0, 0);
}

String _fmtDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final yyyy = d.year.toString();
  return '$dd/$mm/$yyyy';
}

double? _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return null;
}

double _avg(List<double> values) =>
    values.reduce((a, b) => a + b) / values.length;

Color _gradeColor(double? v) {
  if (v == null) return Colors.blueGrey;
  if (v >= 90) return const Color(0xFF2E7D32);
  if (v >= 80) return const Color(0xFF558B2F);
  if (v >= 70) return const Color(0xFFE6A700);
  return const Color(0xFFC62828);
}

String _motivationTitle(double? avg) {
  if (avg == null) return 'Arranquemos con fuerza';
  if (avg >= 90) return 'Nivel excelente';
  if (avg >= 80) return 'Muy buen camino';
  if (avg >= 70) return 'Buen avance, sigue subiendo';
  return 'Plan de mejora activo';
}

String _motivationText(double? avg) {
  if (avg == null) return 'A medida que entren notas, aqui veras tu progreso por periodo.';
  if (avg >= 90) return 'Mantente constante. Estas entre los mejores resultados.';
  if (avg >= 80) return 'Con un pequeno esfuerzo adicional puedes pasar al nivel excelente.';
  if (avg >= 70) return 'Enfocate en la asignatura mas baja para subir rapido el promedio.';
  return 'No te detengas: trabaja por periodos y veras mejoras claras en poco tiempo.';
}
