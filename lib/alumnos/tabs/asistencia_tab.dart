import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AsistenciaTab extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;
  const AsistenciaTab({super.key, required this.estRef});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Asistencia (próximo)\nAquí irá presente/ausente/tarde + justificaciones.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade700),
      ),
    );
  }
}
