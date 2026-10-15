import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/docentes/widgets/docente_app_bar.dart';

class EstrategiasScreen extends StatelessWidget {
  final Escuela escuela;
  const EstrategiasScreen({Key? key, required this.escuela}) : super(key: key);

  static const Color primaryColor = Color(0xFF1A5276);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildDocenteBackAppBar(context),
      body: Center(
        child: Text(
          'Estrategias de ${escuela.nombre}',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
