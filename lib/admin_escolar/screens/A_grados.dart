// lib/admin_escolar/screens/A_grados.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class AGrados extends StatefulWidget {
  final Escuela escuela;

  const AGrados({Key? key, required this.escuela}) : super(key: key);

  @override
  State<AGrados> createState() => _AGradosState();
}

class _AGradosState extends State<AGrados> {
  static const _blue = Color(0xFF0D47A1);
  static const _orange = Color(0xFFFFA000);

  final TextEditingController _gradoCtrl = TextEditingController();
  bool _saving = false;

  late final String _schoolId;

  // ✅ grados unificados (misma fuente para maestros/estudiantes)
  late final CollectionReference<Map<String, dynamic>> _gradosCol;

  @override
  void initState() {
    super.initState();
    _schoolId = normalizeSchoolIdFromEscuela(widget.escuela);

    // escuelas/{schoolId}/grados
    _gradosCol = FirebaseFirestore.instance
        .collection('escuelas')
        .doc(_schoolId)
        .collection('grados');
  }

  @override
  void dispose() {
    _gradoCtrl.dispose();
    super.dispose();
  }

  String _toKey(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _addGrado() async {
    final name = _gradoCtrl.text.trim();
    if (name.isEmpty) return;

    final key = _toKey(name);

    setState(() => _saving = true);
    try {
      // ✅ Evitar duplicados por key (mejor que por name)
      final existing = await _gradosCol.where('gradoKey', isEqualTo: key).limit(1).get();

      if (existing.docs.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ya existe un grado con ese nombre')),
        );
        return;
      }

      await _gradosCol.add({
        'name': name,
        'gradoKey': key,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _gradoCtrl.clear();
    } catch (e) {
      debugPrint('Error al agregar grado: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editGrado(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    if (data == null) return;

    final editCtrl = TextEditingController(text: data['name']?.toString() ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar grado'),
        content: TextField(
          controller: editCtrl,
          decoration: const InputDecoration(
            labelText: 'Nombre del grado',
            hintText: 'Ej: 5to A',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, editCtrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    final key = _toKey(result);

    try {
      // evita que lo edites a un nombre ya existente
      final existing = await _gradosCol.where('gradoKey', isEqualTo: key).limit(1).get();

      if (existing.docs.isNotEmpty && existing.docs.first.id != doc.id) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ya existe otro grado con ese nombre')),
        );
        return;
      }

      await _gradosCol.doc(doc.id).update({
        'name': result,
        'gradoKey': key,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error al editar grado: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _deleteGrado(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final name = doc.data()?['name']?.toString() ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar grado'),
        content: Text('¿Seguro que quieres eliminar "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _gradosCol.doc(doc.id).delete();
    } catch (e) {
      debugPrint('Error al eliminar grado: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Grados de la escuela',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: _blue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.escuela.nombre ?? '',
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _blue.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Text(
            'Aquí la administración define los grados de la institución.\n'
            'Esta lista se usa para DOCENTES y ESTUDIANTES (una sola fuente).',
            style: TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(top: 16, bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Agregar nuevo grado',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: _blue,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _gradoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del grado',
                      hintText: 'Ej: 5to A, 6to B, 3ro de Secundaria',
                    ),
                    onSubmitted: (_) {
                      if (!_saving) _addGrado();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _addGrado,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: const Text('Agregar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _orange,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradosList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _gradosCol.orderBy('name').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Text(
              'Todavía no hay grados configurados.\nAgrega el primero arriba.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          );
        }

        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final name = data['name']?.toString() ?? '—';
            final createdAt = data['createdAt'];
            String subtitle = '';

            if (createdAt is Timestamp) {
              final dt = createdAt.toDate();
              subtitle = 'Creado: ${DateFormat.yMMMd().add_Hm().format(dt)}';
            }

            return Card(
              elevation: 0,
              margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _blue.withOpacity(0.1),
                  child: const Icon(Icons.view_agenda, color: _blue),
                ),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Editar',
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _editGrado(doc),
                    ),
                    IconButton(
                      tooltip: 'Eliminar',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _deleteGrado(doc),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 720;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grados'),
        backgroundColor: _blue,
      ),
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildForm(),
            const SizedBox(height: 4),
            const Text(
              'Lista de grados',
              style: TextStyle(fontWeight: FontWeight.w600, color: _blue),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildGradosList()),
          ],
        ),
      ),
    );
  }
}
