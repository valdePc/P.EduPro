import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:edupro/docentes/widgets/docente_app_bar.dart';
import 'package:edupro/models/escuela.dart';

class DocenteEstudiantesScreen extends StatefulWidget {
  final Escuela escuela;
  final String? schoolIdOverride;
  final String? gradeKeyOverride;
  final String? gradeLabelOverride;
  final String? gradeIdOverride;
  final String? tandaOverride;

  const DocenteEstudiantesScreen({
    super.key,
    required this.escuela,
    this.schoolIdOverride,
    this.gradeKeyOverride,
    this.gradeLabelOverride,
    this.gradeIdOverride,
    this.tandaOverride,
  });

  @override
  State<DocenteEstudiantesScreen> createState() => _DocenteEstudiantesScreenState();
}

class _DocenteEstudiantesScreenState extends State<DocenteEstudiantesScreen> {
  String _selectedGradeId = '';
  String _selectedGradeLabel = '';
  String _selectedTanda = '';

  static const _defaultTandas = <String>['', 'Manana', 'Tarde', 'Noche'];

  String get _schoolId => (widget.schoolIdOverride ?? '').trim();

  CollectionReference<Map<String, dynamic>> get _alumnosRef =>
      FirebaseFirestore.instance.collection('schools').doc(_schoolId).collection('alumnos');

  CollectionReference<Map<String, dynamic>> get _gradosRef =>
      FirebaseFirestore.instance.collection('schools').doc(_schoolId).collection('grados');

  @override
  void initState() {
    super.initState();
    _selectedGradeId = (widget.gradeIdOverride ?? '').trim();
    _selectedGradeLabel = (widget.gradeLabelOverride ?? '').trim();
    _selectedTanda = _normTanda((widget.tandaOverride ?? '').trim());
  }

  @override
  Widget build(BuildContext context) {
    if (_schoolId.isEmpty) {
      return Scaffold(
        appBar: buildDocenteBackAppBar(context),
        body: const Center(
          child: Text(
            'Falta schoolId para cargar alumnos.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: buildDocenteBackAppBar(context),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _gradosRef.snapshots(),
              builder: (context, gSnap) {
                final grades = _extractGrades(gSnap.data?.docs ?? const []);
                if (_selectedGradeId.isEmpty && grades.isNotEmpty) {
                  _selectedGradeId = grades.first.id;
                  _selectedGradeLabel = grades.first.label;
                }
                if (_selectedGradeId.isNotEmpty && grades.isNotEmpty) {
                  final found = grades.where((e) => e.id == _selectedGradeId).toList();
                  if (found.isNotEmpty) _selectedGradeLabel = found.first.label;
                }

                return Column(
                  children: [
                    _InfoCard(
                      schoolId: _schoolId,
                      gradeLabel: _selectedGradeLabel.isEmpty ? '--' : _selectedGradeLabel,
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _selectedGradeId.isEmpty ? null : _selectedGradeId,
                                decoration: const InputDecoration(
                                  labelText: 'Grado',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: grades
                                    .map((g) => DropdownMenuItem(value: g.id, child: Text(g.label)))
                                    .toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  final found = grades.where((e) => e.id == v).toList();
                                  setState(() {
                                    _selectedGradeId = v;
                                    _selectedGradeLabel = found.isNotEmpty ? found.first.label : '';
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _selectedTanda.isEmpty ? '' : _selectedTanda,
                                decoration: const InputDecoration(
                                  labelText: 'Tanda',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: _defaultTandas
                                    .map((t) => DropdownMenuItem(
                                          value: t,
                                          child: Text(t.isEmpty ? 'Todas' : t),
                                        ))
                                    .toList(),
                                onChanged: (v) => setState(() => _selectedTanda = _normTanda(v ?? '')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _buildStudentsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentsList() {
    if (_selectedGradeId.isEmpty) {
      return const Center(child: Text('Selecciona un grado.'));
    }

    final q = _alumnosRef.where('gradeId', isEqualTo: _selectedGradeId);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text('Error cargando alumnos:\n${snap.error}', textAlign: TextAlign.center),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var docs = snap.data?.docs ?? const [];
        if (_selectedTanda.isNotEmpty) {
          docs = docs.where((d) {
            final t = _normTanda((d.data()['tanda'] ?? '').toString());
            return t == _selectedTanda;
          }).toList();
        }

        if (docs.isEmpty) {
          final extra = _selectedTanda.isNotEmpty ? '\nTanda: $_selectedTanda' : '';
          return Center(
            child: Text(
              'No encontre alumnos para:\ngradeId: $_selectedGradeId$extra',
              textAlign: TextAlign.center,
            ),
          );
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final nombres = (d['nombres'] ?? d['nombre'] ?? '').toString().trim();
            final apellidos = (d['apellidos'] ?? '').toString().trim();
            final nombreCompleto = ('$nombres $apellidos').trim().isEmpty
                ? 'Alumno sin nombre'
                : ('$nombres $apellidos').trim();
            final matricula =
                (d['matricula'] ?? d['matricula'] ?? d['codigo'] ?? docs[i].id).toString().trim();
            final tanda = (d['tanda'] ?? '').toString().trim();

            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(nombreCompleto),
                subtitle: Text(
                  tanda.isEmpty ? 'Matricula: $matricula' : 'Matricula: $matricula\nTanda: $tanda',
                ),
                isThreeLine: tanda.isNotEmpty,
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Abrir: $nombreCompleto')),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  List<_GradeOpt> _extractGrades(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final out = <_GradeOpt>[];
    for (final d in docs) {
      final m = d.data();
      final id = d.id.trim();
      final label = (m['name'] ?? m['nombre'] ?? m['label'] ?? m['grado'] ?? id).toString().trim();
      if (id.isEmpty) continue;
      out.add(_GradeOpt(id: id, label: label.isEmpty ? id : label));
    }
    out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return out;
  }

  String _normTanda(String t) {
    final x = t.trim().toLowerCase();
    if (x == 'mañana' || x == 'manana' || x == 'maÃ±ana' || x == 'maã±ana' || x == 'maÃ£Â±ana' || x == 'maã£â±ana') return 'Manana';
    if (x == 'tarde') return 'Tarde';
    if (x == 'noche') return 'Noche';
    return '';
  }
}

class _InfoCard extends StatelessWidget {
  final String schoolId;
  final String gradeLabel;

  const _InfoCard({
    required this.schoolId,
    required this.gradeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final border = Theme.of(context).dividerColor;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border.withOpacity(0.6)),
        color: surface,
      ),
      child: Row(
        children: [
          const Text('Grado: ', style: TextStyle(fontWeight: FontWeight.w900)),
          Expanded(
            child: Text(
              gradeLabel,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _GradeOpt {
  final String id;
  final String label;
  const _GradeOpt({required this.id, required this.label});
}
