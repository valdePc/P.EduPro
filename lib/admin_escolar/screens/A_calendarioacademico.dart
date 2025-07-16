// lib/admin_escolar/screens/A_calendarioacademico.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class ACalendarioAcademico extends StatelessWidget {
  final Escuela escuela;
  const ACalendarioAcademico({Key? key, required this.escuela}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Calendario Académico — ${escuela.nombre}'),
        backgroundColor: Colors.blue.shade900,
      ),
      body: Center(
        child: Text(
          'Aquí administras el calendario académico de ${escuela.nombre}',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
