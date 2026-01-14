import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class TareasTab extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;
  const TareasTab({super.key, required this.estRef});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Tareas (próximo)\nAquí irán pendientes/entregadas, detalles y adjuntos.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade700),
      ),
    );
  }
}
