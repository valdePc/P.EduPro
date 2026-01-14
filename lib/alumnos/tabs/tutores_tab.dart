import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TutoresTab extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;
  const TutoresTab({super.key, required this.estRef});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Tutores (en construcción)'),
    );
  }
}
