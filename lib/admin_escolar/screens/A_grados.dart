// lib/admin_escolar/screens/A_grados.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart'
    show normalizeSchoolIdFromEscuela;

class AGrados extends StatefulWidget {
  final Escuela escuela;

  const AGrados({Key? key, required this.escuela}) : super(key: key);

  @override
  State<AGrados> createState() => _AGradosState();
}

class _AGradosState extends State<AGrados> {
  static const _blue = Color(0xFF1A237E);
  static const _ink = Color(0xFF17243A);
  static const _muted = Color(0xFF5C687A);
  static const _page = Color(0xFFF4F6FB);

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

    // ✅ ID real de la escuela (sin prefijo)
    final schoolDocId = rawId;

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
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editGrado(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    if (data == null) return;

    // Si ya existe nivel, úsalo; si no, intenta inferir por el nombre.
    final existingNivel = (data['nivel'] ?? '').toString().trim().toLowerCase();
    String nivelUi = _nivelSel;
    if (existingNivel == 'inicial') nivelUi = 'Inicial';
    if (existingNivel == 'primaria') nivelUi = 'Primaria';
    if (existingNivel == 'secundaria') nivelUi = 'Secundaria';

    final rawName = (data['name'] ?? '').toString();

    // Para editar, quitamos " de X" al final si coincide
    String base = rawName;
    final low = rawName.toLowerCase();
    if (low.endsWith(' de primaria'))
      base = rawName.substring(0, rawName.length - ' de Primaria'.length);
    if (low.endsWith(' de secundaria'))
      base = rawName.substring(0, rawName.length - ' de Secundaria'.length);
    if (low.endsWith(' de inicial'))
      base = rawName.substring(0, rawName.length - ' de Inicial'.length);
    base = base.trim();

    final editCtrl = TextEditingController(text: base);

    String tempNivelUi = nivelUi;

    final result = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (_, setModal) => AlertDialog(
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
                        items:
                            _niveles
                                .map(
                                  (n) => DropdownMenuItem(
                                    value: n,
                                    child: Text(n),
                                  ),
                                )
                                .toList(),
                        onChanged:
                            (v) =>
                                setModal(() => tempNivelUi = v ?? tempNivelUi),
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
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _deleteGrado(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final name = doc.data()?['name']?.toString() ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
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
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildHeader() {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final schoolName = (widget.escuela.nombre ?? '').trim();
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 19 : 25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_blue, Color(0xFF3949AB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _blue.withOpacity(0.16),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 48 : 56,
            height: compact ? 48 : 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.school_rounded,
              color: Colors.white,
              size: 29,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Grados de la escuela',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 19 : 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (schoolName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    schoolName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE5E9FF),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Define los niveles y organiza los grados que utilizará la comunidad escolar.',
                  style: TextStyle(
                    color: Color(0xFFE5E9FF),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5EAF2)),
        boxShadow: [
          BoxShadow(
            color: _blue.withOpacity(0.035),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Agregar un grado',
            style: TextStyle(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Escribe el nombre y selecciona el nivel académico.',
            style: TextStyle(color: _muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              final fieldDecoration =
                  (String label, String hint, IconData icon) => InputDecoration(
                    labelText: label,
                    hintText: hint,
                    prefixIcon: Icon(icon, color: _blue, size: 20),
                    filled: true,
                    fillColor: const Color(0xFFF8F9FC),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 15,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE1E6EF)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: _blue, width: 1.4),
                    ),
                  );
              final nameField = TextField(
                controller: _gradoCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: fieldDecoration(
                  'Nombre del grado',
                  'Ej: 4to A, 2do, Pre-K',
                  Icons.edit_note_rounded,
                ),
                onSubmitted: (_) {
                  if (!_saving) _addGrado();
                },
              );
              final levelField = DropdownButtonFormField<String>(
                value: _nivelSel,
                isExpanded: true,
                items:
                    _niveles
                        .map(
                          (level) => DropdownMenuItem(
                            value: level,
                            child: Text(level),
                          ),
                        )
                        .toList(),
                onChanged:
                    _saving
                        ? null
                        : (value) =>
                            setState(() => _nivelSel = value ?? _nivelSel),
                decoration: fieldDecoration(
                  'Nivel académico',
                  'Selecciona el nivel',
                  Icons.school_outlined,
                ),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    nameField,
                    const SizedBox(height: 11),
                    levelField,
                    const SizedBox(height: 13),
                    SizedBox(
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _addGrado,
                        icon:
                            _saving
                                ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : const Icon(Icons.add_rounded),
                        label: const Text('Agregar grado'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: nameField),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: levelField),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _addGrado,
                      icon:
                          _saving
                              ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.add_rounded),
                      label: const Text('Agregar'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
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
              subtitle =
                  subtitle.isEmpty ? createdTxt : '$subtitle • $createdTxt';
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
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
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
    final compact = MediaQuery.sizeOf(context).width < 720;
    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text('Grados'),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 26,
            17,
            compact ? 14 : 26,
            10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              _buildForm(),
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.format_list_bulleted_rounded,
                      color: _blue,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Grados configurados',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildGradosList()),
            ],
          ),
        ),
      ),
    );
  }
}
