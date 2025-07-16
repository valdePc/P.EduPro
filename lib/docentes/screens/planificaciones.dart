import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class PlanificacionesScreen extends StatelessWidget {
  final Escuela escuela;
  const PlanificacionesScreen({Key? key, required this.escuela}) : super(key: key);

  static const Color primaryColor = Color.fromARGB(255, 13, 71, 161);
 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planificaciones'),
        backgroundColor: primaryColor,
        automaticallyImplyLeading: true,
      ),
      body: Center(
        child: Text(
          'Planificaciones de ${escuela.nombre}',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
