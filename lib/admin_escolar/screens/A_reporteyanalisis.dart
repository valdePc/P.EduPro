// lib/admin_escolar/screens/A_reporteyanalisis.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class AReporteYAnalisis extends StatelessWidget {
  final Escuela escuela;
  const AReporteYAnalisis({Key? key, required this.escuela}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Reporte y Análisis — ${escuela.nombre}'),
        backgroundColor: Colors.blue.shade900,
      ),
      body: Center(
        child: Text(
          'Aquí ves reportes y análisis para ${escuela.nombre}',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
