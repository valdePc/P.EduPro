// lib/docentes/screens/paneldedocentes.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

// ✅ IMPORTA TU ENUM REAL DEL CALENDARIO
import 'package:edupro/calendario/models/user_role.dart';

// ✅ CALENDARIO
import 'package:edupro/calendario/ui/calendario_screen.dart';

// ✅ CHAT NUEVO (docentes)
import 'D_chat_docente_screen.dart';

class PaneldedocentesScreen extends StatefulWidget {
  final Escuela escuela;
  const PaneldedocentesScreen({Key? key, required this.escuela}) : super(key: key);

  @override
  State<PaneldedocentesScreen> createState() => _PaneldedocentesScreenState();
}

class _PaneldedocentesScreenState extends State<PaneldedocentesScreen> {
  static const Color primaryColor = Color.fromARGB(255, 255, 193, 7);
  static const Color secondaryColor = Color.fromARGB(255, 21, 101, 192);

  bool _isEditing = false;
  String _docenteName = '';
  String _asignatura = '';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  String _toTitleCase(String text) {
    final cleaned = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return '';
    return cleaned.split(' ').map((word) {
      if (word.isEmpty) return '';
      final w = word.toLowerCase();
      return w[0].toUpperCase() + w.substring(1);
    }).join(' ');
  }

  void _saveInfo() {
    setState(() {
      _docenteName = _toTitleCase(_nameController.text);
      _asignatura = _toTitleCase(_subjectController.text);
      _isEditing = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Información guardada')),
    );
  }

  void _openChatDocente() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DChatDocenteScreen(
          escuela: widget.escuela,
          docenteNombre: _docenteName.isNotEmpty ? _docenteName : null,
        ),
      ),
    );
  }

  void _openCalendarioDocente() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay sesión activa. Inicia sesión nuevamente.')),
      );
      return;
    }

    final schoolId = normalizeSchoolIdFromEscuela(widget.escuela);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CalendarioScreen(
          schoolId: schoolId,
          role: UserRole.teacher,
          userUid: user.uid,
          userGroups: const [], // ✅ luego lo conectamos a grupos reales del docente
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombreEscuela = (widget.escuela.nombre ?? 'EduPro').trim();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(nombreEscuela, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: secondaryColor,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ───────────── TARJETA DE INFO ─────────────
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ─── EDIT MODE ───
                    if (_isEditing)
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: 'Nombre',
                                labelStyle: const TextStyle(color: primaryColor),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _subjectController,
                              decoration: InputDecoration(
                                labelText: 'Asignatura',
                                labelStyle: const TextStyle(color: primaryColor),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            onPressed: _saveInfo,
                            child: const Text('Guardar'),
                          ),
                        ],
                      ),

                    // ─── VIEW MODE ───
                    if (!_isEditing)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Docente: ${_docenteName.isNotEmpty ? _docenteName : '--'}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Asignatura: ${_asignatura.isNotEmpty ? _asignatura : '--'}',
                                  style: const TextStyle(color: Colors.black87),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: secondaryColor),
                            onPressed: () {
                              setState(() {
                                _isEditing = true;
                                _nameController.text = _docenteName;
                                _subjectController.text = _asignatura;
                              });
                            },
                          ),
                        ],
                      ),

                    const SizedBox(height: 16),

                    // ─── BOTONES ───
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                shape: const StadiumBorder(),
                              ),
                              onPressed: () => Navigator.pushNamed(
                                context,
                                '/evaluaciones',
                                arguments: widget.escuela,
                              ),
                              child: const Text('Evaluaciones'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: secondaryColor),
                                shape: const StadiumBorder(),
                                foregroundColor: secondaryColor,
                              ),
                              onPressed: _openCalendarioDocente,
                              child: const Text('Mi Calendario'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ───────────── GRID RESPONSIVO ─────────────
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final crossAxisCount = width < 600 ? 2 : 4;
                  final childAspect = (width / crossAxisCount) / 180;

                  return GridView.count(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: childAspect,
                    children: [
                      _menuItem(
                        context,
                        Icons.insert_drive_file,
                        'Planificaciones',
                        onTap: () => Navigator.pushNamed(context, '/planificaciones', arguments: widget.escuela),
                      ),
                      _menuItem(
                        context,
                        Icons.calendar_today,
                        'Períodos y Boletín',
                        onTap: () => Navigator.pushNamed(context, '/periodos', arguments: widget.escuela),
                      ),
                      _menuItem(
                        context,
                        Icons.lightbulb,
                        'Estrategias',
                        onTap: () => Navigator.pushNamed(context, '/estrategias', arguments: widget.escuela),
                      ),
                      _menuItem(
                        context,
                        Icons.book,
                        'Currículo',
                        onTap: () => Navigator.pushNamed(context, '/curriculo', arguments: widget.escuela),
                      ),
                      _menuItem(
                        context,
                        Icons.group,
                        'Estudiantes',
                        onTap: () => Navigator.pushNamed(context, '/estudiantes', arguments: widget.escuela),
                      ),

                      // ✅ CHAT NUEVO (sin rutas /chat)
                      _menuItem(
                        context,
                        Icons.chat_bubble,
                        'Chat',
                        onTap: _openChatDocente,
                      ),

                      _menuItem(
                        context,
                        Icons.edit,
                        'Planificación\nDocente',
                        onTap: () => Navigator.pushNamed(context, '/planificacionDocente', arguments: widget.escuela),
                      ),
                      _menuItem(
                        context,
                        Icons.check_box,
                        'Colocar\nCalificaciones',
                        onTap: () => Navigator.pushNamed(context, '/colocarCalificaciones', arguments: widget.escuela),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(BuildContext context, IconData icon, String label, {required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: secondaryColor.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: primaryColor),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
