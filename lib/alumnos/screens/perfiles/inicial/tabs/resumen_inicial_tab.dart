import 'package:flutter/material.dart';
import 'package:edupro/alumnos/perfiles/widgets/alumno_ui.dart';

class ResumenInicialTab extends StatelessWidget {
  final String nombreAlumno;
  final String grado;
  const ResumenInicialTab({super.key, required this.nombreAlumno, required this.grado});

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
              const Text('Aquí pondremos progreso, conducta, logros, etc.'),
            ],
          ),
        ),
      ],
    );
  }
}
