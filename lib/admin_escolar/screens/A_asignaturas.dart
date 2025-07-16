// lib/admin_escolar/screens/A_asignaturas.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class AAsignaturas extends StatelessWidget {
  final Escuela escuela;
  const AAsignaturas({Key? key, required this.escuela}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Asignaturas — ${escuela.nombre}'),
        backgroundColor: Colors.blue.shade900,
      ),
      body: Center(
        child: Text(
          'Aquí administras asignaturas de ${escuela.nombre}',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
