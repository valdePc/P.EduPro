// lib/admin_escolar/widgets/asignaturas.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Subject {
  final String id;
  String name;
  DateTime createdAt;

  Subject({required this.id, required this.name, DateTime? createdAt})
    : createdAt = createdAt ?? DateTime.now();
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
  return words
      .map((w) {
        if (w.isEmpty) return '';
        final first = w.substring(0, 1).toUpperCase();
        final rest = w.length > 1 ? w.substring(1).toLowerCase() : '';
        return '$first$rest';
      })
      .join(' ');
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
      throw StateError(
        'SubjectsService no está enlazado a una escuela (bindSchool).',
      );
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
      final snap =
          await _col.orderBy('order', descending: false).limit(500).get();
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
      final list =
          snap.docs.map((d) {
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

    return Subject(
      id: subject.id,
      name: normalized,
      createdAt: subject.createdAt,
    );
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

/// ✅ Para compatibilidad: servicio LOCAL en SharedPreferences
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
              final createdAt =
                  DateTime.tryParse((item['createdAt'] ?? '').toString()) ??
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
    final data =
        _list
            .map(
              (s) => {
                'id': s.id,
                'name': s.name,
                'createdAt': s.createdAt.toIso8601String(),
              },
            )
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
    final s = Subject(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: normalized,
    );
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
    final conflict = _list.any(
      (s) =>
          s.id != subject.id &&
          s.name.toLowerCase() == normalized.toLowerCase(),
    );
    if (conflict) {
      throw DuplicateSubjectException('La asignatura "$normalized" ya existe.');
    }
    _list[idx] = Subject(
      id: subject.id,
      name: normalized,
      createdAt: _list[idx].createdAt,
    );
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
  const SubjectsAdminScreen({Key? key, required this.service})
    : super(key: key);

  @override
  State<SubjectsAdminScreen> createState() => _SubjectsAdminScreenState();
}

class _SubjectsAdminScreenState extends State<SubjectsAdminScreen> {
  static const _blue = Color(0xFF1A237E);
  static const _ink = Color(0xFF17243A);
  static const _muted = Color(0xFF5C687A);
  static const _page = Color(0xFFF4F6FB);
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _showAddDialog() async {
    final ctrl = TextEditingController();
    final form = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text('Agregar asignatura'),
            content: Form(
              key: form,
              child: TextFormField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Nombre de la asignatura',
                ),
                validator:
                    (v) =>
                        (v == null || v.trim().length < 2)
                            ? 'Ingresa al menos 2 caracteres'
                            : null,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (!form.currentState!.validate()) return;
                  try {
                    await widget.service.addSubject(ctrl.text);
                    Navigator.pop(c, true);
                  } on DuplicateSubjectException catch (e) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(e.message)));
                  } catch (e) {
                    Navigator.pop(c, false);
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Asignatura agregada')));
      }
    }
  }

  Future<void> _showEditDialog(Subject s) async {
    final ctrl = TextEditingController(text: s.name);
    final form = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text('Editar asignatura'),
            content: Form(
              key: form,
              child: TextFormField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Nombre'),
                validator:
                    (v) =>
                        (v == null || v.trim().length < 2)
                            ? 'Ingresa al menos 2 caracteres'
                            : null,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (!form.currentState!.validate()) return;
                  try {
                    final copy = Subject(
                      id: s.id,
                      name: ctrl.text,
                      createdAt: s.createdAt,
                    );
                    await widget.service.updateSubject(copy);
                    Navigator.pop(c, true);
                  } on DuplicateSubjectException catch (e) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(e.message)));
                  } catch (e) {
                    Navigator.pop(c, false);
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Asignatura actualizada')));
      }
    }
  }

  Future<void> _confirmDelete(Subject s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text('Eliminar asignatura'),
            content: Text(
              '¿Eliminar "${s.name}"? Esta acción no puede deshacerse.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );

    if (ok == true) {
      await widget.service.deleteSubject(s.id);
      _changed = true;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Asignatura eliminada')));
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
    final filtered =
        _items.where((s) => s.name.toLowerCase().contains(q)).toList();
    final compact = MediaQuery.sizeOf(context).width < 700;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: _page,
        appBar: AppBar(
          title: const Text('Asignaturas'),
          centerTitle: false,
          backgroundColor: _blue,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _changed),
          ),
          actions: [
            IconButton(
              tooltip: 'Agregar asignatura',
              onPressed: _showAddDialog,
              icon: const Icon(Icons.add_rounded),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 14 : 26,
              18,
              compact ? 14 : 26,
              12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: EdgeInsets.all(compact ? 19 : 24),
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
                          Icons.menu_book_rounded,
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
                              'Catálogo de asignaturas',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: compact ? 19 : 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'Organiza las materias disponibles para tu comunidad educativa.',
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
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: const Color(0xFFE5EAF2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.library_books_outlined,
                        color: _blue,
                        size: 22,
                      ),
                      const SizedBox(width: 11),
                      const Expanded(
                        child: Text(
                          'Asignaturas registradas',
                          style: TextStyle(
                            color: _muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${_items.length}',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded, color: _blue),
                    hintText: 'Buscar una asignatura',
                    hintStyle: const TextStyle(color: _muted),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(color: Color(0xFFE5EAF2)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                      borderSide: const BorderSide(color: _blue, width: 1.4),
                    ),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 13),
                Expanded(
                  child:
                      _loading
                          ? const Center(
                            child: CircularProgressIndicator(color: _blue),
                          )
                          : filtered.isEmpty
                          ? Center(
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 30,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFE5EAF2),
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0F2FA),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: const Icon(
                                      Icons.menu_book_outlined,
                                      color: _blue,
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(height: 13),
                                  Text(
                                    _search.isEmpty
                                        ? 'Aún no hay asignaturas'
                                        : 'No encontramos coincidencias',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: _ink,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _search.isEmpty
                                        ? 'Agrega materias para completar el catálogo escolar.'
                                        : 'Prueba con otro nombre o revisa la búsqueda.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: _muted,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          : ListView.separated(
                            itemCount: filtered.length,
                            padding: const EdgeInsets.only(bottom: 8),
                            separatorBuilder:
                                (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final subject = filtered[i];
                              return Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: compact ? 13 : 17,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(17),
                                  border: Border.all(
                                    color: const Color(0xFFE5EAF2),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _blue.withOpacity(0.035),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF0F2FA),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Icon(
                                        Icons.auto_stories_rounded,
                                        color: _blue,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 13),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            subject.name,
                                            style: const TextStyle(
                                              color: _ink,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Creada: ${subject.createdAt.toLocal().toString().split(' ').first}',
                                            style: const TextStyle(
                                              color: _muted,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Editar asignatura',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _showEditDialog(subject),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        color: _blue,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Eliminar asignatura',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _confirmDelete(subject),
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Color(0xFFB84040),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
