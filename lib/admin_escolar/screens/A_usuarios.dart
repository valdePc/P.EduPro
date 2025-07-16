// lib/admin_escolar/screens/A_usuarios.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class AUsuarios extends StatelessWidget {
  final Escuela escuela;
  const AUsuarios({Key? key, required this.escuela}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Usuarios — ${escuela.nombre}'),
        backgroundColor: Colors.blue.shade900,
      ),
      body: Center(
        child: Text(
          'Aquí gestionas usuarios de ${escuela.nombre}',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
