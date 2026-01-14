import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class NacionalesTab extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;
  const NacionalesTab({super.key, required this.estRef});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Pruebas Nacionales (próximo)\nResultados, simulacros, reportes.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade700),
      ),
    );
  }
}
