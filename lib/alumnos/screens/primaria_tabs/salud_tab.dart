import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class SaludTab extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;
  const SaludTab({super.key, required this.estRef});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Salud (próximo)\nAlergias, condiciones, medicación, observaciones.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade700),
      ),
    );
  }
}
