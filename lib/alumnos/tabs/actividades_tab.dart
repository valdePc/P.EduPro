import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ActividadesTab extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> estRef;
  const ActividadesTab({super.key, required this.estRef});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Actividades (Inicial)\nAquí van actividades, logros y desarrollo.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey.shade700),
      ),
    );
  }
}
