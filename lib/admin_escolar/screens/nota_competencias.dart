import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart'
    show normalizeSchoolIdFromEscuela;

class NotaCompetenciasScreen extends StatefulWidget {
  final Escuela escuela;

  const NotaCompetenciasScreen({Key? key, required this.escuela})
    : super(key: key);

  @override
  State<NotaCompetenciasScreen> createState() => _NotaCompetenciasScreenState();
}

class _NotaCompetenciasScreenState extends State<NotaCompetenciasScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _blue = Color(0xFF1A237E);
  static const _orange = Color(0xFFFFA000);
  static const _ink = Color(0xFF17243A);
  static const _muted = Color(0xFF5C687A);
  static const _page = Color(0xFFF4F6FB);
  static const String _kBaseCompetenciasCol = 'competencias_base';
  static const List<String> _genericCompetencias = <String>[
    'Competencia 1',
    'Competencia 2',
    'Competencia 3',
    'Competencia 4',
  ];

  String _sid = '';
  String? _selectedSubjectId;
  String _selectedSubjectName = '';

  bool _loadingSubjects = true;
  bool _loadingDoc = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _subjects = [];

  final _p1Ctrl = TextEditingController();
  final _p2Ctrl = TextEditingController();
  final _p3Ctrl = TextEditingController();
  final _p4Ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sid = normalizeSchoolIdFromEscuela(widget.escuela).toString().trim();
    _loadSubjects();
  }

  @override
  void dispose() {
    _p1Ctrl.dispose();
    _p2Ctrl.dispose();
    _p3Ctrl.dispose();
    _p4Ctrl.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _subjectsCol =>
      _db.collection('schools').doc(_sid).collection('subjects');

  DocumentReference<Map<String, dynamic>> _baseCompetenciasRef(
    String subjectKey,
  ) => _db.collection(_kBaseCompetenciasCol).doc(subjectKey);

  Future<void> _loadSubjects() async {
    if (_sid.isEmpty) {
      setState(() => _loadingSubjects = false);
      return;
    }

    setState(() => _loadingSubjects = true);

    try {
      // Intento ordenado (si existe 'order')
      final snap =
          await _subjectsCol
              .orderBy('order', descending: false)
              .limit(500)
              .get();

      setState(() {
        _subjects = snap.docs;
        _loadingSubjects = false;
      });
    } catch (_) {
      // Fallback: sin order
      try {
        final snap = await _subjectsCol.limit(500).get();
        final docs = snap.docs.toList();

        docs.sort((a, b) {
          final an = (a.data()['name'] ?? '').toString().toLowerCase();
          final bn = (b.data()['name'] ?? '').toString().toLowerCase();
          return an.compareTo(bn);
        });

        setState(() {
          _subjects = docs;
          _loadingSubjects = false;
        });
      } catch (e) {
        setState(() => _loadingSubjects = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error cargando asignaturas: $e')),
          );
        }
      }
    }

    // Auto-seleccionar la primera si existe
    if (_subjects.isNotEmpty && _selectedSubjectId == null) {
      final first = _subjects.first;
      final name = (first.data()['name'] ?? '').toString();
      _selectedSubjectId = first.id;
      _selectedSubjectName = name;
      await _loadPeriodObjectives(first.id);
    }
  }

  Future<void> _loadPeriodObjectives(String subjectId) async {
    if (_sid.isEmpty) return;
    setState(() => _loadingDoc = true);

    try {
      final doc = await _subjectsCol.doc(subjectId).get();
      final data = doc.data() ?? <String, dynamic>{};
      final po =
          (data['periodObjectives'] is Map)
              ? Map<String, dynamic>.from(data['periodObjectives'] as Map)
              : <String, dynamic>{};

      String readPeriod(dynamic node) {
        if (node is String) return node.trim();
        if (node is List) {
          final values =
              node
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
          return values.join('\n');
        }
        if (node is Map) {
          final values =
              node.values
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
          return values.join('\n');
        }
        return '';
      }

      bool isGenericPeriod(dynamic node) {
        if (node is List) {
          final values =
              node
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
          if (values.length != 4) return false;
          for (int i = 0; i < 4; i++) {
            if (values[i] != _genericCompetencias[i]) return false;
          }
          return true;
        }

        final text = readPeriod(node);
        if (text.isEmpty) return false;
        final lines =
            text
                .split('\n')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
        if (lines.length != 4) return false;
        for (int i = 0; i < 4; i++) {
          if (lines[i] != _genericCompetencias[i]) return false;
        }
        return true;
      }

      String p1 = readPeriod(po['p1']);
      String p2 = readPeriod(po['p2']);
      String p3 = readPeriod(po['p3']);
      String p4 = readPeriod(po['p4']);

      final isGeneric =
          isGenericPeriod(po['p1']) &&
          isGenericPeriod(po['p2']) &&
          isGenericPeriod(po['p3']) &&
          isGenericPeriod(po['p4']);

      if ((p1.isEmpty && p2.isEmpty && p3.isEmpty && p4.isEmpty) || isGeneric) {
        final subjectKey =
            (data['subjectKey'] ?? '').toString().trim().isNotEmpty
                ? (data['subjectKey'] ?? '').toString().trim()
                : (subjectId.startsWith('def_')
                    ? subjectId.substring(4)
                    : subjectId);

        final base = await _baseCompetenciasRef(subjectKey).get();
        final baseData = base.data() ?? <String, dynamic>{};
        final basePo =
            (baseData['periodObjectives'] is Map)
                ? Map<String, dynamic>.from(baseData['periodObjectives'] as Map)
                : baseData;

        p1 = readPeriod(basePo['p1']);
        p2 = readPeriod(basePo['p2']);
        p3 = readPeriod(basePo['p3']);
        p4 = readPeriod(basePo['p4']);
      }

      _p1Ctrl.text = p1;
      _p2Ctrl.text = p2;
      _p3Ctrl.text = p3;
      _p4Ctrl.text = p4;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error cargando P1–P4: $e')));
      }
    } finally {
      if (mounted) setState(() => _loadingDoc = false);
    }
  }

  Widget _periodBox({
    required String title,
    required TextEditingController controller,
  }) {
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE3E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _orange.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: _blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (_selectedSubjectName.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          _selectedSubjectName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.visibility_outlined, color: _muted, size: 20),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: null,
              readOnly: true,
              style: const TextStyle(
                color: _ink,
                fontSize: 16,
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                hintText: 'Texto definido centralmente para este período.',
                hintStyle: TextStyle(color: _muted, fontSize: 14),
                filled: true,
                fillColor: Color(0xFFF7F8FC),
                contentPadding: EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                  borderSide: BorderSide(color: Color(0xFFE3E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                  borderSide: BorderSide(color: Color(0xFFE3E8F0)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_sid.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('Error: schoolId vacío. No se pudo enlazar la escuela.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        title: const Text('Competencias'),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadingSubjects ? null : _loadSubjects,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualizar asignaturas',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child:
            _loadingSubjects
                ? const Center(child: CircularProgressIndicator())
                : _subjects.isEmpty
                ? const Center(
                  child: Text('No hay asignaturas en esta escuela.'),
                )
                : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 18),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_blue, Color(0xFF303F9F)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: _blue.withOpacity(0.16),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.auto_stories_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Competencias académicas',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 5),
                                Text(
                                  'Consulta los aprendizajes por asignatura y período.',
                                  style: TextStyle(
                                    color: Color(0xFFE8EAF6),
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
                    const Text(
                      'Selecciona una asignatura',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedSubjectId,
                      isExpanded: true,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      items:
                          _subjects.map((d) {
                            final name = (d.data()['name'] ?? d.id).toString();
                            return DropdownMenuItem<String>(
                              value: d.id,
                              child: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                      onChanged: (id) async {
                        if (id == null) return;
                        final doc = _subjects.firstWhere((x) => x.id == id);
                        final name = (doc.data()['name'] ?? doc.id).toString();

                        setState(() {
                          _selectedSubjectId = id;
                          _selectedSubjectName = name;
                        });

                        await _loadPeriodObjectives(id);
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 15,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFFE3E8F0),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFFE3E8F0),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: _blue,
                            width: 1.5,
                          ),
                        ),
                        hintText: 'Elige una asignatura...',
                      ),
                    ),
                    const SizedBox(height: 16),

                    Expanded(
                      child:
                          _loadingDoc
                              ? const Center(child: CircularProgressIndicator())
                              : ListView(
                                children: [
                                  _periodBox(title: 'P1', controller: _p1Ctrl),
                                  _periodBox(title: 'P2', controller: _p2Ctrl),
                                  _periodBox(title: 'P3', controller: _p3Ctrl),
                                  _periodBox(title: 'P4', controller: _p4Ctrl),
                                  const SizedBox(height: 80),
                                ],
                              ),
                    ),
                  ],
                ),
      ),
    );
  }
}
