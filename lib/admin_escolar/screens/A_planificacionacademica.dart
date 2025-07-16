// lib/admin_escolar/screens/A_planificacionacademica.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class APlanificacionAcademica extends StatelessWidget {
  final Escuela escuela;
  const APlanificacionAcademica({Key? key, required this.escuela}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Planificación Académica — ${escuela.nombre}'),
        backgroundColor: Colors.blue.shade900,
      ),
      body: Center(
        child: Text(
          'Aquí planificas el periodo académico de ${escuela.nombre}',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
