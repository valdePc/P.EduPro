import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class AReporteYAnalisis extends StatelessWidget {
  final Escuela escuela;
  const AReporteYAnalisis({Key? key, required this.escuela}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: const SizedBox.shrink(),
        leadingWidth: 0,
        title: const SizedBox.shrink(),
        backgroundColor: Colors.blue.shade900,
        elevation: 0,
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
