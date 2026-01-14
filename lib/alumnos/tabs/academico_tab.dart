import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AcademicoTab extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;

  const AcademicoTab({
    super.key,
    required this.estRef,
  });

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Académico (en construcción)'),
    );
  }
}
