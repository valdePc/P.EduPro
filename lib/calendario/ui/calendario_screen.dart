// lib/calendario/ui/calendario_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:edupro/calendario/models/user_role.dart';
import 'package:edupro/calendario/models/appointment_model.dart';
import 'package:edupro/calendario/services/appointments_service.dart';

class CalendarioScreen extends StatefulWidget {
  final String schoolId;
  final UserRole role;

  /// UID del usuario autenticado (o id del estudiante/docente si así lo manejas).
  final String userUid;

  /// Opcional: grupos del usuario (para futuro filtrado por grado/sección).
  final List<String> userGroups;

  /// Opcional: si vienes desde un Scaffold con AppBar propio y quieres ocultar el AppBar del calendario.
  final bool hideAppBar;

  const CalendarioScreen({
    super.key,
    required this.schoolId,
    required this.role,
    required this.userUid,
    this.userGroups = const [],
    this.hideAppBar = false,
  });

  @override
  State<CalendarioScreen> createState() => _CalendarioScreenState();
}

class _CalendarioScreenState extends State<CalendarioScreen> {
  final AppointmentsService _svc = AppointmentsService();

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  bool get _canWrite => widget.role == UserRole.admin;

  @override
  Widget build(BuildContext context) {
    final azul = const Color.fromARGB(255, 21, 101, 192);

    final body = LayoutBuilder(
      builder: (context, c) {
        final isWide = c.maxWidth >= 900;

        final calendar = _CalendarPanel(
          focusedDay: _focusedDay,
          selectedDay: _selectedDay,
          onDaySelected: (selected, focused) {
            setState(() {
              _selectedDay = selected;
              _focusedDay = focused;
            });
          },
        );

        final agenda = _AgendaPanel(
          schoolId: widget.schoolId,
          selectedDay: _selectedDay,
          role: widget.role,
          userUid: widget.userUid,
          service: _svc,
          canWrite: _canWrite,
        );

        if (isWide) {
          return Row(
            children: [
              Expanded(child: calendar),
              const VerticalDivider(width: 1),
              Expanded(child: agenda),
            ],
          );
        }

        return Column(
          children: [
            Expanded(flex: 5, child: calendar),
            const Divider(height: 1),
            Expanded(flex: 6, child: agenda),
          ],
        );
      },
    );

    if (widget.hideAppBar) return body;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: azul,
        title: const Text('Agenda'),
      ),
      body: body,
    );
  }
}

class _CalendarPanel extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime selectedDay;
  final void Function(DateTime selectedDay, DateTime focusedDay) onDaySelected;

  const _CalendarPanel({
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final azul = const Color.fromARGB(255, 21, 101, 192);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: focusedDay,
            selectedDayPredicate: (day) =>
                day.year == selectedDay.year &&
                day.month == selectedDay.month &&
                day.day == selectedDay.day,
            onDaySelected: onDaySelected,
            headerStyle: HeaderStyle(
              titleCentered: true,
              formatButtonVisible: false,
              titleTextStyle: const TextStyle(fontWeight: FontWeight.w700),
              leftChevronIcon: Icon(Icons.chevron_left, color: azul),
              rightChevronIcon: Icon(Icons.chevron_right, color: azul),
            ),
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                border: Border.all(color: azul, width: 1.5),
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: azul,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AgendaPanel extends StatelessWidget {
  final String schoolId;
  final DateTime selectedDay;
  final UserRole role;

  final String userUid;
  final AppointmentsService service;
  final bool canWrite;

  const _AgendaPanel({
    required this.schoolId,
    required this.selectedDay,
    required this.role,
    required this.userUid,
    required this.service,
    required this.canWrite,
  });

  @override
  Widget build(BuildContext context) {
    final azul = const Color.fromARGB(255, 21, 101, 192);
    final dayLabel = DateFormat('EEEE, d MMM y', 'es').format(selectedDay);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Citas: $dayLabel',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (canWrite)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: azul),
                      onPressed: () async {
                        await showDialog(
                          context: context,
                          builder: (_) => _CreateAppointmentDialog(
                            schoolId: schoolId,
                            selectedDay: selectedDay,
                            service: service,
                          ),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Agendar'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: StreamBuilder<List<AppointmentModel>>(
              stream: service.watchAppointmentsForDay(
                schoolId: schoolId,
                day: selectedDay,
              ),
              builder: (context, snap) {
                if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());

                final items = _filterByRole(role, snap.data!);

                if (items.isEmpty) {
                  return const Center(child: Text('No hay citas para este día.'));
                }

                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final a = items[i];
                    final time =
                        '${DateFormat('hh:mm a').format(a.start)} - ${DateFormat('hh:mm a').format(a.end)}';

                    return Card(
                      elevation: 1,
                      child: ListTile(
                        leading: Icon(
                          a.canceled ? Icons.cancel : Icons.event_available,
                          color: a.canceled ? Colors.red : azul,
                        ),
                        title: Text(
                          a.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            decoration: a.canceled ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(time),
                            Text(_audienceLabel(a.audience)),
                            if ((a.description ?? '').trim().isNotEmpty)
                              Text(
                                a.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                        trailing: canWrite
                            ? PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'cancel') {
                                    await service.cancelAppointment(
                                      schoolId: schoolId,
                                      appointmentId: a.id,
                                    );
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'cancel',
                                    child: Text('Cancelar (no borrar)'),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static List<AppointmentModel> _filterByRole(UserRole role, List<AppointmentModel> items) {
    bool visible(AudienceScope a) {
      switch (role) {
        case UserRole.admin:
          return true;
        case UserRole.teacher:
          return a == AudienceScope.adminTeachers || a == AudienceScope.adminTeachersStudents;
        case UserRole.student:
          return a == AudienceScope.adminTeachersStudents;
      }
    }

    return items.where((x) => visible(x.audience)).toList();
  }

  static String _audienceLabel(AudienceScope a) {
    switch (a) {
      case AudienceScope.adminOnly:
        return 'Solo Administración';
      case AudienceScope.adminTeachers:
        return 'Admin + Docentes';
      case AudienceScope.adminTeachersStudents:
        return 'Admin + Docentes + Alumnos';
    }
  }
}

class _CreateAppointmentDialog extends StatefulWidget {
  final String schoolId;
  final DateTime selectedDay;
  final AppointmentsService service;

  const _CreateAppointmentDialog({
    required this.schoolId,
    required this.selectedDay,
    required this.service,
  });

  @override
  State<_CreateAppointmentDialog> createState() => _CreateAppointmentDialogState();
}

class _CreateAppointmentDialogState extends State<_CreateAppointmentDialog> {
  final _title = TextEditingController();
  final _desc = TextEditingController();

  TimeOfDay _start = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 9, minute: 0);

  AudienceScope _audience = AudienceScope.adminOnly;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  DateTime _toDateTime(TimeOfDay t) => DateTime(
        widget.selectedDay.year,
        widget.selectedDay.month,
        widget.selectedDay.day,
        t.hour,
        t.minute,
      );

  bool _validateTimeRange() {
    final s = _toDateTime(_start);
    final e = _toDateTime(_end);
    return e.isAfter(s);
  }

  @override
  Widget build(BuildContext context) {
    final azul = const Color.fromARGB(255, 21, 101, 192);

    return AlertDialog(
      title: const Text('Agendar cita'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Título',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _desc,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _TimePick(
                      label: 'Inicio',
                      value: _start,
                      onPick: (t) => setState(() => _start = t),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TimePick(
                      label: 'Fin',
                      value: _end,
                      onPick: (t) => setState(() => _end = t),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AudienceScope>(
                value: _audience,
                decoration: const InputDecoration(
                  labelText: 'Quién lo ve',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: AudienceScope.adminOnly,
                    child: Text('Solo Administración'),
                  ),
                  DropdownMenuItem(
                    value: AudienceScope.adminTeachers,
                    child: Text('Admin + Docentes'),
                  ),
                  DropdownMenuItem(
                    value: AudienceScope.adminTeachersStudents,
                    child: Text('Admin + Docentes + Alumnos'),
                  ),
                ],
                onChanged: (v) => setState(() => _audience = v ?? AudienceScope.adminOnly),
              ),
              const SizedBox(height: 8),
              if (!_validateTimeRange())
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'La hora final debe ser mayor a la inicial.',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: azul),
          onPressed: _saving
              ? null
              : () async {
                  final title = _title.text.trim();
                  if (title.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('El título no puede estar vacío.')),
                    );
                    return;
                  }
                  if (!_validateTimeRange()) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('La hora final debe ser mayor a la inicial.')),
                    );
                    return;
                  }

                  setState(() => _saving = true);
                  try {
                    await widget.service.createAppointment(
                      schoolId: widget.schoolId,
                      title: title,
                      description: _desc.text,
                      start: _toDateTime(_start),
                      end: _toDateTime(_end),
                      audience: _audience,
                    );
                    if (mounted) Navigator.pop(context);
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$e')),
                    );
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

class _TimePick extends StatelessWidget {
  final String label;
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onPick;

  const _TimePick({
    required this.label,
    required this.value,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: value);
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Text(value.format(context)),
      ),
    );
  }
}
