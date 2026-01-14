import 'package:flutter/material.dart';

class PrimariaResumenTab extends StatelessWidget {
  final String nombre;
  final String grado;

  const PrimariaResumenTab({
    super.key,
    required this.nombre,
    required this.grado,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeaderCard(nombre: nombre, grado: grado),
        const SizedBox(height: 12),
        _Card(
          title: 'Identidad',
          subtitle: 'Aquí pondremos: matrícula, sección, tanda, edad, foto, etc.',
        ),
        const SizedBox(height: 12),
        Row(
          children: const [
            Expanded(child: _MiniCard(title: 'Tareas', value: '0')),
            SizedBox(width: 10),
            Expanded(child: _MiniCard(title: 'Ausencias', value: '0')),
          ],
        ),
        const SizedBox(height: 10),
        const _Card(
          title: 'Observaciones',
          subtitle: 'Comentarios del docente / logros / conducta (luego).',
        ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String nombre;
  final String grado;
  const _HeaderCard({required this.nombre, required this.grado});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(colors: [Colors.blue.shade900, Colors.blue.shade600]),
      ),
      child: Row(
        children: [
          const CircleAvatar(radius: 26, child: Icon(Icons.school)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 4),
              Text(grado, style: const TextStyle(color: Colors.white70)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String subtitle;
  const _Card({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
      ]),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final String title;
  final String value;
  const _MiniCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
      ]),
    );
  }
}
