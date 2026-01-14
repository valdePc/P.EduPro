import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class TutoresTab extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;
  const TutoresTab({super.key, required this.estRef});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Tutores (próximo)\nAquí van madre/padre/tutor y autorizados a retirar.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade700),
      ),
    );
  }
}
