// lib/admin_escolar/widgets/asignaturas.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Subject {
  final String id;
  String name;
  DateTime createdAt;

  Subject({
    required this.id,
    required this.name,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

class DuplicateSubjectException implements Exception {
  final String message;
  DuplicateSubjectException([this.message = 'Asignatura duplicada']);
  @override
  String toString() => message;
}

// Util: Title Case + limpia espacios
String normalizeSubjectName(String name) {
  final cleaned = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (cleaned.isEmpty) return '';
  final words = cleaned.split(' ');
  return words.map((w) {
    if (w.isEmpty) return '';
    final first = w.substring(0, 1).toUpperCase();
    final rest = w.length > 1 ? w.substring(1).toLowerCase() : '';
    return '$first$rest';
  }).join(' ');
}

/// ✅ Contrato único para cualquier implementación (Firestore / Local / Tests)
abstract class SubjectsService {
  /// Para servicios por escuela (Firestore). En servicios locales puede ser NO-OP.
  void bindSchool(String schoolId);

  /// Para inicializaciones (SharedPrefs). En Firestore es NO-OP.
  Future<void> init();

  Future<List<Subject>> getSubjects();
  Future<Subject> addSubject(String name);
  Future<Subject> updateSubject(Subject subject);
  Future<void> deleteSubject(String id);
  Future<void> reorderSubjects(List<Subject> subjects);
}

/// ✅ Implementación recomendada: Firestore por escuela
class FirestoreSubjectsService implements SubjectsService {
  final FirebaseFirestore _db;
  String? _schoolId;

  FirestoreSubjectsService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  @override
  void bindSchool(String schoolId) {
    _schoolId = schoolId.trim();
  }

  String get _sid {
    final v = _schoolId;
    if (v == null || v.isEmpty) {
      throw StateError('SubjectsService no está enlazado a una escuela (bindSchool).');
    }
    return v;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('schools').doc(_sid).collection('subjects');

  @override
  Future<void> init() async {
    // no-op
  }

  DateTime _readCreatedAt(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    final s = raw?.toString() ?? '';
    return DateTime.tryParse(s) ?? DateTime.now();
  }

  @override
  Future<List<Subject>> getSubjects() async {
    try {
      // Intento 1: si existe "order"
      final snap = await _col.orderBy('order', descending: false).limit(500).get();
      return snap.docs.map((d) {
        final m = d.data();
        return Subject(
          id: d.id,
          name: (m['name'] ?? d.id).toString(),
          createdAt: _readCreatedAt(m['createdAt']),
        );
      }).toList();
    } catch (_) {
      // Fallback: sin order (o sin índices)
      final snap = await _col.limit(500).get();
      final list = snap.docs.map((d) {
        final m = d.data();
        return Subject(
          id: d.id,
          name: (m['name'] ?? d.id).toString(),
          createdAt: _readCreatedAt(m['createdAt']),
        );
      }).toList();

      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    }
  }

  @override
  Future<Subject> addSubject(String name) async {
    final normalized = normalizeSubjectName(name);
    if (normalized.isEmpty) throw ArgumentError('Nombre vacío');

    final lower = normalized.toLowerCase();

    // Evitar duplicados por escuela
    final dup = await _col.where('nameLower', isEqualTo: lower).limit(1).get();
    if (dup.docs.isNotEmpty) {
      throw DuplicateSubjectException('La asignatura "$normalized" ya existe.');
    }

    final ref = _col.doc();
    final now = DateTime.now();
    final order = -now.millisecondsSinceEpoch; // nuevo arriba si orden asc

    await ref.set({
      'name': normalized,
      'nameLower': lower,
      'createdAt': FieldValue.serverTimestamp(),
      'order': order,
    });

    return Subject(id: ref.id, name: normalized, createdAt: now);
  }

  @override
  Future<Subject> updateSubject(Subject subject) async {
    final normalized = normalizeSubjectName(subject.name);
    if (normalized.isEmpty) throw ArgumentError('Nombre vacío');

    final lower = normalized.toLowerCase();

    // Evitar duplicados excepto sí mismo
    final dup = await _col.where('nameLower', isEqualTo: lower).limit(5).get();
    final conflict = dup.docs.any((d) => d.id != subject.id);
    if (conflict) {
      throw DuplicateSubjectException('La asignatura "$normalized" ya existe.');
    }

    await _col.doc(subject.id).set({
      'name': normalized,
      'nameLower': lower,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return Subject(id: subject.id, name: normalized, createdAt: subject.createdAt);
  }

  @override
  Future<void> deleteSubject(String id) async {
    await _col.doc(id).delete();
  }

  @override
  Future<void> reorderSubjects(List<Subject> subjects) async {
    // Guardamos order = 0..n
    final batch = _db.batch();
    for (int i = 0; i < subjects.length; i++) {
      final s = subjects[i];
      batch.set(_col.doc(s.id), {'order': i}, SetOptions(merge: true));
    }
    await batch.commit();
  }
}

/// ✅ Para que tu main.dart NO se rompa si todavía lo referencia.
/// (Este servicio es LOCAL en SharedPreferences; no sirve para catálogos por escuela en Firestore)
class PersistentSubjectsService implements SubjectsService {
  static const String _kKey = 'edupro_subjects_v1';
  final List<Subject> _list = [];
  bool _initialized = false;

  @override
  void bindSchool(String schoolId) {
    // No-op (es local)
  }

  @override
  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is List) {
          _list.clear();
          for (final item in decoded) {
            if (item is Map) {
              final id = (item['id'] ?? '').toString();
              final name = (item['name'] ?? '').toString();
              final createdAt = DateTime.tryParse((item['createdAt'] ?? '').toString()) ??
                  DateTime.now();
              if (id.isNotEmpty && name.isNotEmpty) {
                _list.add(Subject(id: id, name: name, createdAt: createdAt));
              }
            }
          }
        }
      } catch (_) {
        _list.clear();
      }
    }
    _initialized = true;
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _list
        .map((s) => {
              'id': s.id,
              'name': s.name,
              'createdAt': s.createdAt.toIso8601String(),
            })
        .toList();
    await prefs.setString(_kKey, json.encode(data));
  }

  @override
  Future<List<Subject>> getSubjects() async {
    if (!_initialized) await init();
    return List.unmodifiable(_list);
  }

  @override
  Future<Subject> addSubject(String name) async {
    if (!_initialized) await init();
    final normalized = normalizeSubjectName(name);
    if (normalized.isEmpty) throw ArgumentError('Nombre vacío');
    if (_list.any((s) => s.name.toLowerCase() == normalized.toLowerCase())) {
      throw DuplicateSubjectException('La asignatura "$normalized" ya existe.');
    }
    final s = Subject(id: DateTime.now().microsecondsSinceEpoch.toString(), name: normalized);
    _list.insert(0, s);
    await _saveToPrefs();
    return s;
  }

  @override
  Future<void> deleteSubject(String id) async {
    if (!_initialized) await init();
    _list.removeWhere((s) => s.id == id);
    await _saveToPrefs();
  }

  @override
  Future<Subject> updateSubject(Subject subject) async {
    if (!_initialized) await init();
    final idx = _list.indexWhere((s) => s.id == subject.id);
    if (idx < 0) throw ArgumentError('Asignatura no encontrada');
    final normalized = normalizeSubjectName(subject.name);
    final conflict = _list.any((s) =>
        s.id != subject.id && s.name.toLowerCase() == normalized.toLowerCase());
    if (conflict) throw DuplicateSubjectException('La asignatura "$normalized" ya existe.');
    _list[idx] = Subject(id: subject.id, name: normalized, createdAt: _list[idx].createdAt);
    await _saveToPrefs();
    return _list[idx];
  }

  @override
  Future<void> reorderSubjects(List<Subject> subjects) async {
    if (!_initialized) await init();
    _list
      ..clear()
      ..addAll(subjects);
    await _saveToPrefs();
  }
}

/// ✅ Instancia global compartida (USAMOS FIRESTORE por defecto)
final SubjectsService sharedSubjectsService = FirestoreSubjectsService();

/// ------------------------------------------------------------
/// UI: pantalla de administración de asignaturas
/// ------------------------------------------------------------
class SubjectsAdminScreen extends StatefulWidget {
  final SubjectsService service;
  const SubjectsAdminScreen({Key? key, required this.service}) : super(key: key);

  @override
  State<SubjectsAdminScreen> createState() => _SubjectsAdminScreenState();
}

class _SubjectsAdminScreenState extends State<SubjectsAdminScreen> {
  List<Subject> _items = [];
  String _search = '';
  bool _loading = true;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await widget.service.init(); // no-op en Firestore
      final list = await widget.service.getSubjects();
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _showAddDialog() async {
    final ctrl = TextEditingController();
    final form = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Agregar asignatura'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Nombre de la asignatura'),
            validator: (v) =>
                (v == null || v.trim().length < 2) ? 'Ingresa al menos 2 caracteres' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              try {
                await widget.service.addSubject(ctrl.text);
                Navigator.pop(c, true);
              } on DuplicateSubjectException catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
              } catch (e) {
                Navigator.pop(c, false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );

    if (result == true) {
      _changed = true;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Asignatura agregada')));
      }
    }
  }

  Future<void> _showEditDialog(Subject s) async {
    final ctrl = TextEditingController(text: s.name);
    final form = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Editar asignatura'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Nombre'),
            validator: (v) =>
                (v == null || v.trim().length < 2) ? 'Ingresa al menos 2 caracteres' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              try {
                final copy = Subject(id: s.id, name: ctrl.text, createdAt: s.createdAt);
                await widget.service.updateSubject(copy);
                Navigator.pop(c, true);
              } on DuplicateSubjectException catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
              } catch (e) {
                Navigator.pop(c, false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result == true) {
      _changed = true;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Asignatura actualizada')));
      }
    }
  }

  Future<void> _confirmDelete(Subject s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminar asignatura'),
        content: Text('¿Eliminar "${s.name}"? Esta acción no puede deshacerse.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
        ],
      ),
    );

    if (ok == true) {
      await widget.service.deleteSubject(s.id);
      _changed = true;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Asignatura eliminada')));
      }
    }
  }

  Future<bool> _onWillPop() async {
    Navigator.pop(context, _changed);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final filtered = _items.where((s) => s.name.toLowerCase().contains(q)).toList();

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administrar asignaturas'),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _changed),
          ),
          actions: [
            IconButton(onPressed: _showAddDialog, icon: const Icon(Icons.add)),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar asignaturas...',
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 12),
              _loading
                  ? const Expanded(child: Center(child: CircularProgressIndicator()))
                  : filtered.isEmpty
                      ? const Expanded(child: Center(child: Text('No hay asignaturas')))
                      : Expanded(
                          child: ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final s = filtered[i];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                child: ListTile(
                                  title: Text(
                                    s.name,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    'Creada: ${s.createdAt.toLocal().toString().split(' ').first}',
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => _showEditDialog(s),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => _confirmDelete(s),
                                      ),
                                    ],
                                  ),
                                ),
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
