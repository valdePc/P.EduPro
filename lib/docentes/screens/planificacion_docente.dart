import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class PlanificacionDocenteScreen extends StatelessWidget {
  final Escuela escuela;

  const PlanificacionDocenteScreen({
    Key? key,
    required this.escuela,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planificación docente'),
        centerTitle: true,
      ),
      body: Center(
        child: Text(
          'Aquí irá la planificación docente de ${escuela.nombre ?? ''}',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
