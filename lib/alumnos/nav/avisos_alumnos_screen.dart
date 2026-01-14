import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class AvisosAlumnoScreen extends StatelessWidget {
  final Escuela escuela;
  const AvisosAlumnoScreen({super.key, required this.escuela});

  @override
  Widget build(BuildContext context) {
    final schoolId = normalizeSchoolIdFromEscuela(escuela);
    final db = FirebaseFirestore.instance;

    final stream = db
        .collection('escuelas')
        .doc(schoolId)
        .collection('avisos')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Avisos / Circulares'),
        backgroundColor: const Color.fromARGB(255, 21, 101, 192),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('No hay avisos'));

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (d['titulo'] ?? 'Aviso').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text((d['mensaje'] ?? '').toString()),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
