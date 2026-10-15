import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;
import '../services/competencias_service.dart';

const _competenciasBlue = Color(0xFF1A237E);

class ACompetencias extends StatelessWidget {
  final Escuela escuela;
  final CompetenciasService service;

  ACompetencias({
    Key? key,
    required this.escuela,
    CompetenciasService? service,
  })  : service = service ?? _DefaultCompetenciasService(),
        super(key: key);

  @override
  Widget build(BuildContext context) {
    final sid = normalizeSchoolIdFromEscuela(escuela);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Competencias'),
        backgroundColor: _competenciasBlue,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: service.streamSubjects(sid),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Error cargando asignaturas'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('No hay asignaturas todavia.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();
              final name = (data['name'] ?? '').toString().trim();
              final key = (data['subjectKey'] ?? '').toString().trim();
              final isDefault = data['isDefault'] == true;

              return ListTile(
                leading: Icon(isDefault ? Icons.verified : Icons.edit_note),
                title: Text(name.isEmpty ? '(Sin nombre)' : name),
                subtitle: Text('key: $key'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _CompetenciasBySubjectScreen(
                        sid: sid,
                        subjectDocId: d.id,
                        subjectName: name,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _DefaultCompetenciasService extends CompetenciasService {
  _DefaultCompetenciasService();
}

class _CompetenciasBySubjectScreen extends StatefulWidget {
  final String sid;
  final String subjectDocId;
  final String subjectName;

  const _CompetenciasBySubjectScreen({
    Key? key,
    required this.sid,
    required this.subjectDocId,
    required this.subjectName,
  }) : super(key: key);

  @override
  State<_CompetenciasBySubjectScreen> createState() => _CompetenciasBySubjectScreenState();
}

class _CompetenciasBySubjectScreenState extends State<_CompetenciasBySubjectScreen> {
  static const String _kFieldPeriodObjectives = 'periodObjectives';
  static const List<String> _periodKeys = ['p1', 'p2', 'p3', 'p4'];
  static const String _kBaseCompetenciasCol = 'competencias_base';

  final Map<String, List<TextEditingController>> _poCtrls = {
    'p1': List.generate(4, (_) => TextEditingController()),
    'p2': List.generate(4, (_) => TextEditingController()),
    'p3': List.generate(4, (_) => TextEditingController()),
    'p4': List.generate(4, (_) => TextEditingController()),
  };

  @override
  void dispose() {
    for (final list in _poCtrls.values) {
      for (final c in list) {
        c.dispose();
      }
    }
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>> _subjectRef() {
    return FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.sid)
        .collection(CompetenciasService.subjectsCol)
        .doc(widget.subjectDocId);
  }

  DocumentReference<Map<String, dynamic>> _baseCompetenciasRef(String subjectKey) {
    return FirebaseFirestore.instance.collection(_kBaseCompetenciasCol).doc(subjectKey);
  }

  List<String> _normalizeTo4(dynamic raw) {
    if (raw is List) {
      return List<String>.generate(4, (i) => i < raw.length ? raw[i].toString().trim() : '');
    }
    if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty) return List.filled(4, '');
      return <String>[s, '', '', ''];
    }
    if (raw is Map) {
      final m = raw.cast<String, dynamic>();
      String pick(String k) => (m[k] ?? '').toString().trim();
      return <String>[
        pick('c1').isNotEmpty ? pick('c1') : pick('1'),
        pick('c2').isNotEmpty ? pick('c2') : pick('2'),
        pick('c3').isNotEmpty ? pick('c3') : pick('3'),
        pick('c4').isNotEmpty ? pick('c4') : pick('4'),
      ];
    }
    return List.filled(4, '');
  }

  Map<String, List<String>> _extractPeriodObjectives(Map<String, dynamic> source) {
    final out = <String, List<String>>{
      'p1': List.filled(4, ''),
      'p2': List.filled(4, ''),
      'p3': List.filled(4, ''),
      'p4': List.filled(4, ''),
    };

    final po = source[_kFieldPeriodObjectives];
    if (po is Map) {
      final m = po.cast<String, dynamic>();
      for (final pk in _periodKeys) {
        out[pk] = _normalizeTo4(m[pk]);
      }
      return out;
    }

    for (final pk in _periodKeys) {
      out[pk] = _normalizeTo4(source[pk]);
    }
    return out;
  }

  String _subjectKeyFromData(Map<String, dynamic> data) {
    final fromDoc = (data['subjectKey'] ?? '').toString().trim();
    if (fromDoc.isNotEmpty) return fromDoc;
    if (widget.subjectDocId.startsWith('def_')) {
      return widget.subjectDocId.substring(4).trim();
    }
    return widget.subjectDocId.trim();
  }

  bool _isGeneric(Map<String, List<String>> data) {
    final p1 = data['p1'] ?? const <String>[];
    if (p1.length < 4) return false;
    return p1[0].trim() == 'Competencia 1' &&
        p1[1].trim() == 'Competencia 2' &&
        p1[2].trim() == 'Competencia 3' &&
        p1[3].trim() == 'Competencia 4';
  }

  Future<Map<String, List<String>>> _resolveDisplayObjectives(Map<String, dynamic> subjectData) async {
    final fromSubject = _extractPeriodObjectives(subjectData);
    final hasRealSubjectData = fromSubject.values.any(
      (list) => list.any((text) => text.trim().isNotEmpty),
    );

    if (hasRealSubjectData && !_isGeneric(fromSubject)) {
      return fromSubject;
    }

    try {
      final subjectKey = _subjectKeyFromData(subjectData);
      final baseSnap = await _baseCompetenciasRef(subjectKey).get();
      if (!baseSnap.exists) return fromSubject;

      final baseData = baseSnap.data() ?? <String, dynamic>{};
      final fromBase = _extractPeriodObjectives(baseData);
      final hasBaseData = fromBase.values.any(
        (list) => list.any((text) => text.trim().isNotEmpty),
      );
      return hasBaseData ? fromBase : fromSubject;
    } catch (_) {
      return fromSubject;
    }
  }

  void _syncControllers(Map<String, List<String>> data) {
    for (final pk in _periodKeys) {
      final values = data[pk] ?? List.filled(4, '');
      final ctrls = _poCtrls[pk]!;
      for (int i = 0; i < 4; i++) {
        ctrls[i].text = i < values.length ? values[i].trim() : '';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.subjectName.isEmpty ? 'Competencias' : widget.subjectName;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: _competenciasBlue,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _subjectRef().snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Error cargando competencias'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data() ?? <String, dynamic>{};
          return FutureBuilder<Map<String, List<String>>>(
            future: _resolveDisplayObjectives(data),
            builder: (context, resolvedSnap) {
              if (!resolvedSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              _syncControllers(resolvedSnap.data!);

              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: const Text(
                      'La administracion escolar solo puede consultar estos textos. La edicion queda centralizada.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (int pi = 0; pi < 4; pi++) ...[
                    _periodCard(periodIndex: pi),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _periodCard({required int periodIndex}) {
    final pk = _periodKeys[periodIndex];
    final ctrls = _poCtrls[pk]!;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Periodo ${periodIndex + 1} (P${periodIndex + 1})',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 10),
          for (int ci = 0; ci < 4; ci++) ...[
            TextField(
              controller: ctrls[ci],
              readOnly: true,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Competencia ${ci + 1}',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
