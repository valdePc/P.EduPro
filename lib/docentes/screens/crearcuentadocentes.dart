import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class CrearCuentaDocentesScreen extends StatelessWidget {
  final Escuela escuela;
  const CrearCuentaDocentesScreen({Key? key, required this.escuela}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear cuenta de docente'),
        backgroundColor: Colors.blue.shade900,
      ),
      body: Center(
        child: Text(
          '¡Bienvenido, docente!',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}