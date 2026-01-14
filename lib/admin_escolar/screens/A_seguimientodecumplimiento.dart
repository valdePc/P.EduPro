import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class ASeguimientoDeCumplimiento extends StatelessWidget {
  final Escuela escuela;
  const ASeguimientoDeCumplimiento({Key? key, required this.escuela}) : super(key: key);

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
          'Aquí haces seguimiento de cumplimiento de ${escuela.nombre}',
          style: const TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
