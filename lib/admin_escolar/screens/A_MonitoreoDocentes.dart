// lib/admin_escolar/screens/A_MonitoreoDocentes.dart
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/admin_escolar/widgets/admin_back_button.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

/// ------------------------------------------------------------
/// A_MonitoreoDocentes.dart (Admin Escolar)
/// ------------------------------------------------------------
/// Estructura usada:
/// schools/{schoolId}
///   config_academica/periodos/lista/{periodoId}  (P1..P4)
///   planificaciones_anuales/{planId}             (por ano + grado)
///   teachers/{teacherId}
///     curricular_progress/{unidadId}
///     attendance/{dateId}
///     admin_feedback/{feedbackId}
///     tasks/{taskId} (opcional)
///
/// Nota importante:
/// Para que el mapeo sea perfecto, cada unidad en planificacion anual deberia tener:
///   - unidadId (o id) estable
///   - periodoId: "P1".."P4"
///   - indicadores (lista de ids o lista de objetos con id)
/// ------------------------------------------------------------

class AMonitoreoDocentes extends StatefulWidget {
  final Escuela escuela;
  final String? schoolIdOverride;
  final VoidCallback? onBack;

  const AMonitoreoDocentes({
    Key? key,
    required this.escuela,
    this.schoolIdOverride,
    this.onBack,
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
        throw Exception('schoolId vacio (override y normalizacion fallaron).');
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
        backgroundColor: Colors.indigo.shade900,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: AdminBackButton(onBack: widget.onBack),
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
              label: const Text('Agregar observacion'),
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
        title: Text('Observacion para $teacherName'),
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
                hintText: 'Describe la observacion...',
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
                  const SnackBar(content: Text('Escribe un poco mas de detalle.')),
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
            const SnackBar(content: Text('Observacion guardada.')),
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
          subtitle: 'Vista general de carga, planes, chats y seguimiento',
          trailing: Icon(Icons.manage_accounts_outlined),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Column(
            children: [
              TextField(
                controller: searchCtrl,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Buscar por nombre, grado, asignatura o nivel...',
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
                  DropdownMenuItem(value: 'Activos', child: Text('Activos')),
                  DropdownMenuItem(value: 'Pendientes', child: Text('Pendientes')),
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
                    t.nivelAsignado,
                    t.gradesLabel,
                    t.subjectsLabel,
                  ].join(' ').toLowerCase();
                  return hay.contains(q);
                }).toList();
              }

              if (statusFilter != 'Todos') {
                list = list.where((t) {
                  if (statusFilter == 'Activos') return t.enabled;
                  if (statusFilter == 'Pendientes') return !t.enabled;
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _TeacherStateDot(enabled: t.enabled),
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
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      t.nivelAsignado,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.textTheme.bodySmall?.color?.withOpacity(0.72),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              _TeacherStateChip(enabled: t.enabled),
                              const SizedBox(width: 6),
                              Icon(Icons.chevron_right,
                                  color: theme.iconTheme.color?.withOpacity(0.6)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _SoftInfoChip(
                                icon: Icons.groups_2_outlined,
                                label: t.effectiveGradeNames.length == 1
                                    ? t.effectiveGradeNames.first
                                    : '${t.effectiveGradeNames.length} grados',
                              ),
                              _SoftInfoChip(
                                icon: Icons.menu_book_outlined,
                                label: t.effectiveSubjectNames.isEmpty
                                    ? 'Sin asignaturas'
                                    : t.effectiveSubjectNames.length == 1
                                        ? t.effectiveSubjectNames.first
                                        : '${t.effectiveSubjectNames.length} asignaturas',
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _KpiChip(label: 'Curricular', value: t.kpiCurricular),
                              _KpiChip(label: 'Logro', value: t.kpiLogro),
                              _KpiChip(label: 'Asistencia', value: t.kpiAttendance),
                              _KpiChip(
                                  label: 'Promedio',
                                  value: t.kpiAverage,
                                  emphasize: true),
                            ],
                          ),
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
          title: 'Monitoreo completo',
          subtitle: 'Seguimiento de grados, planes, chats y desempeño del docente',
          trailing: _TeacherStateChip(enabled: t.enabled),
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
          child: FutureBuilder<TeacherMonitoringSnapshot>(
            future: service.getTeacherMonitoringSnapshot(
              schoolId: schoolId,
              teacher: t,
              anio: anio,
            ),
            builder: (context, monitorSnap) {
              if (monitorSnap.hasError) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                  child: _CardError(
                    title: 'Monitoreo',
                    error: monitorSnap.error.toString(),
                  ),
                );
              }
              if (!monitorSnap.hasData) {
                return const SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 18),
                  child: _LoadingCard(title: 'Monitoreo del docente'),
                );
              }

              final monitoring = monitorSnap.data!;

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TeacherOverviewCard(theme: theme, teacher: t, data: monitoring),
                    const SizedBox(height: 12),
                    FutureBuilder<TeacherCurricularMetrics>(
                      future: service.getTeacherCurricularMetrics(
                        schoolId: schoolId,
                        teacher: t,
                        anio: anio,
                      ),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return _CardError(
                              title: 'Avance Curricular', error: snap.error.toString());
                        }
                        if (!snap.hasData) {
                          return const _LoadingCard(title: 'Avance Curricular');
                        }
                        return _CurricularCard(theme: theme, metrics: snap.data!);
                      },
                    ),
                    const SizedBox(height: 12),
                    _PlansMonitoringCard(theme: theme, plans: monitoring.plans),
                    const SizedBox(height: 12),
                    _ChatsMonitoringCard(
                      theme: theme,
                      chats: monitoring.chats,
                      onOpen: (chat) => _openReadOnlyChat(
                        context,
                        theme,
                        service,
                        schoolId,
                        chat,
                      ),
                    ),
                    const SizedBox(height: 12),
                     FutureBuilder<AttendanceSummary>(
                       future: service.getAttendanceSummary(
                         schoolId: schoolId,
                         teacher: t,
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
                     _AttendanceEditAccessCard(
                       theme: theme,
                       schoolId: schoolId,
                       teacher: t,
                       service: service,
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
                          return _TasksCard(
                            theme: theme,
                            items: const [],
                            hint: 'Tasks no configurado (opcional).',
                          );
                        }
                        if (!snap.hasData) {
                          return const _LoadingCard(title: 'Tareas administrativas');
                        }
                        return _TasksCard(theme: theme, items: snap.data!);
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openReadOnlyChat(
    BuildContext context,
    ThemeData theme,
    MonitoreoService service,
    String schoolId,
    ChatPreviewItem chat,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 760,
          height: 620,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chat.subjectLabel.trim().isEmpty
                                ? 'Chat del grado ${chat.gradeLabel}'
                                : '${chat.gradeLabel} • ${chat.subjectLabel}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text('Vista de solo lectura para administración escolar'),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: service.streamGradeChatMessages(
                    schoolId: schoolId,
                    threadId: chat.threadId,
                  ),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'No se pudo cargar el chat: ${snap.error}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final items = snap.data!;
                    if (items.isEmpty) {
                      return const Center(child: Text('No hay mensajes registrados.'));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final msg = items[index];
                        final sender = (msg['senderName'] ??
                                msg['name'] ??
                                msg['senderUid'] ??
                                'Usuario')
                            .toString();
                        final role = (msg['senderRole'] ??
                                msg['role'] ??
                                msg['rol'] ??
                                '')
                            .toString();
                        final text = (msg['text'] ?? msg['message'] ?? msg['mensaje'] ?? '')
                            .toString();
                        final dt = _readDateTimeOrNull(
                          msg['createdAt'] ?? msg['timestamp'] ?? msg['sentAt'],
                        );
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
                            border: Border.all(
                              color: theme.dividerColor.withOpacity(0.25),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      sender,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  if (role.trim().isNotEmpty)
                                    _SoftInfoChip(
                                      icon: Icons.badge_outlined,
                                      label: role,
                                    ),
                                ],
                              ),
                              if (text.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(text),
                              ],
                              if (dt != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _fmtDateTime(dt),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.65),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
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
              labelText: 'Ano escolar',
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
                      helpText: 'Selecciona un dia del mes',
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
    final items = metrics.byPeriodo.entries.toList();

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
                  ? '-'
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
      _PieSlice(label: 'Presentes', value: summary.present.toDouble()),
      _PieSlice(label: 'Ausente', value: summary.absent.toDouble()),
      _PieSlice(label: 'Excusas', value: summary.excused.toDouble()),
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
              subtitle: 'Mes ${month.year}-${month.month.toString().padLeft(2, '0')} • Registros: $total',
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
                      _LegendRow(label: 'Presentes', value: summary.present, total: total),
                      _LegendRow(label: 'Ausente', value: summary.absent, total: total),
                      _LegendRow(label: 'Excusas', value: summary.excused, total: total),
                      const SizedBox(height: 10),
                      _MiniStat(
                        label: 'Asistencia efectiva',
                        value: total == 0 ? '-' : '${((summary.present / total) * 100).toStringAsFixed(0)}%',
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

class _AttendanceEditAccessCard extends StatefulWidget {
  final ThemeData theme;
  final String schoolId;
  final TeacherSummary teacher;
  final MonitoreoService service;

  const _AttendanceEditAccessCard({
    required this.theme,
    required this.schoolId,
    required this.teacher,
    required this.service,
  });

  @override
  State<_AttendanceEditAccessCard> createState() => _AttendanceEditAccessCardState();
}

class _AttendanceEditAccessCardState extends State<_AttendanceEditAccessCard> {
  bool _saving = false;

  Future<void> _saveDates(Set<String> allowedDateKeys) async {
    setState(() => _saving = true);
    try {
      await widget.service.setAttendanceAllowedPastDates(
        schoolId: widget.schoolId,
        teacher: widget.teacher,
        allowedDateKeys: allowedDateKeys,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permisos de asistencia actualizados.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar el permiso: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndAddDate(AttendanceEditAccess access) async {
    final today = DateTime.now();
    final lastEligible = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 2));
    final firstEligible = DateTime(2020, 1, 1);

    if (lastEligible.isBefore(firstEligible)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aún no hay fechas pasadas para habilitar.')),
      );
      return;
    }

    final initialDate = access.allowedPastDates.isNotEmpty
        ? access.allowedPastDates.last
        : lastEligible;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(lastEligible) ? lastEligible : initialDate,
      firstDate: firstEligible,
      lastDate: lastEligible,
      helpText: 'Selecciona la fecha pasada a habilitar',
    );

    if (picked == null) return;

    final next = access.allowedPastDateKeys.toSet()
      ..add(_attendanceDateKey(picked));
    await _saveDates(next);
  }

  Future<void> _removeDate(AttendanceEditAccess access, String dateKey) async {
    final next = access.allowedPastDateKeys.toSet()..remove(dateKey);
    await _saveDates(next);
  }

  Future<void> _clearAll(AttendanceEditAccess access) async {
    if (access.allowedPastDateKeys.isEmpty) return;
    await _saveDates(<String>{});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AttendanceEditAccess>(
      stream: widget.service.streamAttendanceEditAccess(
        schoolId: widget.schoolId,
        teacher: widget.teacher,
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return _CardError(
            title: 'Permisos de asistencia',
            error: snap.error.toString(),
          );
        }
        if (!snap.hasData) {
          return const _LoadingCard(title: 'Permisos de asistencia');
        }

        final access = snap.data!;
        final hasDates = access.allowedPastDates.isNotEmpty;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardTitle(
                  title: 'Permiso para asistencia pasada',
                  subtitle: 'El docente ya puede usar hoy y ayer. Aquí habilitas solo fechas más antiguas y específicas.',
                  icon: Icons.edit_calendar_outlined,
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: widget.theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: widget.theme.dividerColor.withOpacity(0.22)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasDates
                            ? 'Fechas autorizadas para ${widget.teacher.nombreCompleto}'
                            : 'No hay fechas pasadas autorizadas.',
                        style: widget.theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (!hasDates)
                        Text(
                          'Si el docente necesita completar asistencia más allá de la ventana normal, agrega aquí las fechas exactas.',
                          style: widget.theme.textTheme.bodyMedium,
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: access.allowedPastDates.map((date) {
                            final dateKey = _attendanceDateKey(date);
                            return Chip(
                              label: Text(_fmtSimpleDate(date)),
                              deleteIcon: const Icon(Icons.close, size: 18),
                              onDeleted: _saving ? null : () => _removeDate(access, dateKey),
                            );
                          }).toList(),
                        ),
                      if (access.updatedAt != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Última actualización: ${_fmtDateTime(access.updatedAt!)}',
                          style: widget.theme.textTheme.bodySmall?.copyWith(
                            color: widget.theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _saving ? null : () => _pickAndAddDate(access),
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_circle_outline),
                      label: const Text('Agregar fecha'),
                    ),
                    OutlinedButton.icon(
                      onPressed: (_saving || !hasDates) ? null : () => _clearAll(access),
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: const Text('Limpiar permisos'),
                    ),
                  ],
                ),
                if (access.hasLegacyWideOpenAccess) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.amber.withOpacity(0.28)),
                    ),
                    child: Text(
                      access.legacyWideOpenUntil == null
                          ? 'Este docente tiene un permiso retroactivo amplio heredado. Al guardar fechas específicas, ese permiso se reemplaza.'
                          : 'Este docente tiene un permiso retroactivo heredado hasta ${_fmtDateTime(access.legacyWideOpenUntil!)}. Al guardar fechas específicas, ese permiso se reemplaza.',
                      style: widget.theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
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
              title: 'Observaciones de la administracion',
              subtitle: 'Ultimas 5',
              icon: Icons.comment_bank_outlined,
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Aun no hay observaciones registradas.'),
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
              subtitle: hint ?? (pending.isEmpty ? 'Al dia' : 'Pendientes'),
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

class _TeacherOverviewCard extends StatelessWidget {
  final ThemeData theme;
  final TeacherSummary teacher;
  final TeacherMonitoringSnapshot data;

  const _TeacherOverviewCard({
    required this.theme,
    required this.teacher,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final planRate = data.totalPlans == 0 ? null : data.completedPlans / data.totalPlans;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                  child: Icon(Icons.school_outlined,
                      color: theme.colorScheme.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        teacher.nombreCompleto,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        teacher.nivelAsignado,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(0.72),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _TeacherStateChip(enabled: teacher.enabled),
                          _SoftInfoChip(
                            icon: Icons.groups_2_outlined,
                            label: teacher.gradesLabel,
                          ),
                          _SoftInfoChip(
                            icon: Icons.menu_book_outlined,
                            label: teacher.subjectsLabel,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, c) {
                final compact = c.maxWidth < 760;
                final tiles = [
                  _MiniStat(label: 'Alumnos', value: '${data.totalStudents}'),
                  _MiniStat(label: 'Grados', value: '${data.totalGrades}'),
                  _MiniStat(label: 'Asignaturas', value: '${data.totalSubjects}'),
                  _MiniStat(
                    label: 'Planes',
                    value: data.totalPlans == 0
                        ? '0'
                        : '${data.completedPlans}/${data.totalPlans}',
                    helper: planRate == null
                        ? 'Sin planes'
                        : '${(planRate * 100).toStringAsFixed(0)}% completado',
                  ),
                ];
                if (compact) {
                  return Column(
                    children: tiles
                        .map((t) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: t,
                            ))
                        .toList(),
                  );
                }
                return Row(
                  children: [
                    for (int i = 0; i < tiles.length; i++) ...[
                      Expanded(child: tiles[i]),
                      if (i != tiles.length - 1) const SizedBox(width: 10),
                    ]
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PlansMonitoringCard extends StatelessWidget {
  final ThemeData theme;
  final List<PlanMonitoringItem> plans;

  const _PlansMonitoringCard({
    required this.theme,
    required this.plans,
  });

  @override
  Widget build(BuildContext context) {
    final completed = plans.where((p) => p.completed).length;
    final pending = math.max(0, plans.length - completed);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTitle(
              title: 'Planificaciones anuales',
              subtitle: plans.isEmpty
                  ? 'Sin planes registrados'
                  : '$completed completadas • $pending pendientes',
              icon: Icons.edit_note_outlined,
            ),
            const SizedBox(height: 12),
            if (plans.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Este docente aún no tiene planificaciones anuales registradas.'),
              )
            else
              Column(
                children: plans.map((plan) {
                  final tone = plan.completed
                      ? _Tone(
                          bg: Colors.green.withOpacity(0.08),
                          border: Colors.green.withOpacity(0.22),
                          fg: Colors.green.shade800,
                          icon: Icons.check_circle_outline,
                        )
                      : _Tone(
                          bg: Colors.amber.withOpacity(0.10),
                          border: Colors.amber.withOpacity(0.28),
                          fg: Colors.brown.shade800,
                          icon: Icons.schedule_outlined,
                        );
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
                                plan.subjectLabel,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${plan.gradeLabel} • ${plan.schoolYear}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.textTheme.bodyMedium?.color?.withOpacity(0.76),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _SoftInfoChip(
                                    icon: Icons.layers_outlined,
                                    label: '${plan.unitsCount} unidades',
                                  ),
                                  _SoftInfoChip(
                                    icon: Icons.task_alt_outlined,
                                    label: plan.completed ? 'Completada' : 'En progreso',
                                  ),
                                  if (plan.updatedAt != null)
                                    _SoftInfoChip(
                                      icon: Icons.update_outlined,
                                      label: _fmtDateTime(plan.updatedAt!),
                                    ),
                                ],
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
}

class _ChatsMonitoringCard extends StatelessWidget {
  final ThemeData theme;
  final List<ChatPreviewItem> chats;
  final ValueChanged<ChatPreviewItem> onOpen;

  const _ChatsMonitoringCard({
    required this.theme,
    required this.chats,
    required this.onOpen,
  });

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
                title: 'Chats por grado y asignatura',
                subtitle: 'Vista de solo lectura de conversaciones asociadas',
                icon: Icons.forum_outlined,
              ),
            const SizedBox(height: 12),
            if (chats.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('No hay chats por grado y asignatura asociados a este docente.'),
              )
            else
              Column(
                children: chats.map((chat) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onOpen(chat),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.42),
                        border: Border.all(
                          color: theme.dividerColor.withOpacity(0.18),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: theme.colorScheme.primary.withOpacity(0.10),
                            child: Icon(Icons.forum_outlined,
                                color: theme.colorScheme.primary, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  chat.subjectLabel.trim().isEmpty
                                      ? chat.gradeLabel
                                      : '${chat.gradeLabel} • ${chat.subjectLabel}',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  chat.lastMessage?.trim().isNotEmpty == true
                                      ? chat.lastMessage!
                                      : 'Sin mensajes recientes',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.78),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if ((chat.lastSenderName ?? '').trim().isNotEmpty)
                                      _SoftInfoChip(
                                        icon: Icons.person_outline,
                                        label: chat.lastSenderName!,
                                      ),
                                    if (chat.lastAt != null)
                                      _SoftInfoChip(
                                        icon: Icons.schedule_outlined,
                                        label: _fmtDateTime(chat.lastAt!),
                                      ),
                                    if (chat.unreadCount > 0)
                                      _SoftInfoChip(
                                        icon: Icons.mark_chat_unread_outlined,
                                        label: '${chat.unreadCount} sin leer',
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right,
                              color: theme.iconTheme.color?.withOpacity(0.58)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _TeacherStateChip extends StatelessWidget {
  final bool enabled;

  const _TeacherStateChip({required this.enabled});

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? Colors.green.shade800 : Colors.amber.shade900;
    final bg = enabled ? Colors.green.withOpacity(0.10) : Colors.amber.withOpacity(0.12);
    final border =
        enabled ? Colors.green.withOpacity(0.26) : Colors.amber.withOpacity(0.30);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            enabled ? Icons.verified_outlined : Icons.block_outlined,
            size: 15,
            color: fg,
          ),
          const SizedBox(width: 6),
          Text(
            enabled ? 'Activo' : 'Pendiente',
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherStateDot extends StatelessWidget {
  final bool enabled;

  const _TeacherStateDot({required this.enabled});

  @override
  Widget build(BuildContext context) {
    final c = enabled ? Colors.green.shade600 : Colors.amber.shade700;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c,
        boxShadow: [BoxShadow(blurRadius: 10, color: c.withOpacity(0.28))],
      ),
    );
  }
}

class _SoftInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SoftInfoChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.42),
        border: Border.all(color: theme.dividerColor.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade900, Colors.indigo.shade700],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
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
    final text = v == null ? '-' : '${(v * 100).toStringAsFixed(0)}%';

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
  final String? helper;

  const _MiniStat({required this.label, required this.value, this.helper});

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
          Text(value, style: theme.textTheme.bodySmall),
          if (helper != null && helper!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              helper!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.72),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

DateTime? _readDateTimeOrNull(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
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
/// Semaforo
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
            ? 'Atencion'
            : 'Critico';

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

String _fmtDateTime(DateTime d) {
  final hh = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
  final mm = d.minute.toString().padLeft(2, '0');
  final ap = d.hour >= 12 ? 'PM' : 'AM';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} $hh:$mm $ap';
}

String _fmtSimpleDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _attendanceDateKey(DateTime d) =>
    '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

DateTime? _attendanceDateFromKey(String raw) {
  final value = raw.trim();
  if (!RegExp(r'^\d{8}$').hasMatch(value)) return null;
  final year = int.tryParse(value.substring(0, 4));
  final month = int.tryParse(value.substring(4, 6));
  final day = int.tryParse(value.substring(6, 8));
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

bool _readBoolish(dynamic value) {
  if (value is bool) return value;
  final raw = (value ?? '').toString().trim().toLowerCase();
  return raw == 'true' || raw == '1' || raw == 'si' || raw == 'sí';
}

/// ------------------------------
/// Modelos (UI)
/// ------------------------------
class TeacherSummary {
  final String teacherId;
  final String teacherUid;
  final String nombreCompleto;
  final String nivelAsignado;
  final String gradoAsignado;
  final List<String> gradeIds;
  final List<String> gradeNames;
  final List<String> subjectIds;
  final List<String> subjectNames;
  final bool enabled;

  // KPIs agregados (ideal: guardarlos en teachers para lista rapida)
  final double? kpiCurricular;
  final double? kpiLogro;
  final double? kpiAttendance;

  TeacherSummary({
    required this.teacherId,
    required this.teacherUid,
    required this.nombreCompleto,
    required this.nivelAsignado,
    required this.gradoAsignado,
    required this.gradeIds,
    required this.gradeNames,
    required this.subjectIds,
    required this.subjectNames,
    required this.enabled,
    required this.kpiCurricular,
    required this.kpiLogro,
    required this.kpiAttendance,
  });

  List<String> get effectiveGradeNames {
    if (gradeNames.isNotEmpty) return gradeNames;
    if (gradoAsignado.trim().isNotEmpty && gradoAsignado.trim() != '-') {
      return [gradoAsignado.trim()];
    }
    return const [];
  }

  List<String> get effectiveSubjectNames => subjectNames;

  String get gradesLabel =>
      effectiveGradeNames.isEmpty ? 'Sin grados asignados' : effectiveGradeNames.join(', ');

  String get subjectsLabel =>
      effectiveSubjectNames.isEmpty ? 'Sin asignaturas registradas' : effectiveSubjectNames.join(', ');

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

class TeacherMonitoringSnapshot {
  final int totalStudents;
  final int totalGrades;
  final int totalSubjects;
  final int totalPlans;
  final int completedPlans;
  final List<PlanMonitoringItem> plans;
  final List<ChatPreviewItem> chats;

  const TeacherMonitoringSnapshot({
    required this.totalStudents,
    required this.totalGrades,
    required this.totalSubjects,
    required this.totalPlans,
    required this.completedPlans,
    required this.plans,
    required this.chats,
  });
}

class PlanMonitoringItem {
  final String id;
  final String gradeLabel;
  final String subjectLabel;
  final String schoolYear;
  final int unitsCount;
  final DateTime? updatedAt;
  final bool completed;

  const PlanMonitoringItem({
    required this.id,
    required this.gradeLabel,
    required this.subjectLabel,
    required this.schoolYear,
    required this.unitsCount,
    required this.updatedAt,
    required this.completed,
  });
}

class ChatPreviewItem {
  final String threadId;
  final String gradeId;
  final String gradeLabel;
  final String subjectId;
  final String subjectLabel;
  final String? lastMessage;
  final String? lastSenderName;
  final DateTime? lastAt;
  final int unreadCount;

  const ChatPreviewItem({
    required this.threadId,
    required this.gradeId,
    required this.gradeLabel,
    required this.subjectId,
    required this.subjectLabel,
    required this.lastMessage,
    required this.lastSenderName,
    required this.lastAt,
    required this.unreadCount,
  });
}

class AttendanceSummary {
  final int present;
  final int absent;
  final int excused;

  AttendanceSummary({
    required this.present,
    required this.absent,
    required this.excused,
  });

  int get total => present + absent + excused;
}

class AttendanceEditAccess {
  final List<String> allowedPastDateKeys;
  final DateTime? updatedAt;
  final bool hasLegacyWideOpenAccess;
  final DateTime? legacyWideOpenUntil;

  const AttendanceEditAccess({
    required this.allowedPastDateKeys,
    required this.updatedAt,
    required this.hasLegacyWideOpenAccess,
    required this.legacyWideOpenUntil,
  });

  List<DateTime> get allowedPastDates {
    final list = allowedPastDateKeys
        .map(_attendanceDateFromKey)
        .whereType<DateTime>()
        .toList()
      ..sort((a, b) => a.compareTo(b));
    return list;
  }
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

/// Metricas curriculares calculadas uniendo:
/// - periodos oficiales
/// - planificacion anual (unidades + indicadores esperados)
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

  CollectionReference<Map<String, dynamic>> _teacherDirectoryCol(String schoolId) =>
      _schoolDoc(schoolId).collection('teacher_directory');

  CollectionReference<Map<String, dynamic>> _teachersPublicCol(String schoolId) =>
      _schoolDoc(schoolId).collection('teachers_public');

  /// 1) Lista rapida de docentes (ideal: KPIs ya calculados en teachers).
  Stream<List<TeacherSummary>> streamTeachers(String schoolId) {
    return _teachersCol(schoolId).snapshots().asyncMap((qs) async {
      final byId = <String, TeacherSummary>{};

      void absorb(TeacherSummary teacher) {
        if (teacher.teacherId.trim().isEmpty) return;
        final current = byId[teacher.teacherId];
        byId[teacher.teacherId] =
            current == null ? teacher : _mergeTeacherSummary(current, teacher);
      }

      void absorbMap(String fallbackId, Map<String, dynamic> data) {
        final teacherId = (data['teacherDocId'] ?? data['teacherId'] ?? fallbackId)
            .toString()
            .trim();
        absorb(_teacherFromMap(teacherId, data));
      }

      for (final doc in qs.docs) {
        absorb(_teacherFromDoc(doc));
      }

      final dirSnap = await _teacherDirectoryCol(schoolId).get();
      for (final doc in dirSnap.docs) {
        absorb(_teacherFromDoc(doc));
      }

      final pubSnap = await _teachersPublicCol(schoolId).get();
      for (final doc in pubSnap.docs) {
        absorb(_teacherFromDoc(doc));
      }

      final membersSnap = await _schoolDoc(schoolId).collection('members').get();
      for (final d in membersSnap.docs.where((d) {
        final role = (d.data()['role'] ?? d.data()['rol'] ?? '').toString().trim().toLowerCase();
        return role == 'teacher' || role == 'docente';
      })) {
        final data = Map<String, dynamic>.from(d.data());
        data['authUid'] = d.id;
        data['uid'] ??= d.id;
        data['teacherUid'] ??= d.id;
        absorbMap(d.id, data);
      }

      if (byId.isEmpty) {
        final usersSnap = await _db.collection('users').get();
        for (final doc in usersSnap.docs.where((d) {
          final data = d.data();
          final role = (data['role'] ?? data['rol'] ?? '').toString().trim().toLowerCase();
          final school = (data['schoolId'] ?? '').toString().trim();
          return school == schoolId && (role == 'teacher' || role == 'docente');
        })) {
          final data = Map<String, dynamic>.from(doc.data());
          data['authUid'] ??= doc.id;
          data['uid'] ??= doc.id;
          data['teacherUid'] ??= doc.id;
          absorbMap(doc.id, data);
        }
      }

      final list = byId.values.toList()
        ..sort(
          (a, b) => a.nombreCompleto.toLowerCase().compareTo(b.nombreCompleto.toLowerCase()),
        );
      return list;
    });
  }

  TeacherSummary _teacherFromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    return _teacherFromMap(d.id, d.data() ?? {});
  }

  TeacherSummary _mergeTeacherSummary(TeacherSummary current, TeacherSummary incoming) {
    List<String> mergeList(List<String> a, List<String> b) {
      final out = <String>[];
      for (final item in [...a, ...b]) {
        final v = item.trim();
        if (v.isEmpty) continue;
        if (!out.contains(v)) out.add(v);
      }
      return out;
    }

    String preferText(String a, String b, {Set<String> generic = const {}}) {
      final av = a.trim();
      final bv = b.trim();
      final aOk = av.isNotEmpty && !generic.contains(av.toLowerCase());
      final bOk = bv.isNotEmpty && !generic.contains(bv.toLowerCase());
      if (aOk && !bOk) return av;
      if (bOk && !aOk) return bv;
      if (aOk && bOk) return bv.length > av.length ? bv : av;
      return bv.isNotEmpty ? bv : av;
    }

    final mergedGradeNames = mergeList(current.gradeNames, incoming.gradeNames);
    final mergedSubjectNames = mergeList(current.subjectNames, incoming.subjectNames);
    final mergedGradeIds = mergeList(current.gradeIds, incoming.gradeIds);
    final mergedSubjectIds = mergeList(current.subjectIds, incoming.subjectIds);

    final mergedName = preferText(
      current.nombreCompleto,
      incoming.nombreCompleto,
      generic: const {'docente'},
    );

    final mergedGrade = preferText(
      current.gradoAsignado,
      incoming.gradoAsignado,
      generic: const {'-', 'sin nivel', 'sin grados asignados'},
    );

    final mergedLevel = preferText(
      current.nivelAsignado,
      incoming.nivelAsignado,
      generic: const {'sin nivel'},
    );

    return TeacherSummary(
      teacherId: current.teacherId,
      teacherUid: preferText(current.teacherUid, incoming.teacherUid),
      nombreCompleto: mergedName.isEmpty ? 'Docente' : mergedName,
      nivelAsignado: mergedLevel.isEmpty ? 'Sin nivel' : mergedLevel,
      gradoAsignado: mergedGrade.isEmpty ? '-' : mergedGrade,
      gradeIds: mergedGradeIds,
      gradeNames: mergedGradeNames,
      subjectIds: mergedSubjectIds,
      subjectNames: mergedSubjectNames,
      enabled: current.enabled || incoming.enabled,
      kpiCurricular: incoming.kpiCurricular ?? current.kpiCurricular,
      kpiLogro: incoming.kpiLogro ?? current.kpiLogro,
      kpiAttendance: incoming.kpiAttendance ?? current.kpiAttendance,
    );
  }

  TeacherSummary _teacherFromMap(String id, Map<String, dynamic> data) {
    final gradeNames = _extractGradeNames(data);
    final subjectNames = _extractSubjectNames(data);
    return TeacherSummary(
      teacherId: id,
      teacherUid: (data['authUid'] ?? data['uid'] ?? data['teacherUid'] ?? '').toString(),
      nombreCompleto: _teacherDisplayName(data),
      nivelAsignado: _teacherLevel(data),
      gradoAsignado: gradeNames.isNotEmpty ? gradeNames.first : '-',
      gradeIds: _extractGradeIds(data),
      gradeNames: gradeNames,
      subjectIds: _extractSubjectIds(data),
      subjectNames: subjectNames,
      enabled: _teacherEnabled(data),
      kpiCurricular: _asDoubleOrNull(data['kpi_curricular_score']),
      kpiLogro: _asDoubleOrNull(data['kpi_logro_score']),
      kpiAttendance: _asDoubleOrNull(data['kpi_attendance_rate']),
    );
  }

  String _teacherDisplayName(Map<String, dynamic> data) {
    final full = (data['nombreCompleto'] ??
            data['displayName'] ??
            data['name'] ??
            data['fullName'] ??
            data['teacherName'] ??
            '')
        .toString()
        .trim();
    if (full.isNotEmpty) return full;

    final nombres = (data['nombres'] ?? data['nombre'] ?? data['firstName'] ?? '').toString().trim();
    final apellidos = (data['apellidos'] ?? data['apellido'] ?? data['lastName'] ?? '').toString().trim();
    final joined = [nombres, apellidos].where((e) => e.isNotEmpty).join(' ').trim();
    if (joined.isNotEmpty) return joined;

    final email = (data['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email.split('@').first;

    return 'Docente';
  }

  String _teacherLevel(Map<String, dynamic> data) {
    final direct = (data['nivelAsignado'] ?? data['nivel'] ?? data['level'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    final grades = _extractGradeNames(data);
    if (grades.isNotEmpty) {
      final joined = grades.join(' ').toLowerCase();
      if (joined.contains('inicial')) return 'Inicial';
      if (joined.contains('primaria')) return 'Primaria';
      if (joined.contains('secundaria')) return 'Secundaria';
      return grades.first;
    }
    return 'Sin nivel';
  }

  bool _teacherEnabled(Map<String, dynamic> data) {
    if (data['enabled'] is bool) return data['enabled'] == true;
    if (data['active'] is bool) return data['active'] == true;
    return true;
  }

  List<String> _extractGradeIds(Map<String, dynamic> data) {
    final raw = data['gradeIds'] ??
        data['gradesIds'] ??
        data['gradoIds'] ??
        data['gradosIds'] ??
        data['gradeId'] ??
        data['gradoId'];
    return _asStringList(raw);
  }

  List<String> _extractGradeNames(Map<String, dynamic> data) {
    final out = <String>{};
    for (final key in [
      'gradeNames',
      'grades',
      'grados',
      'gradosAsignados',
      'grado',
      'gradoAsignado',
    ]) {
      out.addAll(_asStringList(data[key]));
    }
    return out.where((e) => e.trim().isNotEmpty).toList();
  }

  List<String> _extractSubjectIds(Map<String, dynamic> data) {
    final raw = data['subjectIds'] ?? data['subjectsIds'] ?? data['asignaturaIds'] ?? data['materiaIds'];
    return _asStringList(raw);
  }

  List<String> _extractSubjectNames(Map<String, dynamic> data) {
    final out = <String>{};
    for (final key in ['subjects', 'subjectNames', 'asignaturas', 'materias']) {
      out.addAll(_asStringList(data[key]));
    }
    return out.where((e) => e.trim().isNotEmpty).toList();
  }

  Future<TeacherMonitoringSnapshot> getTeacherMonitoringSnapshot({
    required String schoolId,
    required TeacherSummary teacher,
    required int anio,
  }) async {
    final gradeIds = teacher.gradeIds.toSet();
    final gradeNamesNorm = teacher.effectiveGradeNames.map(_norm).toSet();
    final subjectIds = teacher.subjectIds.toSet();
    final subjectNamesNorm = teacher.effectiveSubjectNames.map(_norm).toSet();

    final alumnosSnap = await _schoolDoc(schoolId).collection('alumnos').get();
    final totalStudents = alumnosSnap.docs.where((d) {
      final data = d.data();
      final alumnoGradeIds = {
        ..._asStringList(data['gradeIds']),
        ..._asStringList(data['gradoIds']),
        ..._asStringList(data['gradeId']),
        ..._asStringList(data['gradoId']),
      };
      return alumnoGradeIds.any(gradeIds.contains);
    }).length;

    final plansSnap = await _schoolDoc(schoolId).collection('planificaciones_anuales').get();
    final plans = plansSnap.docs.where((d) {
      final data = d.data();
      final dataYear = (data['anioEscolar'] ?? data['schoolYear'] ?? data['anio'] ?? '').toString();
      final matchesYear = dataYear.isEmpty || dataYear.contains(anio.toString());

      final dataTeacherDocId = (data['teacherDocId'] ?? '').toString().trim();
      final dataTeacherUid = (data['teacherUid'] ?? '').toString().trim();
      final matchesTeacher = dataTeacherDocId == teacher.teacherId ||
          (teacher.teacherUid.isNotEmpty && dataTeacherUid == teacher.teacherUid);

      final dataGradeId = (data['gradeId'] ?? '').toString().trim();
      final dataGrade = _norm((data['grado'] ?? data['grade'] ?? '').toString());
      final matchesGrade = (dataGradeId.isNotEmpty && gradeIds.contains(dataGradeId)) ||
          (dataGrade.isNotEmpty && gradeNamesNorm.contains(dataGrade));

      final dataSubjectId = (data['asignaturaId'] ?? data['subjectId'] ?? '').toString().trim();
      final dataSubject = _norm((data['asignatura'] ?? data['materia'] ?? data['subject'] ?? '').toString());
      final matchesSubject = subjectIds.isEmpty && subjectNamesNorm.isEmpty
          ? true
          : (dataSubjectId.isNotEmpty && subjectIds.contains(dataSubjectId)) ||
              (dataSubject.isNotEmpty && subjectNamesNorm.contains(dataSubject));

      return matchesYear && (matchesTeacher || matchesGrade) && matchesSubject;
    }).map((d) {
      final data = d.data();
      final units = _extractUnidadesFromPlan(data);
      final updatedAt = _asDateTimeOrNull(data['updatedAt']) ??
          _asDateTimeOrNull(data['updated_at']) ??
          _asDateTimeOrNull(data['createdAt']);
      final completed = units.isNotEmpty &&
          units.every((u) => ((u['estado'] ?? u['status'] ?? '').toString().toLowerCase() == 'completed'));
      return PlanMonitoringItem(
        id: d.id,
        gradeLabel: (data['grado'] ?? data['grade'] ?? teacher.gradesLabel).toString(),
        subjectLabel: (data['asignatura'] ?? data['materia'] ?? data['subject'] ?? teacher.subjectsLabel).toString(),
        schoolYear: (data['anioEscolar'] ?? data['schoolYear'] ?? data['anio'] ?? '').toString(),
        unitsCount: units.length,
        updatedAt: updatedAt,
        completed: completed,
      );
    }).toList()
      ..sort((a, b) => (b.updatedAt ?? DateTime(1900)).compareTo(a.updatedAt ?? DateTime(1900)));

    final chats = <ChatPreviewItem>[];
    final chatThreadsSnap = await _schoolDoc(schoolId).collection('chat_grados').get();
    for (final thread in chatThreadsSnap.docs) {
      final data = thread.data();
      final gradeId = (data['gradeId'] ?? '').toString().trim();
      final subjectId = (data['subjectId'] ?? '').toString().trim();
      final gradeLabel = (data['gradeName'] ?? data['grado'] ?? gradeId).toString().trim();
      final subjectLabel =
          (data['subjectName'] ?? data['asignatura'] ?? data['materia'] ?? subjectId)
              .toString()
              .trim();

      final matchesGrade = gradeId.isNotEmpty && gradeIds.contains(gradeId);
      final matchesSubject = subjectIds.isEmpty && subjectNamesNorm.isEmpty
          ? true
          : (subjectId.isNotEmpty && subjectIds.contains(subjectId)) ||
              (subjectLabel.isNotEmpty && subjectNamesNorm.contains(_norm(subjectLabel)));

      if (!matchesGrade || !matchesSubject) continue;

      chats.add(
        ChatPreviewItem(
          threadId: thread.id,
          gradeId: gradeId,
          gradeLabel: gradeLabel.isEmpty ? gradeId : gradeLabel,
          subjectId: subjectId,
          subjectLabel: subjectLabel.isEmpty ? subjectId : subjectLabel,
          lastMessage: (data['lastMessage'] ?? data['ultimoMensaje'] ?? '').toString(),
          lastSenderName: (data['lastSenderName'] ?? data['ultimoRemitente'] ?? '').toString(),
          lastAt: _asDateTimeOrNull(data['updatedAt']) ??
              _asDateTimeOrNull(data['lastAt']) ??
              _asDateTimeOrNull(data['timestamp']),
          unreadCount: (data['unreadCount'] is num) ? (data['unreadCount'] as num).toInt() : 0,
        ),
      );
    }
    chats.sort((a, b) => (b.lastAt ?? DateTime(1900)).compareTo(a.lastAt ?? DateTime(1900)));

    return TeacherMonitoringSnapshot(
      totalStudents: totalStudents,
      totalGrades: teacher.effectiveGradeNames.length,
      totalSubjects: teacher.effectiveSubjectNames.length,
      totalPlans: plans.length,
      completedPlans: plans.where((p) => p.completed).length,
      plans: plans,
      chats: chats,
    );
  }

  String _norm(String s) => s.trim().toLowerCase();

  Stream<List<Map<String, dynamic>>> streamGradeChatMessages({
    required String schoolId,
    required String threadId,
  }) {
    return _schoolDoc(schoolId)
        .collection('chat_grados')
        .doc(threadId)
        .collection('mensajes')
        .snapshots()
        .map((qs) {
          final list = qs.docs.map((d) {
            final m = Map<String, dynamic>.from(d.data());
            m['id'] = d.id;
            return m;
          }).toList();
          list.sort((a, b) {
            final ad = _asDateTimeOrNull(a['createdAt']) ??
                _asDateTimeOrNull(a['timestamp']) ??
                _asDateTimeOrNull(a['sentAt']) ??
                DateTime(1900);
            final bd = _asDateTimeOrNull(b['createdAt']) ??
                _asDateTimeOrNull(b['timestamp']) ??
                _asDateTimeOrNull(b['sentAt']) ??
                DateTime(1900);
            return ad.compareTo(bd);
          });
          return list;
        });
  }

  /// 2) Periodos academicos oficiales
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
      final id = d.id.toString().toUpperCase().trim();
      final code = (data['id'] ?? data['codigo'] ?? '').toString().toUpperCase().trim();
      final nombre = (data['nombre'] ?? '').toString().trim();
      final displayName = nombre.isNotEmpty ? nombre : (code.isNotEmpty ? code : id);
      final ordenSource = code.isNotEmpty ? code : displayName;
      final orden =
          (data['orden'] is num) ? (data['orden'] as num).toInt() : _guessOrdenFromId(ordenSource);
      final inicio = _asDateTimeOrNull(data['inicio']) ?? _asDateTimeOrNull(data['fechaInicio']);
      final fin = _asDateTimeOrNull(data['fin']) ?? _asDateTimeOrNull(data['fechaFin']);
      return PeriodoAcademico(id: id, nombre: displayName, inicio: inicio, fin: fin, orden: orden);
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

  /// 3) Trae planificacion anual del ano/grado
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
      // Si no hay indices o campos, no rompemos.
    }

    // Intento B: docId convencion "anio_grado" o "anio-grado"
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

  /// 4) METRICAS CURRICULARES:
  /// - planeado: unidades + indicadores desde planificacion anual
  /// - realizado: curricular_progress del docente
  /// - a tiempo: usando fechaFinReal <= fechaFin del periodo (si existe)
  Future<TeacherCurricularMetrics> getTeacherCurricularMetrics({
    required String schoolId,
    required TeacherSummary teacher,
    required int anio,
  }) async {
    final periodos = await getPeriodos(schoolId);
    final plan = await _findBestTeacherPlanForCurricularMetrics(
      schoolId: schoolId,
      teacher: teacher,
      anio: anio,
    );
    final firstPeriodoKey = periodos.isNotEmpty ? _periodoStorageKey(periodos.first.id) : 'P1';

    if (plan == null) {
      // fallback: aun puede mostrar algo con curricular_progress solo, pero sin "planeado"
      return TeacherCurricularMetrics(
        byPeriodo: {
          for (final p in periodos)
            _periodoDisplayLabel(p): PeriodoMetrics(
              unidadesPlaneadas: 0,
              unidadesCompletadas: 0,
              indicadoresTotales: 0,
              indicadoresLogrados: 0,
            ),
        },
        onTimeRate: null,
        note: 'No se encontro una planificacion anual vinculada a ${teacher.nombreCompleto} para este ciclo.',
      );
    }

    final unidades = _extractUnidadesFromPlan(plan); // lista de maps
    final Set<String> unidadIdsPlaneadas = {};
    final Map<String, PeriodoMetricsBuilder> builders = {
      for (final p in periodos) _periodoStorageKey(p.id): PeriodoMetricsBuilder(),
    };

    // 4.1 Planeado (unidades + indicadores esperados) por periodo
    for (int i = 0; i < unidades.length; i++) {
      final u = unidades[i];
      final unidadId = _unidadId(u, i);
      unidadIdsPlaneadas.add(unidadId);

      final periodoId = _resolvePeriodoStorageKey(
        periodos: periodos,
        raw: u['periodoId'] ?? u['periodo'] ?? u['periodoAcademico'],
      );
      final key = builders.containsKey(periodoId) ? periodoId : firstPeriodoKey;

      builders[key]!.unidadesPlaneadas += 1;

      final plannedIndicadores = _extractIndicadoresIds(u);
      builders[key]!.indicadoresTotales += plannedIndicadores.length;

      // guardamos el set planeado por unidad para luego cruzar con logrados
      builders[key]!.planeadosPorUnidad[unidadId] = plannedIndicadores;
    }

    // 4.2 Real (curricular_progress del docente)
    final progCol = _teachersCol(schoolId).doc(teacher.teacherId).collection('curricular_progress');
    final progSnap = await progCol.get();

    int onTimeCount = 0;
    int onTimeBase = 0;

    final periodoById = {for (final p in periodos) _periodoStorageKey(p.id): p};

    for (final d in progSnap.docs) {
      final data = d.data();
      final unidadId = d.id;

      if (_hasAcademicYearMetadata(data) && !_matchesAcademicYearInMap(data, anio)) {
        continue;
      }

      // Solo consideramos unidades que estan dentro de la planificacion de ese ano/grado
      if (unidadIdsPlaneadas.isNotEmpty && !unidadIdsPlaneadas.contains(unidadId)) continue;

      final status = (data['status'] ?? 'planned').toString();
      final isCompleted = status == 'completed';

      final periodoId = _resolvePeriodoStorageKey(
            periodos: periodos,
            raw: data['periodoId'] ?? data['periodo'] ?? data['periodoAcademico'],
          ) ??
          _periodoIdGuessByUnidad(builders, unidadId) ??
          firstPeriodoKey;
      final key = builders.containsKey(periodoId) ? periodoId : firstPeriodoKey;

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
      final key = _periodoStorageKey(p.id);
      final b = builders[key] ?? PeriodoMetricsBuilder();
      byPeriodo[_periodoDisplayLabel(p)] = b.build();
    }

    final onTimeRate = onTimeBase == 0 ? null : (onTimeCount / onTimeBase);

    final planGrade = (plan['grado'] ?? plan['grade'] ?? teacher.gradesLabel).toString().trim();
    final planSubject =
        (plan['asignatura'] ?? plan['materia'] ?? plan['subject'] ?? teacher.subjectsLabel)
            .toString()
            .trim();
    final planSummary = [planGrade, planSubject].where((e) => e.isNotEmpty).join(' / ');
    final note = 'Basado en periodos oficiales + planificacion anual'
        '${planSummary.isEmpty ? '' : ' ($planSummary)'} + curricular_progress.'
        '${onTimeRate == null ? " (A tiempo requiere fechas fin en periodos + fechaFinReal)" : ""}';

    return TeacherCurricularMetrics(byPeriodo: byPeriodo, onTimeRate: onTimeRate, note: note);
  }

  String? _periodoIdGuessByUnidad(Map<String, PeriodoMetricsBuilder> builders, String unidadId) {
    for (final e in builders.entries) {
      if (e.value.planeadosPorUnidad.containsKey(unidadId)) return e.key;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _findBestTeacherPlanForCurricularMetrics({
    required String schoolId,
    required TeacherSummary teacher,
    required int anio,
  }) async {
    final plansSnap = await _schoolDoc(schoolId).collection('planificaciones_anuales').get();

    final matches = plansSnap.docs.where((d) {
      return _matchesPlanForCurricularMetrics(
        data: d.data(),
        teacher: teacher,
        anio: anio,
      );
    }).toList();

    if (matches.isEmpty) return null;

    matches.sort((a, b) {
      final scoreA = _planMatchScoreForTeacher(a.data(), teacher);
      final scoreB = _planMatchScoreForTeacher(b.data(), teacher);
      if (scoreA != scoreB) return scoreB.compareTo(scoreA);

      final updatedA = _extractPlanUpdatedAt(a.data()) ?? DateTime(1900);
      final updatedB = _extractPlanUpdatedAt(b.data()) ?? DateTime(1900);
      return updatedB.compareTo(updatedA);
    });

    return matches.first.data();
  }

  bool _matchesPlanForCurricularMetrics({
    required Map<String, dynamic> data,
    required TeacherSummary teacher,
    required int anio,
  }) {
    if (!_matchesAcademicYearInMap(data, anio)) return false;

    final sameTeacher = _planMatchesTeacherIdentity(data, teacher);
    final sameGrade = _planMatchesTeacherGrade(data, teacher);
    final sameSubject = _planMatchesTeacherSubject(data, teacher);
    final hasTeacherRef = _planHasTeacherIdentity(data);

    if (!sameSubject) return false;
    if (sameTeacher) return true;
    if (hasTeacherRef) return false;
    return sameGrade;
  }

  int _planMatchScoreForTeacher(Map<String, dynamic> data, TeacherSummary teacher) {
    var score = 0;
    if (_planMatchesTeacherIdentity(data, teacher)) score += 100;
    if (_planMatchesTeacherGrade(data, teacher)) score += 20;
    if (_planMatchesTeacherSubject(data, teacher)) score += 20;
    if (_planHasTeacherIdentity(data)) score += 5;
    return score;
  }

  bool _planHasTeacherIdentity(Map<String, dynamic> data) {
    final teacherDocId = (data['teacherDocId'] ?? data['teacherId'] ?? '').toString().trim();
    final teacherUid = (data['teacherUid'] ?? data['createdByUid'] ?? '').toString().trim();
    return teacherDocId.isNotEmpty || teacherUid.isNotEmpty;
  }

  bool _planMatchesTeacherIdentity(Map<String, dynamic> data, TeacherSummary teacher) {
    final teacherDocId = (data['teacherDocId'] ?? data['teacherId'] ?? '').toString().trim();
    final teacherUid = (data['teacherUid'] ?? data['createdByUid'] ?? '').toString().trim();
    return teacherDocId == teacher.teacherId ||
        (teacher.teacherUid.trim().isNotEmpty && teacherUid == teacher.teacherUid.trim());
  }

  bool _planMatchesTeacherGrade(Map<String, dynamic> data, TeacherSummary teacher) {
    final gradeIds = teacher.gradeIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final gradeNamesNorm = teacher.effectiveGradeNames.map(_norm).toSet();
    final dataGradeId = (data['gradeId'] ?? data['gradoId'] ?? '').toString().trim();
    final dataGrade = _norm((data['grado'] ?? data['grade'] ?? '').toString());
    return (dataGradeId.isNotEmpty && gradeIds.contains(dataGradeId)) ||
        (dataGrade.isNotEmpty && gradeNamesNorm.contains(dataGrade));
  }

  bool _planMatchesTeacherSubject(Map<String, dynamic> data, TeacherSummary teacher) {
    final subjectIds = teacher.subjectIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final subjectNamesNorm = teacher.effectiveSubjectNames.map(_norm).toSet();
    final dataSubjectId = (data['asignaturaId'] ?? data['subjectId'] ?? '').toString().trim();
    final dataSubject = _norm((data['asignatura'] ?? data['materia'] ?? data['subject'] ?? '').toString());
    if (subjectIds.isEmpty && subjectNamesNorm.isEmpty) return true;
    return (dataSubjectId.isNotEmpty && subjectIds.contains(dataSubjectId)) ||
        (dataSubject.isNotEmpty && subjectNamesNorm.contains(dataSubject));
  }

  DateTime? _extractPlanUpdatedAt(Map<String, dynamic> data) {
    return _asDateTimeOrNull(data['updatedAt']) ??
        _asDateTimeOrNull(data['updated_at']) ??
        _asDateTimeOrNull(data['createdAt']) ??
        _asDateTimeOrNull(data['created_at']);
  }

  bool _matchesAcademicYearInMap(Map<String, dynamic> data, int anio) {
    final candidates = [
      data['anioEscolar'],
      data['schoolYear'],
      data['year'],
      data['anio'],
    ];

    for (final value in candidates) {
      if (_matchesAcademicYearValue(value, anio)) return true;
    }
    return false;
  }

  bool _hasAcademicYearMetadata(Map<String, dynamic> data) {
    for (final value in [data['anioEscolar'], data['schoolYear'], data['year'], data['anio']]) {
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      return true;
    }
    return false;
  }

  bool _matchesAcademicYearValue(dynamic value, int anio) {
    if (value == null) return false;
    if (value is num) {
      final year = value.toInt();
      return year == anio || year == (anio - 1);
    }

    final raw = value.toString().trim();
    if (raw.isEmpty) return false;

    final schoolYearMatch = RegExp(r'^(\d{4})\s*[-/]\s*(\d{4})$').firstMatch(raw);
    if (schoolYearMatch != null) {
      final start = int.tryParse(schoolYearMatch.group(1)!);
      final end = int.tryParse(schoolYearMatch.group(2)!);
      return start == anio || end == anio || start == (anio - 1) || end == (anio - 1);
    }

    final single = int.tryParse(raw);
    if (single != null) return single == anio || single == (anio - 1);

    return raw.contains(anio.toString()) || raw.contains((anio - 1).toString());
  }

  String _periodoStorageKey(String raw) => raw.trim().toUpperCase();

  String _periodoDisplayLabel(PeriodoAcademico periodo) {
    final nombre = periodo.nombre.trim();
    if (nombre.isNotEmpty) return nombre;
    final id = periodo.id.trim();
    return id.isEmpty ? 'Periodo' : id;
  }

  String? _resolvePeriodoStorageKey({
    required List<PeriodoAcademico> periodos,
    required dynamic raw,
  }) {
    final rawText = raw?.toString().trim() ?? '';
    if (rawText.isEmpty) return null;

    final rawToken = _periodoToken(rawText);

    for (final periodo in periodos) {
      if (_periodoTokenMatches(rawToken, _periodoToken(periodo.id))) {
        return _periodoStorageKey(periodo.id);
      }
    }

    for (final periodo in periodos) {
      if (_periodoTokenMatches(rawToken, _periodoToken(periodo.nombre))) {
        return _periodoStorageKey(periodo.id);
      }
    }

    return _periodoStorageKey(rawText);
  }

  String _periodoToken(String value) =>
      value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '');

  bool _periodoTokenMatches(String left, String right) {
    if (left.isEmpty || right.isEmpty) return false;
    if (left == right) return true;

    final shortPeriodo = RegExp(r'^P\d+$');
    if (shortPeriodo.hasMatch(left) && right.startsWith(left)) return true;
    if (shortPeriodo.hasMatch(right) && left.startsWith(right)) return true;
    return false;
  }

  /// 5) Asistencia del alumnado registrada por el docente
  Future<AttendanceSummary> getAttendanceSummary({
    required String schoolId,
    required TeacherSummary teacher,
    required DateTime month,
  }) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final monthKey = '${month.year}${month.month.toString().padLeft(2, '0')}';
    final asistenciaCol = _schoolDoc(schoolId).collection('asistencia');
    final sheetsSnap = await asistenciaCol.where('monthKey', isEqualTo: monthKey).get();
    final gradeIds = teacher.gradeIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final gradeNamesNorm = teacher.effectiveGradeNames.map(_norm).toSet();
    final teacherUid = teacher.teacherUid.trim();
    final teacherId = teacher.teacherId.trim();
    final teacherNameNorm = _norm(teacher.nombreCompleto);

    int present = 0, absent = 0, excused = 0;

    bool matchesTeacherSheet(Map<String, dynamic> data) {
      final dataTeacherUid = (data['teacherUid'] ?? '').toString().trim();
      final dataTeacherDocId = (data['teacherDocId'] ?? '').toString().trim();
      final dataTeacherId = (data['teacherId'] ?? '').toString().trim();
      final dataTeacherName = _norm(
        (data['teacherName'] ?? data['docente'] ?? data['teacher'] ?? '').toString(),
      );
      final dataGradeId = (data['gradeId'] ?? '').toString().trim();
      final dataGrade = _norm((data['gradeLabel'] ?? data['grado'] ?? data['grade'] ?? '').toString());

      final sameTeacher = (teacherUid.isNotEmpty &&
              (dataTeacherUid == teacherUid ||
                  dataTeacherDocId == teacherUid ||
                  dataTeacherId == teacherUid)) ||
          (teacherId.isNotEmpty &&
              (dataTeacherDocId == teacherId ||
                  dataTeacherId == teacherId ||
                  dataTeacherUid == teacherId)) ||
          (teacherNameNorm.isNotEmpty && dataTeacherName == teacherNameNorm);
      final sameGrade = gradeIds.isEmpty && gradeNamesNorm.isEmpty
          ? true
          : (dataGradeId.isNotEmpty && gradeIds.contains(dataGradeId)) ||
              (dataGrade.isNotEmpty && gradeNamesNorm.contains(dataGrade));
      return sameTeacher || sameGrade;
    }

    for (final sheet in sheetsSnap.docs) {
      final data = sheet.data();
      if (!matchesTeacherSheet(data)) continue;

      final rowsSnap = await sheet.reference.collection('rows').get();
      for (final row in rowsSnap.docs) {
        final rowData = row.data();
        rowData.forEach((key, value) {
          if (!key.startsWith('m_')) return;
          final dateKey = key.substring(2);
          if (dateKey.length != 8) return;
          final year = int.tryParse(dateKey.substring(0, 4));
          final monthNum = int.tryParse(dateKey.substring(4, 6));
          final day = int.tryParse(dateKey.substring(6, 8));
          if (year == null || monthNum == null || day == null) return;
          final dayDate = DateTime(year, monthNum, day);
          if (dayDate.isBefore(start) || !dayDate.isBefore(end)) return;

          final mark = (value ?? '').toString().trim().toUpperCase();
          switch (mark) {
            case 'P':
              present++;
              break;
            case 'A':
              absent++;
              break;
            case 'E':
              excused++;
              break;
          }
        });
      }
    }

    return AttendanceSummary(present: present, absent: absent, excused: excused);
  }

  Stream<AttendanceEditAccess> streamAttendanceEditAccess({
    required String schoolId,
    required TeacherSummary teacher,
  }) {
    return _teachersCol(schoolId).doc(teacher.teacherId).snapshots().map((doc) {
      final data = doc.data() ?? <String, dynamic>{};
      final allowedPastDateKeys = <String>{
        ..._asStringList(data['attendanceAllowedPastDates']),
        ..._asStringList(data['attendancePastAllowedDates']),
        ..._asStringList(data['attendanceEditAllowedDates']),
      }.where((value) => RegExp(r'^\d{8}$').hasMatch(value)).toList()
        ..sort();

      final legacyWideOpenAccess = _readBoolish(
            data['allowPastAttendanceEdit'] ??
                data['attendancePastAccess'] ??
                data['attendanceLateEntryEnabled'] ??
                data['canEditPastAttendance'] ??
                data['attendanceRetroactiveEnabled'],
          ) ||
          _asDateTimeOrNull(
                data['attendancePastAccessUntil'] ??
                    data['attendanceLateEntryUntil'] ??
                    data['pastAttendanceEditUntil'] ??
                    data['attendanceRetroactiveUntil'],
              ) !=
              null;

      return AttendanceEditAccess(
        allowedPastDateKeys: allowedPastDateKeys,
        updatedAt: _asDateTimeOrNull(data['attendanceAccessUpdatedAt']) ??
            _asDateTimeOrNull(data['updatedAt']),
        hasLegacyWideOpenAccess: legacyWideOpenAccess,
        legacyWideOpenUntil: _asDateTimeOrNull(
          data['attendancePastAccessUntil'] ??
              data['attendanceLateEntryUntil'] ??
              data['pastAttendanceEditUntil'] ??
              data['attendanceRetroactiveUntil'],
        ),
      );
    });
  }

  Future<void> setAttendanceAllowedPastDates({
    required String schoolId,
    required TeacherSummary teacher,
    required Set<String> allowedDateKeys,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Debes estar autenticado.');

    final cleaned = allowedDateKeys
        .map((e) => e.trim())
        .where((e) => RegExp(r'^\d{8}$').hasMatch(e))
        .toList()
      ..sort();

    final teacherRef = _teachersCol(schoolId).doc(teacher.teacherId);
    final payload = <String, dynamic>{
      'attendanceAllowedPastDates':
          cleaned.isEmpty ? FieldValue.delete() : cleaned,
      'attendancePastAllowedDates': FieldValue.delete(),
      'attendanceEditAllowedDates': FieldValue.delete(),
      'allowPastAttendanceEdit': FieldValue.delete(),
      'attendancePastAccess': FieldValue.delete(),
      'attendanceLateEntryEnabled': FieldValue.delete(),
      'canEditPastAttendance': FieldValue.delete(),
      'attendanceRetroactiveEnabled': FieldValue.delete(),
      'attendancePastAccessUntil': FieldValue.delete(),
      'attendanceLateEntryUntil': FieldValue.delete(),
      'pastAttendanceEditUntil': FieldValue.delete(),
      'attendanceRetroactiveUntil': FieldValue.delete(),
      'attendanceAccessUpdatedAt': FieldValue.serverTimestamp(),
      'attendanceAccessUpdatedBy': uid,
    };

    if (teacher.teacherUid.trim().isNotEmpty) {
      payload['authUid'] = teacher.teacherUid.trim();
    }

    await teacherRef.set(payload, SetOptions(merge: true));
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

  /// ---------------- Helpers: Planificacion ----------------
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

// Helpers genericos (DEJA SOLO ESTE BLOQUE)
double? _asDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim());
}

DateTime? _asDateTimeOrNull(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is String) return DateTime.tryParse(v.trim());
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
