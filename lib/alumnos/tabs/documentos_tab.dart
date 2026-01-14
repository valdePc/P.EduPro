import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DocumentosTab extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;
  const DocumentosTab({super.key, required this.estRef});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Documentos (en construcción)'),
    );
  }
}
