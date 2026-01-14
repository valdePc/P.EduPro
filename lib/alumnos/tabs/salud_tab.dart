import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SaludTab extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;
  const SaludTab({super.key, required this.estRef});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Salud (en construcción)'),
    );
  }
}
