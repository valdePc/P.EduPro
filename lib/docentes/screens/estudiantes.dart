// lib/docentes/screens/estudiantes.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

/// ✅ OJO: Este archivo NO debe tener una clase llamada "DocentesScreen".
/// Solo "DocenteEstudiantesScreen" para evitar el choque de nombres.
class DocenteEstudiantesScreen extends StatelessWidget {
  final Escuela escuela;

  /// Opcionales (los que tú estás pasando desde paneldedocentes.dart)
  final String? schoolIdOverride;
  final String? gradeKeyOverride;
  final String? gradeLabelOverride;

  const DocenteEstudiantesScreen({
    super.key,
    required this.escuela,
    this.schoolIdOverride,
    this.gradeKeyOverride,
    this.gradeLabelOverride,
  });

  @override
  Widget build(BuildContext context) {
    final gradeLabel = (gradeLabelOverride ?? '').trim();
    final gradeKey = (gradeKeyOverride ?? '').trim();
    final schoolId = (schoolIdOverride ?? '').trim();

    // ✅ Construimos los posibles valores de grado para filtrar.
    // (Usamos whereIn sobre el campo "grado" para cubrir si guardas key o label ahí).
    final gradoCandidates = <String>{
      if (gradeKey.isNotEmpty) gradeKey,
      if (gradeLabel.isNotEmpty) gradeLabel,
    }.toList();

    if (schoolId.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Atras', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: const Center(
          child: Text(
            'Falta schoolId para cargar alumnos.\n(Pásalo desde paneldedocentes.dart)',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final alumnosRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('alumnos');

    Query<Map<String, dynamic>> query = alumnosRef;

    // ✅ Filtra por grado (si tenemos candidates).
    // Nota: Firestore exige que el campo exista como "grado" para que este filtro funcione.
    if (gradoCandidates.isNotEmpty && gradoCandidates.length <= 10) {
      query = query.where('grado', whereIn: gradoCandidates);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Atras', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _InfoCard(
              nombreEscuela: '', // NO se mostrará
              schoolId: schoolId,
              gradeKey: gradeKey.isEmpty ? '--' : gradeKey,
              gradeLabel: gradeLabel.isEmpty ? '--' : gradeLabel,
            ),
            const SizedBox(height: 12),

            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: query.snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Text(
                        'Error cargando alumnos:\n${snap.error}',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snap.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        gradoCandidates.isEmpty
                            ? 'No hay alumnos registrados en este colegio.'
                            : 'No encontré alumnos para este grado.\n\n'
                                'Estoy filtrando por el campo "grado" con:\n'
                                '${gradoCandidates.join(" / ")}\n\n'
                                'Si en tu Firestore el campo se llama distinto (ej: "gradoKey"), '
                                'dime el nombre exacto y lo ajusto.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  // ✅ Mapeo robusto (por si tus campos varían un poco)
                  // - nombre: nombres + apellidos, o "nombre"
                  // - matrícula: "matricula", o fallback doc.id
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
                          (d['matricula'] ?? d['matrícula'] ?? d['codigo'] ?? docs[i].id)
                              .toString()
                              .trim();

                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(nombreCompleto),
                          subtitle: Text('Matrícula: $matricula'),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  // ✅ NO los quitamos (para evitar el error del Hot Reload),
  // solo dejamos de mostrarlos.
  final String nombreEscuela;
  final String schoolId;
  final String gradeKey;
  final String gradeLabel;

  const _InfoCard({
    required this.nombreEscuela,
    required this.schoolId,
    required this.gradeKey,
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
          const Text(
            'Grado: ',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
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
