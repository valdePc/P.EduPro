// lib/admin_escolar/screens/A_pagos.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class APagos extends StatelessWidget {
  final Escuela escuela;
  const APagos({Key? key, required this.escuela}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pagos — ${escuela.nombre}'),
        backgroundColor: Colors.blue.shade900,
      ),
      body: Center(
        child: Text(
          'Aquí ves detalles y facturas de ${escuela.nombre}',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
