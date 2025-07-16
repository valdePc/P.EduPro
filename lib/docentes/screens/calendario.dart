import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class CalendarioScreen extends StatelessWidget {
  final Escuela escuela;
  const CalendarioScreen({Key? key, required this.escuela}) : super(key: key);

  static const Color primaryColor = Color(0xFF1A5276);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendario'),
        backgroundColor: primaryColor,
        automaticallyImplyLeading: true,
      ),
      body: Center(
        child: Text(
          'Calendario de ${escuela.nombre}',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
