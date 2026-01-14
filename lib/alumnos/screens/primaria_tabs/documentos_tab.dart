import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class DocumentosTab extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;
  const DocumentosTab({super.key, required this.estRef});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Documentos (próximo)\nBoletines, permisos, constancias, etc.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade700),
      ),
    );
  }
}
