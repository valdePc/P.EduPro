// lib/admin_escolar/screens/A_reuniones.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class AReuniones extends StatefulWidget {
  final Escuela escuela;
  const AReuniones({Key? key, required this.escuela}) : super(key: key);

  @override
  State<AReuniones> createState() => _AReunionesState();
}

class _AReunionesState extends State<AReuniones> {
  bool _loading = false;
  final List<Map<String, dynamic>> _reuniones = [];

  @override
  void initState() {
    super.initState();
    // ignore: avoid_print
    print('BUILD AReuniones for ${widget.escuela.nombre ?? 'escuela'}');
  }

  Future<void> _showCreateDialog() async {
    final titleCtrl = TextEditingController();
    DateTime? selectedDate;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (c, setC) {
        return AlertDialog(
          title: const Text('Crear reunión'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Título')),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text(selectedDate == null ? 'Sin fecha seleccionada' : selectedDate.toString())),
                  TextButton(
                    onPressed: () async {
                      final now = DateTime.now();
                      final d = await showDatePicker(
                        context: context,
                        initialDate: now,
                        firstDate: DateTime(now.year - 2),
                        lastDate: DateTime(now.year + 5),
                      );
                      if (d != null) setC(() => selectedDate = d);
                    },
                    child: const Text('Elegir fecha'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                final item = {
                  'title': title,
                  'date': (selectedDate ?? DateTime.now()).toIso8601String(),
                };
                setState(() => _reuniones.insert(0, item));
                Navigator.pop(ctx);
              },
              child: const Text('Crear'),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_reuniones.isEmpty) {
      return const Center(child: Text('No hay reuniones. Usa el botón + para crear una.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _reuniones.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, i) {
        final r = _reuniones[i];
        final dt = DateTime.tryParse(r['date'] ?? '') ?? DateTime.now();
        return ListTile(
          title: Text(r['title'] ?? 'Sin título'),
          subtitle: Text('${dt.toLocal()}'),
          leading: const Icon(Icons.meeting_room),
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            onPressed: () => setState(() => _reuniones.removeAt(i)),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reuniones')),
      body: _buildList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        tooltip: 'Crear reunión',
        child: const Icon(Icons.add),
      ),
    );
  }
}
