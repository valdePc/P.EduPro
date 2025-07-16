// lib/admin_escolar/screens/A_gestiondemaestros.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class AGestionDeMaestros extends StatelessWidget {
  final Escuela escuela;
  const AGestionDeMaestros({Key? key, required this.escuela}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Gestión de Maestros — ${escuela.nombre}'),
        backgroundColor: Colors.blue.shade900,
      ),
      body: Center(
        child: Text(
          'Aquí gestionas maestros para ${escuela.nombre}',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}