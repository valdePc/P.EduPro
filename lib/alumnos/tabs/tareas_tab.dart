import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

const Color _blue = Color(0xFF0D47A1);
const Color _orange = Color(0xFFFFA000);

enum _TaskFilter { pendientes, entregadas, calificadas, todas }

class TareasTab extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> estRef;
  const TareasTab({super.key, required this.estRef});

  @override
  State<TareasTab> createState() => _TareasTabState();
}

class _TareasTabState extends State<TareasTab> {
  _TaskFilter _filter = _TaskFilter.pendientes;

  CollectionReference<Map<String, dynamic>> get _tareasCol =>
      widget.estRef.collection('tareas');

  Query<Map<String, dynamic>> get _baseQuery =>
      // ✅ IMPORTANTE: Sin where + orderBy combinados => NO pide índice compuesto
      _tareasCol.orderBy('createdAt', descending: true);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _baseQuery.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return _ErrorState(error: snap.error);
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final tasks = snap.data!.docs.map(_Task.fromDoc).toList();

            final pendientes = tasks.where((t) => t.estado == 'pendiente').length;
            final entregadas = tasks.where((t) => t.estado == 'entregada').length;
            final calificadas = tasks.where((t) => t.estado == 'calificada').length;

            final filtered = _applyFilter(tasks, _filter);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _TopStatsRow(
                  pendientes: pendientes,
                  entregadas: entregadas,
                  calificadas: calificadas,
                ),
                const SizedBox(height: 12),
                _FilterChips(
                  value: _filter,
                  onChanged: (v) => setState(() => _filter = v),
                ),
                const SizedBox(height: 12),
                _CardShell(
                  title: 'Listado de tareas',
                  subtitle: 'Crea, marca entregas y califica sin romperse por índices 😄',
                  icon: const Icon(Icons.checklist, color: _orange),
                  child: filtered.isEmpty
                      ? const _EmptyState()
                      : Column(
                          children: [
                            for (final t in filtered) ...[
                              _TaskTile(
                                task: t,
                                onTap: () => _openTaskActions(t),
                              ),
                              const Divider(height: 1),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: 90), // espacio para el FAB
              ],
            );
          },
        ),

        // FAB interno (porque esto está dentro de un Tab, no siempre hay Scaffold con fab)
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            backgroundColor: _blue,
            icon: const Icon(Icons.add),
            label: const Text('Nueva tarea'),
            onPressed: _openCreateTask,
          ),
        ),
      ],
    );
  }

  List<_Task> _applyFilter(List<_Task> all, _TaskFilter f) {
    switch (f) {
      case _TaskFilter.pendientes:
        return all.where((t) => t.estado == 'pendiente').toList();
      case _TaskFilter.entregadas:
        return all.where((t) => t.estado == 'entregada').toList();
      case _TaskFilter.calificadas:
        return all.where((t) => t.estado == 'calificada').toList();
      case _TaskFilter.todas:
        return all;
    }
  }

  Future<void> _openCreateTask() async {
    final res = await showDialog<_CreateTaskResult?>(
      context: context,
      builder: (_) => const _CreateTaskDialog(),
    );

    if (res == null) return;

    try {
      await _tareasCol.add({
        'titulo': res.titulo.trim(),
        'descripcion': res.descripcion.trim().isEmpty ? null : res.descripcion.trim(),
        'dueAt': res.dueAt == null ? null : Timestamp.fromDate(res.dueAt!),
        'estado': 'pendiente',
        'nota': null,
        'entregadaAt': null,
        'calificadaAt': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tarea creada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creando tarea: $e')),
      );
    }
  }

  Future<void> _openTaskActions(_Task t) async {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(_estadoIcon(t.estado), color: _estadoColor(t.estado)),
                  title: Text(t.titulo, style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text(
                    [
                      'Estado: ${t.estado}',
                      if (t.dueAt != null) 'Entrega: ${_fmtDate(t.dueAt!)}',
                      if (t.nota != null) 'Nota: ${t.nota}',
                    ].join(' • '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Divider(),

                if (t.estado != 'entregada')
                  _ActionBtn(
                    icon: Icons.assignment_turned_in,
                    text: 'Marcar como entregada',
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _updateTask(t.id, {
                        'estado': 'entregada',
                        'entregadaAt': FieldValue.serverTimestamp(),
                        'updatedAt': FieldValue.serverTimestamp(),
                      });
                    },
                  ),

                _ActionBtn(
                  icon: Icons.star,
                  text: 'Calificar',
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _openGradeDialog(t);
                  },
                ),

                _ActionBtn(
                  icon: Icons.refresh,
                  text: 'Volver a pendiente',
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _updateTask(t.id, {
                      'estado': 'pendiente',
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                  },
                ),

                const SizedBox(height: 8),

                _ActionBtn(
                  icon: Icons.delete,
                  text: 'Eliminar',
                  danger: true,
                  onTap: () async {
                    Navigator.pop(ctx);
                    final ok = await _confirmDelete();
                    if (!ok) return;
                    await _deleteTask(t.id);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openGradeDialog(_Task t) async {
    final nota = await showDialog<double?>(
      context: context,
      builder: (_) => _GradeDialog(initial: t.nota),
    );
    if (nota == null) return;

    await _updateTask(t.id, {
      'estado': 'calificada',
      'nota': nota,
      'calificadaAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _updateTask(String id, Map<String, dynamic> data) async {
    try {
      await _tareasCol.doc(id).update(data);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error actualizando: $e')),
      );
    }
  }

  Future<void> _deleteTask(String id) async {
    try {
      await _tareasCol.doc(id).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tarea eliminada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error eliminando: $e')),
      );
    }
  }

  Future<bool> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar tarea'),
        content: const Text('¿Seguro? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    return ok == true;
  }
}

/* --------------------------- Model --------------------------- */

class _Task {
  final String id;
  final String titulo;
  final String? descripcion;
  final DateTime? dueAt;
  final String estado; // pendiente | entregada | calificada
  final double? nota;

  _Task({
    required this.id,
    required this.titulo,
    required this.descripcion,
    required this.dueAt,
    required this.estado,
    required this.nota,
  });

  static _Task fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();

    DateTime? _ts(dynamic v) {
      if (v is Timestamp) return v.toDate();
      return null;
    }

    double? _num(dynamic v) {
      if (v is int) return v.toDouble();
      if (v is double) return v;
      return null;
    }

    return _Task(
      id: d.id,
      titulo: (data['titulo'] ?? 'Sin título').toString(),
      descripcion: data['descripcion']?.toString(),
      dueAt: _ts(data['dueAt']),
      estado: (data['estado'] ?? 'pendiente').toString(),
      nota: _num(data['nota']),
    );
  }
}

/* --------------------------- UI Pieces --------------------------- */

class _TopStatsRow extends StatelessWidget {
  final int pendientes;
  final int entregadas;
  final int calificadas;

  const _TopStatsRow({
    required this.pendientes,
    required this.entregadas,
    required this.calificadas,
  });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    final cards = [
      _MiniStat(title: 'Pendientes', value: pendientes.toString()),
      _MiniStat(title: 'Entregadas', value: entregadas.toString()),
      _MiniStat(title: 'Calificadas', value: calificadas.toString()),
    ];

    if (isWide) {
      return Row(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            Expanded(child: cards[i]),
            if (i != cards.length - 1) const SizedBox(width: 12),
          ]
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 12),
            Expanded(child: cards[1]),
          ],
        ),
        const SizedBox(height: 12),
        cards[2],
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String title;
  final String value;
  const _MiniStat({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
      ]),
    );
  }
}

class _FilterChips extends StatelessWidget {
  final _TaskFilter value;
  final ValueChanged<_TaskFilter> onChanged;

  const _FilterChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(_TaskFilter v, String label) {
      final selected = value == v;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onChanged(v),
        selectedColor: _blue.withOpacity(0.12),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w800,
          color: selected ? _blue : Colors.black87,
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        chip(_TaskFilter.pendientes, 'Pendientes'),
        chip(_TaskFilter.entregadas, 'Entregadas'),
        chip(_TaskFilter.calificadas, 'Calificadas'),
        chip(_TaskFilter.todas, 'Todas'),
      ],
    );
  }
}

class _TaskTile extends StatelessWidget {
  final _Task task;
  final VoidCallback onTap;

  const _TaskTile({required this.task, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _estadoColor(task.estado);
    final icon = _estadoIcon(task.estado);

    final subtitleBits = <String>[];
    if (task.dueAt != null) subtitleBits.add('Entrega: ${_fmtDate(task.dueAt!)}');
    if ((task.descripcion ?? '').trim().isNotEmpty) subtitleBits.add(task.descripcion!.trim());
    if (task.nota != null) subtitleBits.add('Nota: ${task.nota}');

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.12),
        child: Icon(icon, color: color),
      ),
      title: Text(task.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitleBits.isEmpty ? '—' : subtitleBits.join(' • '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _StatusChip(estado: task.estado),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String estado;
  const _StatusChip({required this.estado});

  @override
  Widget build(BuildContext context) {
    final color = _estadoColor(estado);
    final label = estado[0].toUpperCase() + estado.substring(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
        color: color.withOpacity(0.10),
      ),
      child: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w900, color: color),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Icon(Icons.inbox, size: 42, color: Colors.grey.shade500),
          const SizedBox(height: 10),
          Text(
            'No hay tareas para mostrar.',
            style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Pulsa "Nueva tarea" para crear la primera.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final bool danger;

  const _ActionBtn({
    required this.icon,
    required this.text,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = danger ? Colors.red : _blue;
    return ListTile(
      leading: Icon(icon, color: c),
      title: Text(text, style: TextStyle(fontWeight: FontWeight.w800, color: c)),
      onTap: onTap,
    );
  }
}

class _CardShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget icon;
  final Widget child;

  const _CardShell({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              icon,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Object? error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    // Si aún aparece "requires an index", aquí te va un mensaje humano
    final msg = error?.toString() ?? 'Error desconocido';
    final needsIndex = msg.contains('requires an index') || msg.contains('failed-precondition');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade300),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: needsIndex ? _orange : Colors.red, size: 40),
              const SizedBox(height: 10),
              Text(
                needsIndex
                    ? 'Firestore pidió un índice (consulta compuesta).'
                    : 'Error cargando tareas.',
                style: const TextStyle(fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                needsIndex
                    ? 'Con este archivo ya evitamos consultas que lo requieran. Si esto sigue saliendo, hay otra pantalla/archivo haciendo otra query.'
                    : msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 10),
              Text(
                'Tip: busca en el proyecto "collectionGroup(\'tareas\')" o ".where(...).orderBy(...)" y lo ajustamos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* --------------------------- Dialogs --------------------------- */

class _CreateTaskResult {
  final String titulo;
  final String descripcion;
  final DateTime? dueAt;
  _CreateTaskResult(this.titulo, this.descripcion, this.dueAt);
}

class _CreateTaskDialog extends StatefulWidget {
  const _CreateTaskDialog();

  @override
  State<_CreateTaskDialog> createState() => _CreateTaskDialogState();
}

class _CreateTaskDialogState extends State<_CreateTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titulo = TextEditingController();
  final _desc = TextEditingController();
  DateTime? _dueAt;

  @override
  void dispose() {
    _titulo.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva tarea'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titulo,
                decoration: const InputDecoration(
                  labelText: 'Título',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().length < 3) ? 'Escribe un título' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _desc,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Descripción (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text(_dueAt == null ? 'Fecha de entrega (opcional)' : _fmtDate(_dueAt!)),
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _dueAt ?? now,
                          firstDate: DateTime(now.year - 1),
                          lastDate: DateTime(now.year + 5),
                        );
                        if (picked == null) return;
                        setState(() => _dueAt = picked);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (_dueAt != null)
                    IconButton(
                      tooltip: 'Quitar fecha',
                      onPressed: () => setState(() => _dueAt = null),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _blue),
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(context, _CreateTaskResult(_titulo.text, _desc.text, _dueAt));
          },
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

class _GradeDialog extends StatefulWidget {
  final double? initial;
  const _GradeDialog({required this.initial});

  @override
  State<_GradeDialog> createState() => _GradeDialogState();
}

class _GradeDialogState extends State<_GradeDialog> {
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.initial?.toString() ?? '';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Calificar tarea'),
      content: TextField(
        controller: _ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Nota (ej: 10, 8.5)',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _blue),
          onPressed: () {
            final raw = _ctrl.text.trim().replaceAll(',', '.');
            final v = double.tryParse(raw);
            if (v == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Nota inválida')),
              );
              return;
            }
            Navigator.pop(context, v);
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/* --------------------------- Utils --------------------------- */

String _fmtDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm/${d.year}';
}

IconData _estadoIcon(String estado) {
  switch (estado) {
    case 'pendiente':
      return Icons.pending_actions;
    case 'entregada':
      return Icons.assignment_turned_in;
    case 'calificada':
      return Icons.grade;
    default:
      return Icons.task_alt;
  }
}

Color _estadoColor(String estado) {
  switch (estado) {
    case 'pendiente':
      return _orange;
    case 'entregada':
      return Colors.green;
    case 'calificada':
      return Colors.purple;
    default:
      return _blue;
  }
}
