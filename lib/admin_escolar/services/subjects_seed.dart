import 'package:cloud_firestore/cloud_firestore.dart';

class SubjectsSeed {
  SubjectsSeed._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _subjectsCol = 'subjects';
  static const String _baseCompetenciasCol = 'competencias_base';

  static const List<Map<String, String>> _defaultSubjects = [
    {'key': 'lengua_espanola', 'name': 'LENGUA ESPAÑOLA'},
    {'key': 'ingles', 'name': 'INGLÉS'},
    {'key': 'frances', 'name': 'FRANCÉS'},
    {'key': 'matematica', 'name': 'MATEMÁTICA'},
    {'key': 'ciencias_sociales', 'name': 'CIENCIAS SOCIALES'},
    {'key': 'ciencias_naturaleza', 'name': 'CIENCIAS DE LA NATURALEZA'},
    {'key': 'educacion_artistica', 'name': 'EDUCACIÓN ARTÍSTICA'},
    {'key': 'educacion_fisica', 'name': 'EDUCACIÓN FÍSICA'},
    {
      'key': 'formacion_integral_humana_religiosa',
      'name': 'FORMACIÓN INTEGRAL HUMANA Y RELIGIOSA'
    },
  ];

  static List<String> _normalizeCompetenciasNode(dynamic raw) {
    if (raw is List) {
      final values = raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return List<String>.generate(4, (i) => i < values.length ? values[i] : '');
    }

    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return List<String>.filled(4, '');

      final parts = text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      if (parts.isEmpty) return List<String>.filled(4, '');
      return List<String>.generate(4, (i) => i < parts.length ? parts[i] : '');
    }

    if (raw is Map) {
      final map = raw.cast<String, dynamic>();
      String read(String key) => (map[key] ?? '').toString().trim();
      return <String>[
        read('c1').isNotEmpty ? read('c1') : read('1'),
        read('c2').isNotEmpty ? read('c2') : read('2'),
        read('c3').isNotEmpty ? read('c3') : read('3'),
        read('c4').isNotEmpty ? read('c4') : read('4'),
      ];
    }

    return List<String>.filled(4, '');
  }

  static Map<String, dynamic> _defaultPeriodObjectives() {
    return <String, dynamic>{
      'p1': <String>['Competencia 1', 'Competencia 2', 'Competencia 3', 'Competencia 4'],
      'p2': <String>['Competencia 1', 'Competencia 2', 'Competencia 3', 'Competencia 4'],
      'p3': <String>['Competencia 1', 'Competencia 2', 'Competencia 3', 'Competencia 4'],
      'p4': <String>['Competencia 1', 'Competencia 2', 'Competencia 3', 'Competencia 4'],
    };
  }

  static Future<Map<String, dynamic>?> _readBasePeriodObjectives(String subjectKey) async {
    try {
      final snap = await _db.collection(_baseCompetenciasCol).doc(subjectKey).get();
      if (!snap.exists) return null;

      final data = snap.data() ?? <String, dynamic>{};
      final po = data['periodObjectives'];

      if (po is Map) {
        final map = po.cast<String, dynamic>();
        return <String, dynamic>{
          'p1': _normalizeCompetenciasNode(map['p1']),
          'p2': _normalizeCompetenciasNode(map['p2']),
          'p3': _normalizeCompetenciasNode(map['p3']),
          'p4': _normalizeCompetenciasNode(map['p4']),
        };
      }

      // Compatibilidad con estructura plana: p1, p2, p3, p4
      final plain = <String, dynamic>{
        'p1': _normalizeCompetenciasNode(data['p1']),
        'p2': _normalizeCompetenciasNode(data['p2']),
        'p3': _normalizeCompetenciasNode(data['p3']),
        'p4': _normalizeCompetenciasNode(data['p4']),
      };

      final hasAnyValue = plain.values.any((v) => v is List && v.any((e) => e.toString().trim().isNotEmpty));
      return hasAnyValue ? plain : null;
    } catch (_) {
      return null;
    }
  }

  /// Crea o "parchea" las 9 asignaturas oficiales:
  /// - Si existen (def_*), agrega campos faltantes con merge.
  /// - Si no existen, las crea.
  static Future<void> ensureDefaultSubjects(String sid) async {
    sid = sid.trim();
    if (sid.isEmpty) return;

    final colRef = _db.collection('schools').doc(sid).collection(_subjectsCol);

    try {
      final batch = _db.batch();

      for (final s in _defaultSubjects) {
        final key = (s['key'] ?? '').trim();
        final name = (s['name'] ?? '').trim();
        if (key.isEmpty) continue;

        final docId = 'def_$key';
        final docRef = colRef.doc(docId);

        final docSnap = await docRef.get();
        final data = docSnap.data() as Map<String, dynamic>? ?? {};
        final basePeriodObjectives = await _readBasePeriodObjectives(key);

        final now = DateTime.now();
        final order = -now.millisecondsSinceEpoch;

        batch.set(
          docRef,
          <String, dynamic>{
            'name': (data['name'] ?? name).toString(),
            'nameLower': (data['nameLower'] ?? name.toLowerCase()).toString(),
            'order': (data['order'] is num) ? data['order'] : order,
            'subjectKey': key,
            'isDefault': true,
            'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),

            // ✅ NUEVO: competencias opcionales (def_* => true por defecto)
            'useCompetencies': (data['useCompetencies'] is bool)
                ? data['useCompetencies']
                : true,

            // ✅ NUEVO: lo que tu pantalla está pidiendo (periodObjectives.p1..p4)
            // Si ya existe, no se pisa.
            'periodObjectives': (data['periodObjectives'] is Map)
                ? data['periodObjectives']
                : (basePeriodObjectives ?? _defaultPeriodObjectives()),
          },
          SetOptions(merge: true),
        );
      }

      await batch.commit();
    } catch (e) {}
  }
}
