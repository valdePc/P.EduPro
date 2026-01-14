// lib/screens/freelancers.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../widgets/sidebar_menu.dart';
import 'package:edupro/models/freelancer.dart';

class FreelancersScreen extends StatefulWidget {
  const FreelancersScreen({Key? key}) : super(key: key);

  @override
  State<FreelancersScreen> createState() => _FreelancersScreenState();
}

class _FreelancersScreenState extends State<FreelancersScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String filtro = '';

  void _handleNavigation(BuildContext context, String route) {
    if (ModalRoute.of(context)?.settings.name != route) {
      Navigator.pushReplacementNamed(context, route);
    }
  }

  Future<void> _toggleActivo(String docId, bool value) async {
    await _db.collection('freelancers').doc(docId).update({
      'active': value,
      'updatedAt': Timestamp.now(),
    });
  }

  Future<void> _deleteFreelancer(String docId) async {
    await _db.collection('freelancers').doc(docId).delete();
  }

  Freelancer _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final ts = d['createdAt'];
    final fecha = ts is Timestamp ? ts.toDate() : DateTime.now();

    final f = Freelancer(
      nombre: (d['name'] ?? '').toString(),
      teacherLink: (d['teacherLink'] ?? '').toString(),
      studentLink: (d['studentLink'] ?? '').toString(),
      fecha: fecha,
      password: (d['password'] ?? '').toString(),
    );

    // Si tu modelo tiene activo como var
    try {
      f.activo = (d['active'] ?? true) == true;
    } catch (_) {}

    return f;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    const currentRoute = '/freelancers';

    // Si no hay sesión, tus rules van a bloquear
    if (_auth.currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('EduPro')),
        body: const Center(
          child: Text(
            'No hay sesión iniciada.\nInicia sesión con tu super admin.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
      drawer: isMobile
          ? Drawer(
              child: Container(
                color: Colors.blue.shade900,
                child: SidebarMenu(
                  currentRoute: currentRoute,
                  onItemSelected: (route) => _handleNavigation(context, route),
                ),
              ),
            )
          : null,
      appBar: isMobile
          ? AppBar(title: const Text('EduPro'))
          : PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Container(
                color: Colors.blue.shade900,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Text(
                  '...',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
      body: isMobile
          ? _buildBodyMobile(context)
          : Row(
              children: [
                Container(
                  width: 220,
                  color: Colors.blue.shade900,
                  child: SidebarMenu(
                    currentRoute: currentRoute,
                    onItemSelected: (route) => _handleNavigation(context, route),
                  ),
                ),
                Expanded(child: _buildBodyDesktop(context)),
              ],
            ),
    );
  }

  // ------------------ MÓVIL ------------------

  Widget _buildBodyMobile(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('freelancers').snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;

        final items = docs
            .map((d) => MapEntry(d.id, _fromDoc(d)))
            .where((e) =>
                e.value.nombre.toLowerCase().contains(filtro.toLowerCase()))
            .toList()
          ..sort((a, b) => b.value.fecha.compareTo(a.value.fecha));

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar freelancer...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => filtro = v.trim()),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('No hay freelancers registrados'))
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final docId = items[i].key;
                          final f = items[i].value;

                          final codigo = f.teacherLink.isEmpty
                              ? docId.toUpperCase()
                              : f.teacherLink.split('/').last.toUpperCase();

                          final isActive = f.activo;

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              title: Text(
                                f.nombre,
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text('Código: $codigo'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Switch(
                                    value: isActive,
                                    onChanged: (v) => _toggleActivo(docId, v),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy),
                                    onPressed: () {
                                      Clipboard.setData(
                                          ClipboardData(text: f.teacherLink));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('Enlace maestro copiado')),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_forever,
                                        color: Colors.red),
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          title: const Text('Eliminar freelancer'),
                                          content: Text('¿Eliminar a ${f.nombre}?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, false),
                                              child: const Text('Cancelar'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, true),
                                              child: const Text('Eliminar'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await _deleteFreelancer(docId);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  '/freelancerDetalle',
                                  arguments: f,
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ------------------ DESKTOP ------------------

  Widget _buildBodyDesktop(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('freelancers').snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;

        final items = docs
            .map((d) => MapEntry(d.id, _fromDoc(d)))
            .where((e) =>
                e.value.nombre.toLowerCase().contains(filtro.toLowerCase()))
            .toList()
          ..sort((a, b) => b.value.fecha.compareTo(a.value.fecha));

        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Freelancers',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/panel');
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange),
                    child: const Text('Registrar freelancer'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Buscador
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar freelancer...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => filtro = v.trim()),
              ),
              const SizedBox(height: 16),

              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('No hay freelancers registrados'))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Nombre')),
                            DataColumn(label: Text('Código')),
                            DataColumn(label: Text('Estado')),
                            DataColumn(label: Text('Maestro')),
                            DataColumn(label: Text('Estudiante')),
                            DataColumn(label: Text('Acciones')),
                          ],
                          rows: items.map((entry) {
                            final docId = entry.key;
                            final f = entry.value;

                            final codigo = f.teacherLink.isEmpty
                                ? docId.toUpperCase()
                                : f.teacherLink.split('/').last.toUpperCase();

                            final estadoText = f.activo ? 'Activo' : 'Pausado';
                            final estadoColor =
                                f.activo ? Colors.green : Colors.red;

                            return DataRow(cells: [
                              DataCell(Text(f.nombre)),
                              DataCell(Text(codigo)),
                              DataCell(
                                Row(
                                  children: [
                                    Switch(
                                      value: f.activo,
                                      onChanged: (v) => _toggleActivo(docId, v),
                                    ),
                                    Text(
                                      estadoText,
                                      style: TextStyle(
                                          color: estadoColor,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              DataCell(IconButton(
                                icon: const Icon(Icons.copy, size: 18),
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: f.teacherLink));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Enlace maestro copiado')),
                                  );
                                },
                              )),
                              DataCell(IconButton(
                                icon: const Icon(Icons.copy, size: 18),
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: f.studentLink));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Enlace estudiante copiado')),
                                  );
                                },
                              )),
                              DataCell(Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_red_eye,
                                        size: 18),
                                    onPressed: () => Navigator.pushNamed(
                                      context,
                                      '/freelancerDetalle',
                                      arguments: f,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete_forever,
                                        color: Colors.red, size: 18),
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          title: const Text('Eliminar freelancer'),
                                          content: Text('¿Eliminar a ${f.nombre}?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, false),
                                              child: const Text('Cancelar'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, true),
                                              child: const Text('Eliminar'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await _deleteFreelancer(docId);
                                      }
                                    },
                                  ),
                                ],
                              )),
                            ]);
                          }).toList(),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
