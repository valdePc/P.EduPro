import 'package:flutter/material.dart';
import 'package:edupro/alumnos/perfiles/widgets/alumno_ui.dart';

class ResumenSecundariaTab extends StatelessWidget {
  final String nombreAlumno;
  final String grado;
  const ResumenSecundariaTab({super.key, required this.nombreAlumno, required this.grado});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AlumnoCard(
          title: 'Resumen',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Alumno: $nombreAlumno'),
              Text('Grado: $grado'),
              const SizedBox(height: 8),
              const Text('Aquí irá: índice, promedio, conducta, créditos, etc.'),
            ],
          ),
        ),
      ],
    );
  }
}
