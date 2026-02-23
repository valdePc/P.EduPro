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

  // ✅ Nuevo: nivel seleccionado
  static const List<String> _niveles = ['Inicial', 'Primaria', 'Secundaria'];
  String _nivelSel = 'Primaria';

  // ✅ grados unificados (misma fuente para maestros/estudiantes)
  late final CollectionReference<Map<String, dynamic>> _gradosCol;

  @override
  void initState() {
    super.initState();

    final rawId = normalizeSchoolIdFromEscuela(widget.escuela);
    final schoolDocId =
        rawId.startsWith('eduproapp_admin_') ? rawId : 'eduproapp_admin_$rawId';

    _gradosCol = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolDocId)
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

  // ✅ normaliza nivel para guardar
  String _nivelKey(String nivelUi) {
    final n = nivelUi.trim().toLowerCase();
    if (n.contains('inicial')) return 'inicial';
    if (n.contains('primaria')) return 'primaria';
    return 'secundaria';
  }

  // ✅ construye nombre final: "X de Primaria"
  String _buildFinalName(String baseName, String nivelUi) {
    final b = baseName.trim();
    final n = nivelUi.trim();

    // Si ya trae "de primaria/secundaria/inicial", no duplicar
    final lower = b.toLowerCase();
    if (lower.contains(' de primaria') ||
        lower.contains(' de secundaria') ||
        lower.contains(' de inicial')) {
      return b;
    }

    return '$b de $n';
  }

  Future<void> _addGrado() async {
    final baseName = _gradoCtrl.text.trim();
    if (baseName.isEmpty) return;

    final finalName = _buildFinalName(baseName, _nivelSel);
    final nivel = _nivelKey(_nivelSel);
    final key = _toKey(finalName);

    setState(() => _saving = true);
    try {
      // ✅ Evitar duplicados por key
      final existing =
          await _gradosCol.where('gradoKey', isEqualTo: key).limit(1).get();

      if (existing.docs.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ya existe un grado con ese nombre')),
        );
        return;
      }

final docRef = _gradosCol.doc(); // genera el ID antes de guardar

await docRef.set({
  'gradeId': docRef.id, // ✅ NUEVO: visible y coincide con el docId
  'name': finalName,
  'gradoKey': key,
  'nivel': nivel,
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

    // Si ya existe nivel, úsalo; si no, intenta inferir por el nombre.
    final existingNivel =
        (data['nivel'] ?? '').toString().trim().toLowerCase();
    String nivelUi = _nivelSel;
    if (existingNivel == 'inicial') nivelUi = 'Inicial';
    if (existingNivel == 'primaria') nivelUi = 'Primaria';
    if (existingNivel == 'secundaria') nivelUi = 'Secundaria';

    final rawName = (data['name'] ?? '').toString();

    // Para editar, quitamos " de X" al final si coincide
    String base = rawName;
    final low = rawName.toLowerCase();
    if (low.endsWith(' de primaria')) base = rawName.substring(0, rawName.length - ' de Primaria'.length);
    if (low.endsWith(' de secundaria')) base = rawName.substring(0, rawName.length - ' de Secundaria'.length);
    if (low.endsWith(' de inicial')) base = rawName.substring(0, rawName.length - ' de Inicial'.length);
    base = base.trim();

    final editCtrl = TextEditingController(text: base);

    String tempNivelUi = nivelUi;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setModal) => AlertDialog(
          title: const Text('Editar grado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: editCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre del grado',
                  hintText: 'Ej: 5to A, 6to B, 3ro',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: tempNivelUi,
                items: _niveles
                    .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                    .toList(),
                onChanged: (v) => setModal(() => tempNivelUi = v ?? tempNivelUi),
                decoration: const InputDecoration(
                  labelText: 'Nivel',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    final newBase = editCtrl.text.trim();
    if (newBase.isEmpty) return;

    final newName = _buildFinalName(newBase, tempNivelUi);
    final newNivel = _nivelKey(tempNivelUi);
    final key = _toKey(newName);

    try {
      final existing =
          await _gradosCol.where('gradoKey', isEqualTo: key).limit(1).get();

      if (existing.docs.isNotEmpty && existing.docs.first.id != doc.id) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ya existe otro grado con ese nombre')),
        );
        return;
      }

      await _gradosCol.doc(doc.id).update({
        'name': newName,
        'gradoKey': key,
        'nivel': newNivel,
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
            'Ahora cada grado indica si es Inicial, Primaria o Secundaria.',
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
                      hintText: 'Ej: 4to A, 2do, Pre-K',
                    ),
                    onSubmitted: (_) {
                      if (!_saving) _addGrado();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    value: _nivelSel,
                    items: _niveles
                        .map((n) =>
                            DropdownMenuItem(value: n, child: Text(n)))
                        .toList(),
                    onChanged:
                        _saving ? null : (v) => setState(() => _nivelSel = v ?? _nivelSel),
                    decoration: const InputDecoration(
                      labelText: 'Nivel',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                ),
              ),
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

        String prettyNivel(String v) {
          final n = v.trim().toLowerCase();
          if (n == 'inicial') return 'Inicial';
          if (n == 'primaria') return 'Primaria';
          if (n == 'secundaria') return 'Secundaria';
          return '';
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

            final nivel = prettyNivel((data['nivel'] ?? '').toString());
            if (nivel.isNotEmpty) {
              subtitle = 'Nivel: $nivel';
            }

            if (createdAt is Timestamp) {
              final dt = createdAt.toDate();
              final createdTxt =
                  'Creado: ${DateFormat.yMMMd().add_Hm().format(dt)}';
              subtitle = subtitle.isEmpty ? createdTxt : '$subtitle • $createdTxt';
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
                title:
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
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
