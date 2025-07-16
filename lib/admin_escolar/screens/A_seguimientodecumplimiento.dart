// lib/admin_escolar/screens/A_seguimientodecumplimiento.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class ASeguimientoDeCumplimiento extends StatelessWidget {
  final Escuela escuela;
  const ASeguimientoDeCumplimiento({Key? key, required this.escuela}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Seguimiento de Cumplimiento — ${escuela.nombre}'),
        backgroundColor: Colors.blue.shade900,
      ),
      body: Center(
        child: Text(
          'Aquí haces seguimiento de cumplimiento de ${escuela.nombre}',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
