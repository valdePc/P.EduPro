// lib/admin_escolar/screens/A_MonitoreoDocentes.dart
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

/// ------------------------------------------------------------
/// A_MonitoreoDocentes.dart (Admin Escolar)
/// ------------------------------------------------------------
/// Estructura usada:
/// schools/{schoolId}
///   config_academica/periodos/lista/{periodoId}  (P1..P4)
///   planificaciones_anuales/{planId}             (por año + grado)
///   teachers/{teacherId}
///     curricular_progress/{unidadId}
///     attendance/{dateId}
///     admin_feedback/{feedbackId}
///     tasks/{taskId} (opcional)
///
/// Nota importante:
/// Para que el mapeo sea perfecto, cada unidad en planificación anual debería tener:
///   - unidadId (o id) estable
///   - periodoId: "P1".."P4"
///   - indicadores (lista de ids o lista de objetos con id)
/// ------------------------------------------------------------

class AMonitoreoDocentes extends StatefulWidget {
  final Escuela escuela;
  final String? schoolIdOverride;

  const AMonitoreoDocentes({
    Key? key,
    required this.escuela,
    this.schoolIdOverride,
  }) : super(key: key);

  @override
  State<AMonitoreoDocentes> createState() => _AMonitoreoDocentesState();
}

class _AMonitoreoDocentesState extends State<AMonitoreoDocentes> {
  final _service = MonitoreoService();
  final _searchCtrl = TextEditingController();

  String? _schoolId;
  bool _resolvingSchool = true;
  String? _resolveError;

  String _statusFilter = 'Todos';
  TeacherSummary? _selected;

  int _anio = DateTime.now().year;
  DateTime _mes = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _resolveSchoolId();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolveSchoolId() async {
    setState(() {
      _resolvingSchool = true;
      _resolveError = null;
    });

    try {
      final override = widget.schoolIdOverride?.trim();
      final resolved = (override != null && override.isNotEmpty)
          ? override
          : normalizeSchoolIdFromEscuela(widget.escuela);

      if (resolved.trim().isEmpty) {
        throw Exception('schoolId vacío (override y normalización fallaron).');
      }

      setState(() {
        _schoolId = resolved.trim();
        _resolvingSchool = false;
      });
    } catch (e) {
      setState(() {
        _resolveError = e.toString();
        _resolvingSchool = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoreo de Docentes'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            onPressed: _resolveSchoolId,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _resolvingSchool
          ? const Center(child: CircularProgressIndicator())
          : (_resolveError != null || _schoolId == null)
              ? _ErrorState(
                  title: 'No se pudo resolver el colegio',
                  message: _resolveError ?? 'schoolId es null.',
                  onRetry: _resolveSchoolId,
                )
              : LayoutBuilder(
                  builder: (context, c) {
                    final wide = c.maxWidth >= 980;
                    return wide
                        ? Row(
                            children: [
                              SizedBox(
                                width: 380,
                                child: _TeachersPane(
                                  theme: theme,
                                  schoolId: _schoolId!,
                                  service: _service,
                                  searchCtrl: _searchCtrl,
                                  statusFilter: _statusFilter,
                                  onStatusFilterChanged: (v) =>
                                      setState(() => _statusFilter = v),
                                  selectedId: _selected?.teacherId,
                                  onSelect: (t) =>
                                      setState(() => _selected = t),
                                ),
                              ),
                              const VerticalDivider(width: 1),
                              Expanded(
                                child: _TeacherDetailPane(
                                  theme: theme,
                                  schoolId: _schoolId!,
                                  teacher: _selected,
                                  anio: _anio,
                                  mes: _mes,
                                  onChangeAnio: (v) => setState(() => _anio = v),
                                  onChangeMes: (v) => setState(() => _mes = v),
                                  service: _service,
                                ),
                              ),
                            ],
                          )
                        : _TeachersPaneMobile(
                            theme: theme,
                            schoolId: _schoolId!,
                            service: _service,
                            searchCtrl: _searchCtrl,
                            statusFilter: _statusFilter,
                            onStatusFilterChanged: (v) =>
                                setState(() => _statusFilter = v),
                            onSelect: (t) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => _TeacherDetailPage(
                                    schoolId: _schoolId!,
                                    teacher: t,
                                    anio: _anio,
                                    mes: _mes,
                                    service: _service,
                                  ),
                                ),
                              );
                            },
                          );
                  },
                ),
      floatingActionButton: (_schoolId != null && _selected != null)
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Agregar observación'),
              onPressed: () => _openAddFeedback(
                context: context,
                schoolId: _schoolId!,
                teacherId: _selected!.teacherId,
                teacherName: _selected!.nombreCompleto,
                service: _service,
              ),
            )
          : null,
    );
  }

  Future<void> _openAddFeedback({
    required BuildContext context,
    required String schoolId,
    required String teacherId,
    required String teacherName,
    required MonitoreoService service,
  }) async {
    final detailsCtrl = TextEditingController();
    String tipo = 'mejora';

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Observación para $teacherName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: tipo,
              decoration: const InputDecoration(
                labelText: 'Tipo',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'positivo', child: Text('Positivo')),
                DropdownMenuItem(value: 'mejora', child: Text('Mejora')),
                DropdownMenuItem(value: 'urgente', child: Text('Urgente')),
              ],
              onChanged: (v) => tipo = v ?? 'mejora',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: detailsCtrl,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Detalles',
                hintText: 'Describe la observación…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (detailsCtrl.text.trim().length < 5) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Escribe un poco más de detalle.')),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await service.addAdminFeedback(
          schoolId: schoolId,
          teacherId: teacherId,
          tipo: tipo,
          detalles: detailsCtrl.text.trim(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Observación guardada.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }

    detailsCtrl.dispose();
  }
}

/// ------------------------------
/// Mobile: lista -> detalle en otra ruta
/// ------------------------------
class _TeachersPaneMobile extends StatelessWidget {
  final ThemeData theme;
  final String schoolId;
  final MonitoreoService service;
  final TextEditingController searchCtrl;

  final String statusFilter;
  final ValueChanged<String> onStatusFilterChanged;

  final ValueChanged<TeacherSummary> onSelect;

  const _TeachersPaneMobile({
    required this.theme,
    required this.schoolId,
    required this.service,
    required this.searchCtrl,
    required this.statusFilter,
    required this.onStatusFilterChanged,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return _TeachersPane(
      theme: theme,
      schoolId: schoolId,
      service: service,
      searchCtrl: searchCtrl,
      statusFilter: statusFilter,
      onStatusFilterChanged: onStatusFilterChanged,
      selectedId: null,
      onSelect: onSelect,
    );
  }
}

class _TeacherDetailPage extends StatelessWidget {
  final String schoolId;
  final TeacherSummary teacher;
  final int anio;
  final DateTime mes;
  final MonitoreoService service;

  const _TeacherDetailPage({
    required this.schoolId,
    required this.teacher,
    required this.anio,
    required this.mes,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(teacher.nombreCompleto)),
      body: _TeacherDetailPane(
        theme: theme,
        schoolId: schoolId,
        teacher: teacher,
        anio: anio,
        mes: mes,
        onChangeAnio: (_) {},
        onChangeMes: (_) {},
        service: service,
        readOnlyFilters: true,
      ),
    );
  }
}

/// ------------------------------
/// Lista de docentes
/// ------------------------------
class _TeachersPane extends StatelessWidget {
  final ThemeData theme;
  final String schoolId;
  final MonitoreoService service;
  final TextEditingController searchCtrl;

  final String statusFilter;
  final ValueChanged<String> onStatusFilterChanged;

  final String? selectedId;
  final ValueChanged<TeacherSummary> onSelect;

  const _TeachersPane({
    required this.theme,
    required this.schoolId,
    required this.service,
    required this.searchCtrl,
    required this.statusFilter,
    required this.onStatusFilterChanged,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _PaneHeader(
          title: 'Docentes',
          subtitle: 'Semáforo por KPIs + detalle por periodos',
          trailing: Icon(Icons.school_outlined),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Column(
            children: [
              TextField(
                controller: searchCtrl,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Buscar por nombre, grado o nivel…',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: searchCtrl,
                    builder: (_, v, __) {
                      if (v.text.trim().isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        tooltip: 'Limpiar',
                        onPressed: () => searchCtrl.clear(),
                        icon: const Icon(Icons.close),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: statusFilter,
                decoration: const InputDecoration(
                  labelText: 'Filtro de estado',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                  DropdownMenuItem(value: 'Verde', child: Text('Verde')),
                  DropdownMenuItem(value: 'Amarillo', child: Text('Amarillo')),
                  DropdownMenuItem(value: 'Rojo', child: Text('Rojo')),
                ],
                onChanged: (v) => onStatusFilterChanged(v ?? 'Todos'),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<TeacherSummary>>(
            stream: service.streamTeachers(schoolId),
            builder: (context, snap) {
              if (snap.hasError) {
                return _InlineError(message: 'Error cargando docentes: ${snap.error}');
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              var list = snap.data!;
              final q = searchCtrl.text.trim().toLowerCase();
              if (q.isNotEmpty) {
                list = list.where((t) {
                  final hay = [
                    t.nombreCompleto,
                    t.gradoAsignado,
                    t.nivelAsignado,
                  ].join(' ').toLowerCase();
                  return hay.contains(q);
                }).toList();
              }

              if (statusFilter != 'Todos') {
                list = list.where((t) {
                  final s = t.semaforo.name;
                  if (statusFilter == 'Verde') return s == 'green';
                  if (statusFilter == 'Amarillo') return s == 'yellow';
                  if (statusFilter == 'Rojo') return s == 'red';
                  return true;
                }).toList();
              }

              if (list.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('No hay docentes que coincidan con el filtro.'),
                  ),
                );
              }

              return ListView.separated(
                itemCount: list.length,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final t = list[i];
                  final selected = selectedId != null && selectedId == t.teacherId;

                  return InkWell(
                    onTap: () => onSelect(t),
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: selected
                            ? theme.colorScheme.primary.withOpacity(0.08)
                            : theme.cardColor,
                        border: Border.all(
                          color: selected
                              ? theme.colorScheme.primary.withOpacity(0.35)
                              : theme.dividerColor.withOpacity(0.35),
                        ),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                            color: Colors.black.withOpacity(0.06),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          _SemaforoDot(status: t.semaforo),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.nombreCompleto,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${t.gradoAsignado} • ${t.nivelAsignado}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.75),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _KpiChip(label: 'Curricular', value: t.kpiCurricular),
                                    _KpiChip(label: 'Indicadores', value: t.kpiLogro),
                                    _KpiChip(label: 'Asistencia', value: t.kpiAttendance),
                                    _KpiChip(label: 'Promedio', value: t.kpiAverage, emphasize: true),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right, color: theme.iconTheme.color?.withOpacity(0.6)),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// ------------------------------
/// Detalle del docente
/// ------------------------------
class _TeacherDetailPane extends StatelessWidget {
  final ThemeData theme;
  final String schoolId;
  final TeacherSummary? teacher;

  final int anio;
  final DateTime mes;
  final ValueChanged<int> onChangeAnio;
  final ValueChanged<DateTime> onChangeMes;

  final MonitoreoService service;
  final bool readOnlyFilters;

  const _TeacherDetailPane({
    required this.theme,
    required this.schoolId,
    required this.teacher,
    required this.anio,
    required this.mes,
    required this.onChangeAnio,
    required this.onChangeMes,
    required this.service,
    this.readOnlyFilters = false,
  });

  @override
  Widget build(BuildContext context) {
    if (teacher == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text('Selecciona un docente para ver su detalle.',
              textAlign: TextAlign.center),
        ),
      );
    }

    final t = teacher!;

    return Column(
      children: [
        _PaneHeader(
          title: 'Detalle',
          subtitle: 'Periodos + unidades + indicadores + asistencia',
          trailing: _SemaforoPill(status: t.semaforo),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: _FiltersRow(
            anio: anio,
            mes: mes,
            onChangeAnio: onChangeAnio,
            onChangeMes: onChangeMes,
            readOnly: readOnlyFilters,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TeacherHeaderCard(theme: theme, t: t),
                const SizedBox(height: 12),

                FutureBuilder<TeacherCurricularMetrics>(
                  future: service.getTeacherCurricularMetrics(
                    schoolId: schoolId,
                    teacherId: t.teacherId,
                    anio: anio,
                    grado: t.gradoAsignado,
                  ),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _CardError(title: 'Avance Curricular', error: snap.error.toString());
                    }
                    if (!snap.hasData) return const _LoadingCard(title: 'Avance Curricular');
                    return _CurricularCard(theme: theme, metrics: snap.data!);
                  },
                ),

                const SizedBox(height: 12),

                FutureBuilder<AttendanceSummary>(
                  future: service.getAttendanceSummary(
                    schoolId: schoolId,
                    teacherId: t.teacherId,
                    month: mes,
                  ),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _CardError(title: 'Asistencia', error: snap.error.toString());
                    }
                    if (!snap.hasData) return const _LoadingCard(title: 'Asistencia');
                    return _AttendanceCard(theme: theme, summary: snap.data!, month: mes);
                  },
                ),

                const SizedBox(height: 12),

                StreamBuilder<List<FeedbackItem>>(
                  stream: service.streamLatestFeedback(
                    schoolId: schoolId,
                    teacherId: t.teacherId,
                    limit: 5,
                  ),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _CardError(title: 'Observaciones', error: snap.error.toString());
                    }
                    if (!snap.hasData) return const _LoadingCard(title: 'Observaciones');
                    return _FeedbackCard(theme: theme, items: snap.data!);
                  },
                ),

                const SizedBox(height: 12),

                StreamBuilder<List<TaskItem>>(
                  stream: service.streamTasks(
                    schoolId: schoolId,
                    teacherId: t.teacherId,
                    limit: 8,
                  ),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _TasksCard(theme: theme, items: const [], hint: 'Tasks no configurado (opcional).');
                    }
                    if (!snap.hasData) return const _LoadingCard(title: 'Tareas administrativas');
                    return _TasksCard(theme: theme, items: snap.data!);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// ------------------------------
/// Filtros
/// ------------------------------
class _FiltersRow extends StatelessWidget {
  final int anio;
  final DateTime mes;
  final ValueChanged<int> onChangeAnio;
  final ValueChanged<DateTime> onChangeMes;
  final bool readOnly;

  const _FiltersRow({
    required this.anio,
    required this.mes,
    required this.onChangeAnio,
    required this.onChangeMes,
    required this.readOnly,
  });

  @override
  Widget build(BuildContext context) {
    final years = List<int>.generate(6, (i) => DateTime.now().year - i);

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            value: anio,
            decoration: const InputDecoration(
              labelText: 'Año escolar',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: years.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
            onChanged: readOnly ? null : (v) => onChangeAnio(v ?? anio),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: readOnly
                ? null
                : () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: mes,
                      firstDate: DateTime(2020, 1, 1),
                      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
                      helpText: 'Selecciona un día del mes',
                    );
                    if (picked != null) onChangeMes(DateTime(picked.year, picked.month));
                  },
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Mes (asistencia)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              child: Row(
                children: [
                  Expanded(child: Text('${mes.year}-${mes.month.toString().padLeft(2, '0')}')),
                  const Icon(Icons.calendar_month_outlined, size: 18),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// ------------------------------
/// Cards
/// ------------------------------
class _TeacherHeaderCard extends StatelessWidget {
  final ThemeData theme;
  final TeacherSummary t;

  const _TeacherHeaderCard({required this.theme, required this.t});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              child: Text(_initials(t.nombreCompleto),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.nombreCompleto,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('${t.gradoAsignado} • ${t.nivelAsignado}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(0.75),
                      )),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _KpiChip(label: 'Curricular', value: t.kpiCurricular),
                      _KpiChip(label: 'Indicadores', value: t.kpiLogro),
                      _KpiChip(label: 'Asistencia', value: t.kpiAttendance),
                      _KpiChip(label: 'Promedio', value: t.kpiAverage, emphasize: true),
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

  String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.take(2).toString().toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }
}

class _CurricularCard extends StatelessWidget {
  final ThemeData theme;
  final TeacherCurricularMetrics metrics;

  const _CurricularCard({required this.theme, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final items = metrics.byPeriodo.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTitle(
              title: 'Avance Curricular',
              subtitle: metrics.note,
              icon: Icons.bar_chart_outlined,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: _BarChart(
                values: items.map((e) => e.value.unidadesCompletionRate).toList(),
                labels: items.map((e) => e.key).toList(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: items.map((e) {
                final p = e.value;
                return _MiniStat(
                  label: e.key,
                  value:
                      'Unidades ${(p.unidadesCompletionRate * 100).toStringAsFixed(0)}% (${p.unidadesCompletadas}/${p.unidadesPlaneadas})'
                      ' • Indicadores ${(p.indicadoresRate * 100).toStringAsFixed(0)}% (${p.indicadoresLogrados}/${p.indicadoresTotales})',
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            _MiniStat(
              label: 'A tiempo',
              value: metrics.onTimeRate == null
                  ? '—'
                  : '${(metrics.onTimeRate! * 100).toStringAsFixed(0)}%',
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final ThemeData theme;
  final AttendanceSummary summary;
  final DateTime month;

  const _AttendanceCard({
    required this.theme,
    required this.summary,
    required this.month,
  });

  @override
  Widget build(BuildContext context) {
    final total = summary.total;

    final values = [
      _PieSlice(label: 'A tiempo', value: summary.onTime.toDouble()),
      _PieSlice(label: 'Tarde', value: summary.late.toDouble()),
      _PieSlice(label: 'Ausente', value: summary.absent.toDouble()),
      _PieSlice(label: 'Salida temprana', value: summary.earlyExit.toDouble()),
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTitle(
              title: 'Asistencia',
              subtitle: 'Mes ${month.year}-${month.month.toString().padLeft(2, '0')} • Total: $total',
              icon: Icons.pie_chart_outline,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(width: 170, height: 170, child: _PieChart(slices: values)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LegendRow(label: 'A tiempo', value: summary.onTime, total: total),
                      _LegendRow(label: 'Tarde', value: summary.late, total: total),
                      _LegendRow(label: 'Ausente', value: summary.absent, total: total),
                      _LegendRow(label: 'Salida temprana', value: summary.earlyExit, total: total),
                      const SizedBox(height: 10),
                      _MiniStat(
                        label: 'Puntualidad',
                        value: total == 0 ? '—' : '${((summary.onTime / total) * 100).toStringAsFixed(0)}%',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final ThemeData theme;
  final List<FeedbackItem> items;

  const _FeedbackCard({required this.theme, required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle(
              title: 'Observaciones de la administración',
              subtitle: 'Últimas 5',
              icon: Icons.comment_bank_outlined,
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Aún no hay observaciones registradas.'),
              )
            else
              Column(
                children: items.map((f) {
                  final tone = _feedbackTone(f.tipo);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: tone.bg,
                      border: Border.all(color: tone.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(tone.icon, color: tone.fg, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_cap(f.tipo)} • ${_fmtDate(f.fecha)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: tone.fg,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(f.detalles, style: theme.textTheme.bodyMedium),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  _Tone _feedbackTone(String tipo) {
    switch (tipo) {
      case 'positivo':
        return _Tone(
          bg: Colors.green.withOpacity(0.10),
          border: Colors.green.withOpacity(0.30),
          fg: Colors.green.shade800,
          icon: Icons.thumb_up_alt_outlined,
        );
      case 'urgente':
        return _Tone(
          bg: Colors.red.withOpacity(0.10),
          border: Colors.red.withOpacity(0.30),
          fg: Colors.red.shade800,
          icon: Icons.warning_amber_outlined,
        );
      case 'mejora':
      default:
        return _Tone(
          bg: Colors.amber.withOpacity(0.12),
          border: Colors.amber.withOpacity(0.35),
          fg: Colors.brown.shade800,
          icon: Icons.build_circle_outlined,
        );
    }
  }
}

class _TasksCard extends StatelessWidget {
  final ThemeData theme;
  final List<TaskItem> items;
  final String? hint;

  const _TasksCard({required this.theme, required this.items, this.hint});

  @override
  Widget build(BuildContext context) {
    final pending = items.where((t) => t.status != 'done').toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTitle(
              title: 'Tareas administrativas',
              subtitle: hint ?? (pending.isEmpty ? 'Al día' : 'Pendientes'),
              icon: Icons.task_alt_outlined,
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('No hay tareas registradas para este docente.'),
              )
            else
              Column(
                children: items.map((t) {
                  final tone = _taskTone(t);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: tone.bg,
                      border: Border.all(color: tone.border),
                    ),
                    child: Row(
                      children: [
                        Icon(tone.icon, color: tone.fg, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.titulo,
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Estado: ${t.statusLabel}'
                                '${t.dueDate != null ? " • Vence: ${_fmt(t.dueDate!)}" : ""}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.75),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  _Tone _taskTone(TaskItem t) {
    if (t.status == 'done') {
      return _Tone(
        bg: Colors.green.withOpacity(0.10),
        border: Colors.green.withOpacity(0.28),
        fg: Colors.green.shade800,
        icon: Icons.check_circle_outline,
      );
    }
    if (t.status == 'late') {
      return _Tone(
        bg: Colors.red.withOpacity(0.10),
        border: Colors.red.withOpacity(0.28),
        fg: Colors.red.shade800,
        icon: Icons.error_outline,
      );
    }
    return _Tone(
      bg: Colors.amber.withOpacity(0.12),
      border: Colors.amber.withOpacity(0.35),
      fg: Colors.brown.shade800,
      icon: Icons.pending_actions_outlined,
    );
  }
}

/// ------------------------------
/// Headers / Chips / Stats
/// ------------------------------
class _PaneHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget trailing;

  const _PaneHeader({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.70),
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _CardTitle({required this.title, required this.subtitle, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              if (subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.70),
                  ),
                ),
              ]
            ],
          ),
        ),
      ],
    );
  }
}

class _KpiChip extends StatelessWidget {
  final String label;
  final double? value;
  final bool emphasize;

  const _KpiChip({required this.label, required this.value, this.emphasize = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value;
    final text = v == null ? '—' : '${(v * 100).toStringAsFixed(0)}%';

    final bg = emphasize
        ? theme.colorScheme.primary.withOpacity(0.12)
        : theme.colorScheme.surfaceContainerHighest.withOpacity(0.65);

    final border = emphasize
        ? theme.colorScheme.primary.withOpacity(0.35)
        : theme.dividerColor.withOpacity(0.35);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: bg,
        border: Border.all(color: border),
      ),
      child: Text(
        '$label: $text',
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: emphasize ? FontWeight.w900 : FontWeight.w600,
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.55),
        border: Border.all(color: theme.dividerColor.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
          Flexible(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final String label;
  final int value;
  final int total;

  const _LegendRow({required this.label, required this.value, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = total == 0 ? 0 : (value / total) * 100;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text('$label: $value (${pct.toStringAsFixed(0)}%)', style: theme.textTheme.bodySmall),
    );
  }
}

/// ------------------------------
/// Semáforo
/// ------------------------------
enum SemaforoStatus { green, yellow, red }

class _SemaforoDot extends StatelessWidget {
  final SemaforoStatus status;

  const _SemaforoDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = _statusColor(status);
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c,
        boxShadow: [BoxShadow(blurRadius: 10, color: c.withOpacity(0.35))],
      ),
    );
  }

  Color _statusColor(SemaforoStatus s) {
    switch (s) {
      case SemaforoStatus.green:
        return Colors.green.shade600;
      case SemaforoStatus.yellow:
        return Colors.amber.shade700;
      case SemaforoStatus.red:
        return Colors.red.shade600;
    }
  }
}

class _SemaforoPill extends StatelessWidget {
  final SemaforoStatus status;

  const _SemaforoPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final c = _statusColor(status);
    final label = status == SemaforoStatus.green
        ? 'Alto'
        : status == SemaforoStatus.yellow
            ? 'Atención'
            : 'Crítico';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: c.withOpacity(0.12),
        border: Border.all(color: c.withOpacity(0.35)),
      ),
      child: Text(label, style: TextStyle(fontWeight: FontWeight.w900, color: c)),
    );
  }

  Color _statusColor(SemaforoStatus s) {
    switch (s) {
      case SemaforoStatus.green:
        return Colors.green.shade700;
      case SemaforoStatus.yellow:
        return Colors.amber.shade800;
      case SemaforoStatus.red:
        return Colors.red.shade700;
    }
  }
}

/// ------------------------------
/// Charts (sin dependencias)
/// ------------------------------
class _BarChart extends StatelessWidget {
  final List<double> values; // 0..1
  final List<String> labels;

  const _BarChart({required this.values, required this.labels})
      : assert(values.length == labels.length);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BarChartPainter(values: values, labels: labels),
      child: const SizedBox.expand(),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;

  _BarChartPainter({required this.values, required this.labels});

  @override
  void paint(Canvas canvas, Size size) {
    final padL = 12.0;
    final padB = 22.0;
    final padT = 8.0;
    final padR = 12.0;

    final chartW = size.width - padL - padR;
    final chartH = size.height - padT - padB;

    final axisPaint = Paint()
      ..color = Colors.black.withOpacity(0.10)
      ..strokeWidth = 1;

    canvas.drawLine(Offset(padL, padT + chartH), Offset(padL + chartW, padT + chartH), axisPaint);

    final n = values.length;
    final barGap = 10.0;
    final barW = (chartW - (barGap * (n - 1))) / n;
    final barPaint = Paint()..color = Colors.black.withOpacity(0.22);

    for (int i = 0; i < n; i++) {
      final v = values[i].clamp(0.0, 1.0);
      final x = padL + i * (barW + barGap);
      final h = chartH * v;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, padT + (chartH - h), barW, h),
        const Radius.circular(10),
      );
      canvas.drawRRect(rect, barPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontSize: 11,
            color: Colors.black.withOpacity(0.65),
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: barW + 8);

      tp.paint(canvas, Offset(x + (barW - tp.width) / 2, padT + chartH + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.labels != labels;
}

class _PieSlice {
  final String label;
  final double value;

  _PieSlice({required this.label, required this.value});
}

class _PieChart extends StatelessWidget {
  final List<_PieSlice> slices;

  const _PieChart({required this.slices});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PieChartPainter(slices: slices),
      child: const SizedBox.expand(),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<_PieSlice> slices;

  _PieChartPainter({required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (p, e) => p + e.value);
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 6;

    if (total <= 0) {
      final p = Paint()..color = Colors.black.withOpacity(0.10);
      canvas.drawCircle(center, r, p);
      return;
    }

    final colors = [
      Colors.black.withOpacity(0.25),
      Colors.black.withOpacity(0.18),
      Colors.black.withOpacity(0.12),
      Colors.black.withOpacity(0.08),
    ];

    var start = -math.pi / 2;
    for (int i = 0; i < slices.length; i++) {
      final sweep = (slices[i].value / total) * math.pi * 2;
      final p = Paint()..color = colors[i % colors.length];
      canvas.drawArc(Rect.fromCircle(center: center, radius: r), start, sweep, true, p);
      start += sweep;
    }

    final hole = Paint()..color = Colors.white;
    canvas.drawCircle(center, r * 0.58, hole);

    final tp = TextPainter(
      text: TextSpan(
        text: '${total.toInt()}',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: Colors.black.withOpacity(0.75),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) => oldDelegate.slices != slices;
}

/// ------------------------------
/// Estados / errores
/// ------------------------------
class _LoadingCard extends StatelessWidget {
  final String title;
  const _LoadingCard({required this.title});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text(title),
          ],
        ),
      ),
    );
  }
}

class _CardError extends StatelessWidget {
  final String title;
  final String error;
  const _CardError({required this.title, required this.error});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTitle(title: title, subtitle: 'No se pudo cargar', icon: Icons.error_outline),
            const SizedBox(height: 8),
            Text(error, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.title, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            )
          ],
        ),
      ),
    );
  }
}

class _Tone {
  final Color bg;
  final Color border;
  final Color fg;
  final IconData icon;

  _Tone({required this.bg, required this.border, required this.fg, required this.icon});
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// ------------------------------
/// Modelos (UI)
/// ------------------------------
class TeacherSummary {
  final String teacherId;
  final String nombreCompleto;
  final String nivelAsignado;
  final String gradoAsignado;

  // KPIs agregados (ideal: guardarlos en teachers para lista rápida)
  final double? kpiCurricular;
  final double? kpiLogro;
  final double? kpiAttendance;

  TeacherSummary({
    required this.teacherId,
    required this.nombreCompleto,
    required this.nivelAsignado,
    required this.gradoAsignado,
    required this.kpiCurricular,
    required this.kpiLogro,
    required this.kpiAttendance,
  });

  double? get kpiAverage {
    final vals = <double>[];
    if (kpiCurricular != null) vals.add(kpiCurricular!.clamp(0, 1));
    if (kpiLogro != null) vals.add(kpiLogro!.clamp(0, 1));
    if (kpiAttendance != null) vals.add(kpiAttendance!.clamp(0, 1));
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  SemaforoStatus get semaforo {
    final avg = kpiAverage;
    if (avg == null) return SemaforoStatus.yellow;
    if (avg >= 0.85) return SemaforoStatus.green;
    if (avg >= 0.70) return SemaforoStatus.yellow;
    return SemaforoStatus.red;
  }
}

class AttendanceSummary {
  final int onTime;
  final int late;
  final int absent;
  final int earlyExit;

  AttendanceSummary({
    required this.onTime,
    required this.late,
    required this.absent,
    required this.earlyExit,
  });

  int get total => onTime + late + absent + earlyExit;
}

class FeedbackItem {
  final String tipo;
  final String detalles;
  final DateTime fecha;
  final String adminId;

  FeedbackItem({
    required this.tipo,
    required this.detalles,
    required this.fecha,
    required this.adminId,
  });
}

class TaskItem {
  final String titulo;
  final String status; // pending|done|late
  final DateTime? dueDate;

  TaskItem({
    required this.titulo,
    required this.status,
    required this.dueDate,
  });

  String get statusLabel {
    switch (status) {
      case 'done':
        return 'Completada';
      case 'late':
        return 'Atrasada';
      case 'pending':
      default:
        return 'Pendiente';
    }
  }
}

class PeriodoAcademico {
  final String id; // P1..P4
  final String nombre;
  final DateTime? inicio;
  final DateTime? fin;
  final int orden;

  PeriodoAcademico({
    required this.id,
    required this.nombre,
    required this.inicio,
    required this.fin,
    required this.orden,
  });
}

/// Métricas curriculares calculadas uniendo:
/// - periodos oficiales
/// - planificación anual (unidades + indicadores esperados)
/// - curricular_progress del docente (status + indicadores logrados + fechaFinReal)
class TeacherCurricularMetrics {
  final Map<String, PeriodoMetrics> byPeriodo;
  final double? onTimeRate;
  final String note;

  TeacherCurricularMetrics({
    required this.byPeriodo,
    required this.onTimeRate,
    required this.note,
  });
}


class PeriodoMetrics {
  final int unidadesPlaneadas;
  final int unidadesCompletadas;

  final int indicadoresTotales;
  final int indicadoresLogrados;

  PeriodoMetrics({
    required this.unidadesPlaneadas,
    required this.unidadesCompletadas,
    required this.indicadoresTotales,
    required this.indicadoresLogrados,
  });

  double get unidadesCompletionRate =>
      unidadesPlaneadas == 0 ? 0 : (unidadesCompletadas / unidadesPlaneadas);

  double get indicadoresRate =>
      indicadoresTotales == 0 ? 0 : (indicadoresLogrados / indicadoresTotales);
}
class PeriodoMetricsBuilder {
  int unidadesPlaneadas = 0;
  int unidadesCompletadas = 0;

  int indicadoresTotales = 0;
  int indicadoresLogrados = 0;

  // unidadId -> indicadores planeados
  final Map<String, List<String>> planeadosPorUnidad = {};

  PeriodoMetrics build() {
    return PeriodoMetrics(
      unidadesPlaneadas: unidadesPlaneadas,
      unidadesCompletadas: unidadesCompletadas,
      indicadoresTotales: indicadoresTotales,
      indicadoresLogrados: indicadoresLogrados,
    );
  }
}


/// ------------------------------
/// Servicio Firestore
/// ------------------------------
class MonitoreoService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  MonitoreoService({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  DocumentReference<Map<String, dynamic>> _schoolDoc(String schoolId) =>
      _db.collection('schools').doc(schoolId);

  CollectionReference<Map<String, dynamic>> _teachersCol(String schoolId) =>
      _schoolDoc(schoolId).collection('teachers');

  /// 1) Lista rápida de docentes (ideal: KPIs ya calculados en teachers).
  Stream<List<TeacherSummary>> streamTeachers(String schoolId) {
    return _teachersCol(schoolId)
        .orderBy('lastActivity', descending: true)
        .snapshots()
        .map((qs) => qs.docs.map(_teacherFromDoc).toList());
  }

  TeacherSummary _teacherFromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? {};
    return TeacherSummary(
      teacherId: d.id,
      nombreCompleto: (data['nombreCompleto'] ?? 'Docente').toString(),
      nivelAsignado: (data['nivelAsignado'] ?? '—').toString(),
      gradoAsignado: (data['gradoAsignado'] ?? '—').toString(),
      kpiCurricular: _asDoubleOrNull(data['kpi_curricular_score']),
      kpiLogro: _asDoubleOrNull(data['kpi_logro_score']),
      kpiAttendance: _asDoubleOrNull(data['kpi_attendance_rate']),
    );
  }

  /// 2) Periodos académicos oficiales
  Future<List<PeriodoAcademico>> getPeriodos(String schoolId) async {
    final col = _schoolDoc(schoolId)
        .collection('config_academica')
        .doc('periodos')
        .collection('lista');

    final snap = await col.get();

    if (snap.docs.isEmpty) {
      // fallback
      return [
        PeriodoAcademico(id: 'P1', nombre: 'P1', inicio: null, fin: null, orden: 1),
        PeriodoAcademico(id: 'P2', nombre: 'P2', inicio: null, fin: null, orden: 2),
        PeriodoAcademico(id: 'P3', nombre: 'P3', inicio: null, fin: null, orden: 3),
        PeriodoAcademico(id: 'P4', nombre: 'P4', inicio: null, fin: null, orden: 4),
      ];
    }

    final list = snap.docs.map((d) {
      final data = d.data();
      final id = (data['id'] ?? d.id).toString().toUpperCase().trim();
      final nombre = (data['nombre'] ?? id).toString();
      final orden = (data['orden'] is num) ? (data['orden'] as num).toInt() : _guessOrdenFromId(id);
      final inicio = _asDateTimeOrNull(data['inicio']) ?? _asDateTimeOrNull(data['fechaInicio']);
      final fin = _asDateTimeOrNull(data['fin']) ?? _asDateTimeOrNull(data['fechaFin']);
      return PeriodoAcademico(id: id, nombre: nombre, inicio: inicio, fin: fin, orden: orden);
    }).toList();

    list.sort((a, b) => a.orden.compareTo(b.orden));
    return list;
  }

  int _guessOrdenFromId(String id) {
    if (id == 'P1') return 1;
    if (id == 'P2') return 2;
    if (id == 'P3') return 3;
    if (id == 'P4') return 4;
    return 99;
  }

  /// 3) Trae planificación anual del año/grado
  Future<Map<String, dynamic>?> getPlanificacionAnual({
    required String schoolId,
    required int anio,
    required String grado,
  }) async {
    // Intento A: query por campos (recomendado)
    final col = _schoolDoc(schoolId).collection('planificaciones_anuales');

    try {
      final qs = await col
          .where('anio', isEqualTo: anio)
          .where('grado', isEqualTo: grado)
          .limit(1)
          .get();
      if (qs.docs.isNotEmpty) return qs.docs.first.data();
    } catch (_) {
      // Si no hay índices o campos, no rompemos.
    }

    // Intento B: docId convención "anio_grado" o "anio-grado"
    final candidates = [
      '$anio-$grado',
      '${anio}_$grado',
      '$grado-$anio',
      '${grado}_$anio',
    ];
    for (final id in candidates) {
      final d = await col.doc(id).get();
      if (d.exists) return d.data();
    }

    return null;
  }

  /// 4) MÉTRICAS CURRICULARES:
  /// - planeado: unidades + indicadores desde planificación anual
  /// - realizado: curricular_progress del docente
  /// - a tiempo: usando fechaFinReal <= fechaFin del periodo (si existe)
  Future<TeacherCurricularMetrics> getTeacherCurricularMetrics({
    required String schoolId,
    required String teacherId,
    required int anio,
    required String grado,
  }) async {
    final periodos = await getPeriodos(schoolId);
    final plan = await getPlanificacionAnual(schoolId: schoolId, anio: anio, grado: grado);

    if (plan == null) {
      // fallback: aún puede mostrar algo con curricular_progress solo, pero sin “planeado”
      return TeacherCurricularMetrics(
        byPeriodo: {for (final p in periodos) p.id: PeriodoMetrics(unidadesPlaneadas: 0, unidadesCompletadas: 0, indicadoresTotales: 0, indicadoresLogrados: 0)},
        onTimeRate: null,
        note: 'No se encontró planificación anual para $anio / $grado.',
      );
    }

    final unidades = _extractUnidadesFromPlan(plan); // lista de maps
    final Set<String> unidadIdsPlaneadas = {};
    final Map<String, PeriodoMetricsBuilder> builders = {
      for (final p in periodos) p.id: PeriodoMetricsBuilder(),
    };

    // 4.1 Planeado (unidades + indicadores esperados) por periodo
    for (int i = 0; i < unidades.length; i++) {
      final u = unidades[i];
      final unidadId = _unidadId(u, i);
      unidadIdsPlaneadas.add(unidadId);

      final periodoId = _periodoIdFromUnidad(u);
      final key = builders.containsKey(periodoId) ? periodoId : (periodos.isNotEmpty ? periodos.first.id : 'P1');

      builders[key]!.unidadesPlaneadas += 1;

      final plannedIndicadores = _extractIndicadoresIds(u);
      builders[key]!.indicadoresTotales += plannedIndicadores.length;

      // guardamos el set planeado por unidad para luego cruzar con logrados
      builders[key]!.planeadosPorUnidad[unidadId] = plannedIndicadores;
    }

    // 4.2 Real (curricular_progress del docente)
    final progCol = _teachersCol(schoolId).doc(teacherId).collection('curricular_progress');

    // intentamos filtrar por anio si existe, si no, leemos todo
    Query<Map<String, dynamic>> q = progCol;
    try {
      q = progCol.where('anio', isEqualTo: anio);
      await q.limit(1).get();
    } catch (_) {
      q = progCol;
    }

    final progSnap = await q.get();

    int onTimeCount = 0;
    int onTimeBase = 0;

    final periodoById = {for (final p in periodos) p.id: p};

    for (final d in progSnap.docs) {
      final data = d.data();
      final unidadId = d.id;

      // Solo consideramos unidades que están dentro de la planificación de ese año/grado
      if (unidadIdsPlaneadas.isNotEmpty && !unidadIdsPlaneadas.contains(unidadId)) continue;

      final status = (data['status'] ?? 'planned').toString();
      final isCompleted = status == 'completed';

      final periodoId = _periodoIdFromProgress(data) ?? _periodoIdGuessByUnidad(builders, unidadId) ?? (periodos.isNotEmpty ? periodos.first.id : 'P1');
      final key = builders.containsKey(periodoId) ? periodoId : (periodos.isNotEmpty ? periodos.first.id : 'P1');

      if (isCompleted) builders[key]!.unidadesCompletadas += 1;

      // Indicadores logrados: intersectamos con los planeados de esa unidad (para evitar inflar con ids raros)
      final logrados = _asStringList(data['indicadoresLogrados']);
      final planeadosUnidad = builders[key]!.planeadosPorUnidad[unidadId] ?? const <String>[];

      if (planeadosUnidad.isNotEmpty && logrados.isNotEmpty) {
        final planeadosSet = planeadosUnidad.toSet();
        final ok = logrados.where((id) => planeadosSet.contains(id)).toSet();
        builders[key]!.indicadoresLogrados += ok.length;
      }

      // A tiempo: fechaFinReal <= fin del periodo
      final finReal = _asDateTimeTime(data['fechaFinReal']);
      final finPeriodo = periodoById[key]?.fin;

      if (isCompleted && finReal != null && finPeriodo != null) {
        onTimeBase++;
        if (!finReal.isAfter(finPeriodo)) onTimeCount++;
      }
    }

    final byPeriodo = <String, PeriodoMetrics>{};
    for (final p in periodos) {
      final b = builders[p.id] ?? PeriodoMetricsBuilder();
      byPeriodo[p.id] = b.build();
    }

    final onTimeRate = onTimeBase == 0 ? null : (onTimeCount / onTimeBase);

    final note = 'Basado en periodos oficiales + planificación anual ($anio/$grado) + curricular_progress.'
        '${onTimeRate == null ? " (A tiempo requiere fechas fin en periodos + fechaFinReal)" : ""}';

    return TeacherCurricularMetrics(byPeriodo: byPeriodo, onTimeRate: onTimeRate, note: note);
  }

  String? _periodoIdGuessByUnidad(Map<String, PeriodoMetricsBuilder> builders, String unidadId) {
    for (final e in builders.entries) {
      if (e.value.planeadosPorUnidad.containsKey(unidadId)) return e.key;
    }
    return null;
  }

  /// 5) Asistencia (igual que antes)
  Future<AttendanceSummary> getAttendanceSummary({
    required String schoolId,
    required String teacherId,
    required DateTime month,
  }) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);

    final col = _teachersCol(schoolId).doc(teacherId).collection('attendance');

    final snap = await col
        .where('fecha', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('fecha', isLessThan: Timestamp.fromDate(end))
        .get();

    int onTime = 0, late = 0, absent = 0, earlyExit = 0;

    for (final d in snap.docs) {
      final data = d.data();
      final status = (data['status'] ?? '').toString();
      switch (status) {
        case 'on_time':
          onTime++;
          break;
        case 'late':
          late++;
          break;
        case 'absent':
          absent++;
          break;
        case 'early_exit':
          earlyExit++;
          break;
      }
    }

    return AttendanceSummary(onTime: onTime, late: late, absent: absent, earlyExit: earlyExit);
  }

  /// 6) Observaciones admin
  Stream<List<FeedbackItem>> streamLatestFeedback({
    required String schoolId,
    required String teacherId,
    int limit = 5,
  }) {
    final col = _teachersCol(schoolId).doc(teacherId).collection('admin_feedback');

    return col
        .orderBy('fecha', descending: true)
        .limit(limit)
        .snapshots()
        .map((qs) => qs.docs.map(_feedbackFromDoc).toList());
  }

  FeedbackItem _feedbackFromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? {};
    return FeedbackItem(
      tipo: (data['tipo'] ?? 'mejora').toString(),
      detalles: (data['detalles'] ?? '').toString(),
      fecha: _asDateTimeOrNull(data['fecha']) ?? DateTime.now(),
      adminId: (data['adminId'] ?? '').toString(),
    );
  }

  Future<void> addAdminFeedback({
    required String schoolId,
    required String teacherId,
    required String tipo,
    required String detalles,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Debes estar autenticado.');

    final col = _teachersCol(schoolId).doc(teacherId).collection('admin_feedback');

    await col.add({
      'adminId': uid,
      'fecha': FieldValue.serverTimestamp(),
      'tipo': tipo,
      'detalles': detalles,
    });
  }

  /// 7) Tasks (opcional)
  Stream<List<TaskItem>> streamTasks({
    required String schoolId,
    required String teacherId,
    int limit = 8,
  }) {
    final col = _teachersCol(schoolId).doc(teacherId).collection('tasks');

    return col
        .orderBy('dueDate', descending: false)
        .limit(limit)
        .snapshots()
        .map((qs) => qs.docs.map(_taskFromDoc).toList());
  }

  TaskItem _taskFromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? {};
    return TaskItem(
      titulo: (data['titulo'] ?? 'Tarea').toString(),
      status: (data['status'] ?? 'pending').toString(),
      dueDate: _asDateTimeOrNull(data['dueDate']),
    );
  }

  /// ---------------- Helpers: Planificación ----------------
  List<Map<String, dynamic>> _extractUnidadesFromPlan(Map<String, dynamic> plan) {
    final raw = plan['unidades'] ?? plan['unidadesDidacticas'] ?? plan['listaUnidades'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  String _unidadId(Map<String, dynamic> unidad, int index) {
    final cands = [
      unidad['unidadId'],
      unidad['id'],
      unidad['uid'],
      unidad['codigo'],
    ].where((e) => e != null && e.toString().trim().isNotEmpty).toList();

    if (cands.isNotEmpty) return cands.first.toString().trim();
    return 'unidad_$index';
  }

  String _periodoIdFromUnidad(Map<String, dynamic> unidad) {
    final raw = (unidad['periodoId'] ?? unidad['periodo'] ?? unidad['periodoAcademico'] ?? 'P1').toString().trim().toUpperCase();
    if (raw == 'P1' || raw == 'P2' || raw == 'P3' || raw == 'P4') return raw;
    return raw.isEmpty ? 'P1' : raw;
  }

  String? _periodoIdFromProgress(Map<String, dynamic> prog) {
    final raw = (prog['periodoId'] ?? prog['periodo'] ?? prog['periodoAcademico'])?.toString().trim().toUpperCase();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  List<String> _extractIndicadoresIds(Map<String, dynamic> unidad) {
    final raw = unidad['indicadores'] ?? unidad['indicadoresLogro'] ?? unidad['indicadoresDeLogro'];
    if (raw is List) {
      // puede ser lista de strings o lista de objetos
      final out = <String>[];
      for (final x in raw) {
        if (x == null) continue;
        if (x is String) {
          final s = x.trim();
          if (s.isNotEmpty) out.add(s);
        } else if (x is Map) {
          final m = Map<String, dynamic>.from(x as Map);
          final id = (m['id'] ?? m['uid'] ?? m['codigo'] ?? m['indicadorId'])?.toString().trim();
          if (id != null && id.isNotEmpty) out.add(id);
        } else {
          final s = x.toString().trim();
          if (s.isNotEmpty) out.add(s);
        }
      }
      return out.toSet().toList();
    }
    return const [];
  }

// Helpers genéricos (DEJA SOLO ESTE BLOQUE)
double? _asDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim());
}

DateTime? _asDateTimeOrNull(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
}

DateTime? _asDateTimeTime(dynamic v) => _asDateTimeOrNull(v);

List<String> _asStringList(dynamic v) {
  if (v == null) return const [];
  if (v is List) {
    return v
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
  }
  final s = v.toString().trim();
  return s.isEmpty ? const [] : [s];
}

} // <- cierra MonitoreoService
