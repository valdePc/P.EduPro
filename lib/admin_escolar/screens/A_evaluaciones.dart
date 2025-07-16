// lib/admin_escolar/screens/A_evaluaciones.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class AEvaluaciones extends StatelessWidget {
  final Escuela escuela;
  const AEvaluaciones({Key? key, required this.escuela}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Evaluaciones — ${escuela.nombre}'),
        backgroundColor: Colors.blue.shade900,
      ),
      body: Center(
        child: Text(
          'Aquí programas y registras evaluaciones de ${escuela.nombre}',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}

