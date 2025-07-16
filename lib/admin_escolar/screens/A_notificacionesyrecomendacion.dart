// lib/admin_escolar/screens/A_notificacionesyrecomendacion.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class ANotificacionesYRecomendacion extends StatelessWidget {
  final Escuela escuela;
  const ANotificacionesYRecomendacion({Key? key, required this.escuela}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Notificaciones y Recomendación — ${escuela.nombre}'),
        backgroundColor: Colors.blue.shade900,
      ),
      body: Center(
        child: Text(
          'Aquí envías notificaciones y recomendaciones para ${escuela.nombre}',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
