import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class MensajesAlumnoScreen extends StatelessWidget {
  final Escuela escuela;
  final String estudianteId;

  const MensajesAlumnoScreen({
    super.key,
    required this.escuela,
    required this.estudianteId,
  });

  @override
  Widget build(BuildContext context) {
    final schoolId = normalizeSchoolIdFromEscuela(escuela);
    final db = FirebaseFirestore.instance;

    final stream = db
        .collection('escuelas')
        .doc(schoolId)
        .collection('estudiantes')
        .doc(estudianteId)
        .collection('mensajes')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Mensajes')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('No hay mensajes aún'));

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 18),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.message_outlined)),
                title: Text((d['titulo'] ?? 'Mensaje').toString()),
                subtitle: Text(
                  (d['texto'] ?? '').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
