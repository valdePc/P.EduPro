import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class CurriculoScreen extends StatelessWidget {
  final Escuela escuela;
  const CurriculoScreen({Key? key, required this.escuela}) : super(key: key);

  static const Color primaryColor = Color(0xFF1A5276);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Currículo'),
        backgroundColor: primaryColor,
        automaticallyImplyLeading: true,
      ),
      body: Center(
        child: Text(
          'Currículo académico de ${escuela.nombre}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
