// lib/admin_escolar/screens/A_notificaciones_y_reportes.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class ANotificacionesYRecomendacion extends StatefulWidget {
  final Escuela escuela;
  final String? schoolIdOverride;

  const ANotificacionesYRecomendacion({
    super.key,
    required this.escuela,
    this.schoolIdOverride,
  });

  @override
  State<ANotificacionesYRecomendacion> createState() => _ANotificacionesYRecomendacionState();
}

class _ANotificacionesYRecomendacionState extends State<ANotificacionesYRecomendacion> {
  final _db = FirebaseFirestore.instance;

  String? _schoolIdRaw;
  String? _schoolId;
  bool _resolvingSchool = true;
  String? _resolveError;

  // Filtros (valores internos únicos)
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'all'; // all, sent, scheduled, draft, archived
  String _typeFilter = 'all'; // all, notification, report, event
  String _audienceFilter = 'all'; // all, teachers, students, parents, staff

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

  // Solo limpia lo mínimo (Firestore no permite "/" en docId)
  String _cleanSchoolId(String v) => v.trim().replaceAll('/', '_');

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  DateTime? _tsToDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  String _fmtDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} • ${two(d.hour)}:${two(d.minute)}';
  }

  Future<String?> _tryResolveByDocId(String candidate) async {
    final doc = await _db.collection('schools').doc(candidate).get();
    if (doc.exists) return candidate;
    return null;
  }

  Future<String?> _tryResolveByQueries({
    required String uid,
    required String? candidate,
    required String schoolName,
  }) async {
    final candidatesToTry = <String>{
      uid.trim(),
      if (candidate != null && candidate.trim().isNotEmpty) candidate.trim(),
    }.toList();

    for (final v in candidatesToTry) {
      final qs1 = await _db.collection('schools').where('adminUid', isEqualTo: v).limit(1).get();
      if (qs1.docs.isNotEmpty) return qs1.docs.first.id;

      final qs2 = await _db.collection('schools').where('schoolAdminUid', isEqualTo: v).limit(1).get();
      if (qs2.docs.isNotEmpty) return qs2.docs.first.id;

      final qs3 = await _db.collection('schools').where('ownerUid', isEqualTo: v).limit(1).get();
      if (qs3.docs.isNotEmpty) return qs3.docs.first.id;

      final qs4 = await _db.collection('schools').where('createdByUid', isEqualTo: v).limit(1).get();
      if (qs4.docs.isNotEmpty) return qs4.docs.first.id;

      final qs5 = await _db.collection('schools').where('admins', arrayContains: v).limit(1).get();
      if (qs5.docs.isNotEmpty) return qs5.docs.first.id;
    }

    // último recurso por nombre
    final byNombre = await _db.collection('schools').where('nombre', isEqualTo: schoolName.trim()).limit(1).get();
    if (byNombre.docs.isNotEmpty) return byNombre.docs.first.id;

    final byName = await _db.collection('schools').where('name', isEqualTo: schoolName.trim()).limit(1).get();
    if (byName.docs.isNotEmpty) return byName.docs.first.id;

    return null;
  }

  Future<void> _resolveSchoolId() async {
    setState(() {
      _resolvingSchool = true;
      _resolveError = null;
    });

    try {
      // 0) Override explícito
      final override = widget.schoolIdOverride?.trim();
      if (override != null && override.isNotEmpty) {
        _schoolIdRaw = override;
        _schoolId = _cleanSchoolId(override);
        setState(() => _resolvingSchool = false);
        return;
      }

      // 1) Candidate desde tu util actual (puede ser docId real o uid del admin)
      final candidateRaw = normalizeSchoolIdFromEscuela(widget.escuela).trim();
      _schoolIdRaw = candidateRaw;
      final candidateClean = _cleanSchoolId(candidateRaw);

      // 2) Si candidate ya es docId real, listo
      final byDoc = await _tryResolveByDocId(candidateClean);
      if (byDoc != null) {
        _schoolId = byDoc;
        setState(() => _resolvingSchool = false);
        return;
      }

      // 3) Resolver por usuario logueado
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? '';
      if (uid.isEmpty) throw 'No hay usuario autenticado para resolver el colegio.';

      final schoolName = (widget.escuela.nombre ?? '').toString();
      final resolved = await _tryResolveByQueries(uid: uid, candidate: candidateClean, schoolName: schoolName);

      if (resolved == null || resolved.trim().isEmpty) {
        throw 'No pude encontrar el colegio en /schools. Candidato="$candidateClean".';
      }

      _schoolId = resolved.trim();
      setState(() => _resolvingSchool = false);
    } catch (e) {
      setState(() {
        _resolvingSchool = false;
        _resolveError = e.toString();
      });
    }
  }

  CollectionReference<Map<String, dynamic>> _alertsRef() {
    return _db.collection('schools').doc(_schoolId).collection('alerts');
  }

  bool _passesFilters(Map<String, dynamic> m) {
    final q = _searchCtrl.text.trim().toLowerCase();

    final type = (m['type'] ?? 'notification').toString();
    final status = (m['status'] ?? 'sent').toString();
    final audience = (m['audience'] ?? 'all').toString();

    if (_typeFilter != 'all' && type != _typeFilter) return false;
    if (_statusFilter != 'all' && status != _statusFilter) return false;
    if (_audienceFilter != 'all' && audience != _audienceFilter) return false;

    if (q.isEmpty) return true;

    final title = (m['title'] ?? '').toString().toLowerCase();
    final msg = (m['message'] ?? '').toString().toLowerCase();
    return title.contains(q) || msg.contains(q);
  }

  Future<void> _archiveDoc(String docId) async {
    await _alertsRef().doc(docId).update({'status': 'archived'});
    _toast('Archivado.');
  }

  Future<void> _openCreateAlertSheet() async {
    if (_schoolId == null) return;

    final azul = const Color.fromARGB(255, 21, 101, 192);
    final user = FirebaseAuth.instance.currentUser;

    // Valores internos
    String type = 'notification'; // notification, report, event
    String audience = 'all'; // all, teachers, students, parents, staff
    String priority = 'normal'; // low, normal, high
    String status = 'sent'; // sent, scheduled, draft

    DateTime? scheduledAt;

    // Para evento/confirmación
    bool confirmable = false;
    DateTime? eventAt;
    int reminderBeforeMinutes = 1440; // 1 día
    bool saveDraft = false;

    final titleCtrl = TextEditingController();
    final msgCtrl = TextEditingController();

    Future<void> pickDateTime({
      required BuildContext ctx,
      required DateTime initial,
      required void Function(DateTime) onPicked,
    }) async {
      final d = await showDatePicker(
        context: ctx,
        initialDate: initial,
        firstDate: DateTime(initial.year - 1, 1, 1),
        lastDate: DateTime(initial.year + 3, 12, 31),
      );
      if (d == null) return;
      final t = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(initial));
      if (t == null) return;
      onPicked(DateTime(d.year, d.month, d.day, t.hour, t.minute));
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;

        return StatefulBuilder(
          builder: (ctx, setModal) {
            final isEvent = type == 'event';

            String scheduleLabel() {
              if (saveDraft) return 'Borrador';
              if (scheduledAt == null) return 'Enviar ahora';
              return 'Programado: ${_fmtDateTime(scheduledAt!)}';
            }

            Future<void> pickSchedule() async {
              final now = DateTime.now();
              await pickDateTime(
                ctx: ctx,
                initial: now,
                onPicked: (dt) {
                  setModal(() {
                    scheduledAt = dt;
                    status = 'scheduled';
                    saveDraft = false;
                  });
                },
              );
            }

            Future<void> pickEvent() async {
              final now = DateTime.now();
              await pickDateTime(
                ctx: ctx,
                initial: eventAt ?? now,
                onPicked: (dt) {
                  setModal(() {
                    eventAt = dt;
                    // Por defecto, recordatorio = 1 día antes
                    if (scheduledAt == null) {
                      scheduledAt = dt.subtract(Duration(minutes: reminderBeforeMinutes));
                      if (scheduledAt!.isBefore(DateTime.now())) {
                        // si ya pasó, lo mandamos "ahora"
                        scheduledAt = null;
                        status = 'sent';
                      } else {
                        status = 'scheduled';
                      }
                    }
                  });
                },
              );
            }

            Future<void> submit() async {
              final title = titleCtrl.text.trim();
              final msg = msgCtrl.text.trim();

              if (title.isEmpty || msg.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Completa título y mensaje.')),
                );
                return;
              }

              // Draft manda status draft y no se programa
              if (saveDraft) {
                status = 'draft';
                scheduledAt = null;
              } else {
                status = scheduledAt == null ? 'sent' : 'scheduled';
              }

              // Si es evento con confirmación, obliga fecha
              if (isEvent && confirmable && eventAt == null) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Si es un evento confirmable, selecciona la fecha del evento.')),
                );
                return;
              }

              final createdAtClient = Timestamp.now();

              await _alertsRef().add({
                'type': type,
                'audience': audience,
                'priority': priority,
                'status': status,
                'title': title,
                'message': msg,

                // Tiempos
                'createdAt': FieldValue.serverTimestamp(),
                'createdAtClient': createdAtClient, // orden inmediato en UI
                'scheduledAt': scheduledAt == null ? null : Timestamp.fromDate(scheduledAt!),

                // Evento / asistencia
                'confirmable': confirmable,
                'eventAt': eventAt == null ? null : Timestamp.fromDate(eventAt!),
                'reminderBeforeMinutes': isEvent ? reminderBeforeMinutes : null,

                // Contadores listos para que luego se actualicen con respuestas reales
                'ackYes': confirmable ? 0 : null,
                'ackNo': confirmable ? 0 : null,
                'ackMaybe': confirmable ? 0 : null,

                // Auditoría
                'createdByUid': user?.uid ?? '',
                'createdByEmail': (user?.email ?? '').trim(),
              });

              if (!mounted) return;
              Navigator.pop(ctx);
              _toast(saveDraft ? 'Guardado como borrador.' : (status == 'scheduled' ? 'Guardado y programado.' : 'Enviado/guardado.'));
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottom),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Crear',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    _FieldLabel('Tipo'),
                    DropdownButtonFormField<String>(
                      value: type,
                      decoration: _inputDeco(hint: 'Selecciona tipo'),
                      items: const [
                        DropdownMenuItem(value: 'notification', child: Text('Notificación')),
                        DropdownMenuItem(value: 'report', child: Text('Reporte')),
                        DropdownMenuItem(value: 'event', child: Text('Evento (asistencia)')),
                      ],
                      onChanged: (v) {
                        setModal(() {
                          type = v ?? 'notification';
                          // Reset de campos de evento si cambias tipo
                          if (type != 'event') {
                            confirmable = false;
                            eventAt = null;
                            reminderBeforeMinutes = 1440;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 10),

                    _FieldLabel('Dirigido a'),
                    DropdownButtonFormField<String>(
                      value: audience,
                      decoration: _inputDeco(hint: 'Selecciona audiencia'),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('Todos')),
                        DropdownMenuItem(value: 'teachers', child: Text('Docentes')),
                        DropdownMenuItem(value: 'students', child: Text('Estudiantes')),
                        DropdownMenuItem(value: 'parents', child: Text('Padres')),
                        DropdownMenuItem(value: 'staff', child: Text('Administración')),
                      ],
                      onChanged: (v) => setModal(() => audience = v ?? 'all'),
                    ),
                    const SizedBox(height: 10),

                    _FieldLabel('Prioridad'),
                    DropdownButtonFormField<String>(
                      value: priority,
                      decoration: _inputDeco(hint: 'Selecciona prioridad'),
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Baja')),
                        DropdownMenuItem(value: 'normal', child: Text('Normal')),
                        DropdownMenuItem(value: 'high', child: Text('Alta')),
                      ],
                      onChanged: (v) => setModal(() => priority = v ?? 'normal'),
                    ),
                    const SizedBox(height: 10),

                    _FieldLabel('Título'),
                    TextField(
                      controller: titleCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: _inputDeco(hint: 'Ej: Reunión / Entrega de planificaciones'),
                    ),
                    const SizedBox(height: 10),

                    _FieldLabel('Mensaje'),
                    TextField(
                      controller: msgCtrl,
                      maxLines: 4,
                      decoration: _inputDeco(hint: 'Escribe el detalle aquí...'),
                    ),
                    const SizedBox(height: 12),

                    if (type == 'event') ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: azul.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: azul.withOpacity(0.14)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.event, color: azul),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Evento / Asistencia',
                                    style: TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                ),
                                Switch(
                                  value: confirmable,
                                  activeColor: azul,
                                  onChanged: (v) => setModal(() => confirmable = v),
                                ),
                              ],
                            ),
                            if (confirmable) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      eventAt == null ? 'Fecha del evento: no seleccionada' : 'Evento: ${_fmtDateTime(eventAt!)}',
                                      style: const TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: pickEvent,
                                    child: const Text('Elegir'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Text('Recordar: ', style: TextStyle(fontWeight: FontWeight.w800)),
                                  const SizedBox(width: 8),
                                  DropdownButton<int>(
                                    value: reminderBeforeMinutes,
                                    items: const [
                                      DropdownMenuItem(value: 60, child: Text('1 hora antes')),
                                      DropdownMenuItem(value: 180, child: Text('3 horas antes')),
                                      DropdownMenuItem(value: 1440, child: Text('1 día antes')),
                                      DropdownMenuItem(value: 2880, child: Text('2 días antes')),
                                    ],
                                    onChanged: (v) {
                                      if (v == null) return;
                                      setModal(() {
                                        reminderBeforeMinutes = v;
                                        if (eventAt != null) {
                                          final maybe = eventAt!.subtract(Duration(minutes: reminderBeforeMinutes));
                                          if (maybe.isAfter(DateTime.now())) {
                                            scheduledAt = maybe;
                                            status = 'scheduled';
                                            saveDraft = false;
                                          }
                                        }
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: azul.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: azul.withOpacity(0.14)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.schedule, color: azul),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              scheduleLabel(),
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          TextButton(
                            onPressed: saveDraft ? null : pickSchedule,
                            child: const Text('Programar'),
                          ),
                          if (scheduledAt != null && !saveDraft)
                            IconButton(
                              tooltip: 'Quitar programación',
                              onPressed: () => setModal(() {
                                scheduledAt = null;
                                status = 'sent';
                              }),
                              icon: const Icon(Icons.close),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.edit_note),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('Guardar como borrador', style: TextStyle(fontWeight: FontWeight.w900)),
                          ),
                          Switch(
                            value: saveDraft,
                            activeColor: azul,
                            onChanged: (v) => setModal(() {
                              saveDraft = v;
                              if (saveDraft) {
                                scheduledAt = null;
                                status = 'draft';
                              } else {
                                status = 'sent';
                              }
                            }),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: azul,
                          foregroundColor: Colors.white, // texto siempre legible
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                        ),
                        icon: const Icon(Icons.send),
                        label: Text(saveDraft ? 'Guardar borrador' : (scheduledAt != null ? 'Guardar programado' : 'Enviar / Guardar')),
                        onPressed: submit,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    titleCtrl.dispose();
    msgCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final azul = const Color.fromARGB(255, 21, 101, 192);
    final bg = const Color(0xFFF4F7FB);

    if (_resolvingSchool) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: const SizedBox.shrink(),
          leadingWidth: 0,
          title: const Text('Notificaciones y Reportes'),
          backgroundColor: azul,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_resolveError != null || _schoolId == null || _schoolId!.isEmpty) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: const SizedBox.shrink(),
          leadingWidth: 0,
          title: const Text('Notificaciones y Reportes'),
          backgroundColor: azul,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: _EmptyState(
          title: 'No se pudo identificar el colegio',
          subtitle: _resolveError ?? 'SchoolId vacío.',
        ),
      );
    }

    final schoolName = (widget.escuela.nombre ?? 'Colegio').toString();

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: const SizedBox.shrink(),
        leadingWidth: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notificaciones y Reportes'),
            Text(
              schoolName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: azul,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: azul,
        foregroundColor: Colors.white,
        onPressed: _openCreateAlertSheet,
        icon: const Icon(Icons.add),
        label: const Text('Crear'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          children: [
            _TopFilters(
              azul: azul,
              searchCtrl: _searchCtrl,
              statusValue: _statusFilter,
              typeValue: _typeFilter,
              audienceValue: _audienceFilter,
              onChanged: (s, t, a) {
                setState(() {
                  _statusFilter = s;
                  _typeFilter = t;
                  _audienceFilter = a;
                });
              },
              onSearchChanged: () => setState(() {}),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _alertsRef()
                    .orderBy('createdAtClient', descending: true)
                    .limit(80)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snap.data?.docs ?? [];
                  final items = docs
                      .map((d) => {'id': d.id, ...d.data()})
                      .where((m) => _passesFilters(m))
                      .toList();

                  // mini métricas (de lo cargado)
                  final sent = items.where((e) => (e['status'] ?? '') == 'sent').length;
                  final scheduled = items.where((e) => (e['status'] ?? '') == 'scheduled').length;
                  final drafts = items.where((e) => (e['status'] ?? '') == 'draft').length;

                  if (items.isEmpty) {
                    return _EmptyState(
                      title: 'No hay elementos',
                      subtitle: 'Crea una notificación, reporte o evento para empezar.',
                    );
                  }

                  return ListView(
                    children: [
                      _QuickStats(azul: azul, sent: sent, scheduled: scheduled, drafts: drafts),
                      const SizedBox(height: 12),
                      ...items.map((m) {
                        final id = (m['id'] ?? '').toString();
                        return _AlertCard(
                          azul: azul,
                          data: m,
                          tsToDate: _tsToDate,
                          fmtDateTime: _fmtDateTime,
                          onArchive: () => _archiveDoc(id),
                        );
                      }).toList(),
                      const SizedBox(height: 90),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ---------------- UI pieces ---------------- */

InputDecoration _inputDeco({String? hint}) {
  return InputDecoration(
    hintText: hint,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    filled: true,
    fillColor: const Color(0xFFF4F7FB),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black87),
        ),
      ),
    );
  }
}

class _TopFilters extends StatelessWidget {
  final Color azul;
  final TextEditingController searchCtrl;

  final String statusValue;
  final String typeValue;
  final String audienceValue;

  final void Function(String status, String type, String audience) onChanged;
  final VoidCallback onSearchChanged;

  const _TopFilters({
    required this.azul,
    required this.searchCtrl,
    required this.statusValue,
    required this.typeValue,
    required this.audienceValue,
    required this.onChanged,
    required this.onSearchChanged,
  });

  String _typeLabel(String v) {
    switch (v) {
      case 'notification':
        return 'Notificación';
      case 'report':
        return 'Reporte';
      case 'event':
        return 'Evento';
      default:
        return 'Todos';
    }
  }

  String _statusLabel(String v) {
    switch (v) {
      case 'sent':
        return 'Enviado';
      case 'scheduled':
        return 'Programado';
      case 'draft':
        return 'Borrador';
      case 'archived':
        return 'Archivado';
      default:
        return 'Todos';
    }
  }

  String _audienceLabel(String v) {
    switch (v) {
      case 'teachers':
        return 'Docentes';
      case 'students':
        return 'Estudiantes';
      case 'parents':
        return 'Padres';
      case 'staff':
        return 'Admins';
      default:
        return 'Todos';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: searchCtrl,
          onChanged: (_) => onSearchChanged(),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search, color: azul),
            hintText: 'Buscar por título o mensaje...',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: azul.withOpacity(0.14)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: typeValue,
                decoration: _miniDeco(label: 'Tipo'),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('Todos')),
                  const DropdownMenuItem(value: 'notification', child: Text('Notificación')),
                  const DropdownMenuItem(value: 'report', child: Text('Reporte')),
                  const DropdownMenuItem(value: 'event', child: Text('Evento')),
                ],
                selectedItemBuilder: (ctx) => [
                  Text(_typeLabel('all')),
                  Text(_typeLabel('notification')),
                  Text(_typeLabel('report')),
                  Text(_typeLabel('event')),
                ],
                onChanged: (v) => onChanged(statusValue, v ?? 'all', audienceValue),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: statusValue,
                decoration: _miniDeco(label: 'Estado'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Todos')),
                  DropdownMenuItem(value: 'sent', child: Text('Enviado')),
                  DropdownMenuItem(value: 'scheduled', child: Text('Programado')),
                  DropdownMenuItem(value: 'draft', child: Text('Borrador')),
                  DropdownMenuItem(value: 'archived', child: Text('Archivado')),
                ],
                onChanged: (v) => onChanged(v ?? 'all', typeValue, audienceValue),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: audienceValue,
                decoration: _miniDeco(label: 'Audiencia'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Todos')),
                  DropdownMenuItem(value: 'teachers', child: Text('Docentes')),
                  DropdownMenuItem(value: 'students', child: Text('Estudiantes')),
                  DropdownMenuItem(value: 'parents', child: Text('Padres')),
                  DropdownMenuItem(value: 'staff', child: Text('Admins')),
                ],
                onChanged: (v) => onChanged(statusValue, typeValue, v ?? 'all'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _miniDeco({required String label}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w800),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: azul.withOpacity(0.14)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    );
  }
}

class _QuickStats extends StatelessWidget {
  final Color azul;
  final int sent;
  final int scheduled;
  final int drafts;

  const _QuickStats({
    required this.azul,
    required this.sent,
    required this.scheduled,
    required this.drafts,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatCard(color: Colors.green, title: 'Enviados', value: sent.toString())),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(color: Colors.orange, title: 'Programados', value: scheduled.toString())),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(color: azul, title: 'Borradores', value: drafts.toString())),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final Color color;
  final String title;
  final String value;

  const _StatCard({
    required this.color,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.18)),
        boxShadow: const [
          BoxShadow(blurRadius: 12, offset: Offset(0, 10), color: Color(0x14000000)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.insights, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final Color azul;
  final Map<String, dynamic> data;
  final DateTime? Function(dynamic) tsToDate;
  final String Function(DateTime) fmtDateTime;
  final VoidCallback onArchive;

  const _AlertCard({
    required this.azul,
    required this.data,
    required this.tsToDate,
    required this.fmtDateTime,
    required this.onArchive,
  });

  String _labelType(String v) {
    switch (v) {
      case 'report':
        return 'Reporte';
      case 'event':
        return 'Evento';
      default:
        return 'Notificación';
    }
  }

  String _labelAudience(String v) {
    switch (v) {
      case 'teachers':
        return 'Docentes';
      case 'students':
        return 'Estudiantes';
      case 'parents':
        return 'Padres';
      case 'staff':
        return 'Admins';
      default:
        return 'Todos';
    }
  }

  Color _priorityColor(String v) {
    switch (v) {
      case 'high':
        return Colors.red;
      case 'low':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  Color _statusColor(String v) {
    switch (v) {
      case 'sent':
        return Colors.green;
      case 'scheduled':
        return Colors.orange;
      case 'draft':
        return Colors.blueGrey;
      case 'archived':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  String _statusLabel(String v) {
    switch (v) {
      case 'sent':
        return 'Enviado';
      case 'scheduled':
        return 'Programado';
      case 'draft':
        return 'Borrador';
      case 'archived':
        return 'Archivado';
      default:
        return v;
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = (data['type'] ?? 'notification').toString();
    final status = (data['status'] ?? 'sent').toString();
    final audience = (data['audience'] ?? 'all').toString();
    final priority = (data['priority'] ?? 'normal').toString();

    final title = (data['title'] ?? '').toString();
    final msg = (data['message'] ?? '').toString();

    final createdAt = tsToDate(data['createdAt']);
    final scheduledAt = tsToDate(data['scheduledAt']);

    final confirmable = (data['confirmable'] ?? false) == true;
    final ackYes = (data['ackYes'] is int) ? data['ackYes'] as int : 0;
    final ackNo = (data['ackNo'] is int) ? data['ackNo'] as int : 0;
    final ackMaybe = (data['ackMaybe'] is int) ? data['ackMaybe'] as int : 0;

    final badge = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: azul.withOpacity(0.12)),
        boxShadow: const [
          BoxShadow(blurRadius: 12, offset: Offset(0, 10), color: Color(0x12000000)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Chip(text: _labelType(type), color: azul),
              const SizedBox(width: 8),
              _Chip(text: _labelAudience(audience), color: Colors.black87),
              const SizedBox(width: 8),
              _Chip(text: priority == 'high' ? 'Alta' : (priority == 'low' ? 'Baja' : 'Normal'), color: _priorityColor(priority)),
              const Spacer(),
              _Chip(text: _statusLabel(status), color: badge),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            msg,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade800, height: 1.25),
          ),

          if (confirmable) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: azul.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: azul.withOpacity(0.14)),
              ),
              child: Row(
                children: [
                  Icon(Icons.how_to_reg, color: azul),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Confirmaciones: Sí $ackYes • No $ackNo • Tal vez $ackMaybe',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.access_time, size: 18, color: Colors.grey.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  scheduledAt != null
                      ? 'Programado: ${fmtDateTime(scheduledAt)}'
                      : createdAt != null
                          ? 'Creado: ${fmtDateTime(createdAt)}'
                          : 'Creado: —',
                  style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                ),
              ),
              if (status != 'archived')
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade800,
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  onPressed: onArchive,
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('Archivar'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Text(
        text,
        style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 12),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, size: 54, color: Colors.blueGrey),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
