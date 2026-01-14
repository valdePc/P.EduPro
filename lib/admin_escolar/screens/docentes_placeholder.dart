// lib/docentes/screens/docentes_placeholder.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class DocentesPlaceholder extends StatelessWidget {
  final Escuela? escuela;
  const DocentesPlaceholder({Key? key, this.escuela}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // ignore: avoid_print
    print('BUILD: DocentesPlaceholder for ${escuela?.nombre ?? 'sin-escuela'}');
    return Scaffold(
      appBar: AppBar(title: const Text('Docentes (placeholder)')),
      body: const Center(
        child: Text(
          'Bienvenido al área de Docentes\n(placeholder)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}
