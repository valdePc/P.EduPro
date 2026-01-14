// lib/screens/freelancer_detail.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:edupro/models/freelancer.dart';

class FreelancerDetailScreen extends StatefulWidget {
  const FreelancerDetailScreen({Key? key}) : super(key: key);

  @override
  State<FreelancerDetailScreen> createState() => _FreelancerDetailScreenState();
}

class _FreelancerDetailScreenState extends State<FreelancerDetailScreen> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    final Freelancer f = ModalRoute.of(context)!.settings.arguments as Freelancer;

    return Scaffold(
      appBar: AppBar(title: Text('Freelancer: ${f.nombre}')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row( // encabezado
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(f.nombre, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Text('${f.fecha.day}/${f.fecha.month}/${f.fecha.year}', style: const TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 16),

            // Enlaces
            ListTile(
              title: const Text('Enlace Maestro'),
              subtitle: Text(f.teacherLink, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: f.teacherLink));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enlace maestro copiado')));
                },
              ),
            ),
            ListTile(
              title: const Text('Enlace Estudiante'),
              subtitle: Text(f.studentLink, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: f.studentLink));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enlace estudiante copiado')));
                },
              ),
            ),

            // Contraseña
            ListTile(
              title: const Text('Contraseña'),
              subtitle: Text(_showPassword ? f.password : '••••••••', style: const TextStyle(fontFamily: 'monospace')),
              trailing: IconButton(
                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),

            const SizedBox(height: 8),

            // Acciones
            Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.edit),
                  label: const Text('Editar'),
                  onPressed: () {
                    Navigator.pushNamed(context, '/editarFreelancer', arguments: f);
                  },
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.delete_forever),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  label: const Text('Eliminar'),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Confirmar eliminación'),
                        content: Text('¿Eliminar a ${f.nombre}?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      // Aquí: remove from repository y pop con mensaje
                      // FreelancerRepository.freelancers.remove(f);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Freelancer eliminado')));
                    }
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Placeholder para lista de estudiantes o métricas
            Expanded(
              child: Center(child: Text('Aquí puedes mostrar la lista de estudiantes, métricas, historial, etc.')),
            ),
          ],
        ),
      ),
    );
  }
}
