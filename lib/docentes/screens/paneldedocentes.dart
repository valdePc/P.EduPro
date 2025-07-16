// lib/docentes/screens/paneldedocentes.dart

import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class PaneldedocentesScreen extends StatefulWidget {
  final Escuela escuela;
  const PaneldedocentesScreen({Key? key, required this.escuela}) : super(key: key);

  @override
  _PaneldedocentesScreenState createState() => _PaneldedocentesScreenState();
}

class _PaneldedocentesScreenState extends State<PaneldedocentesScreen> {
  static const Color primaryColor   = Color.fromARGB(255, 255, 193, 7);
  static const Color secondaryColor = Color.fromARGB(255, 21, 101, 192);

  bool _isEditing = false;
  String _docenteName = '';
  String _asignatura  = '';

  final TextEditingController _nameController    = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  String _toTitleCase(String text) {
    return text.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  void _saveInfo() {
    setState(() {
      _docenteName = _toTitleCase(_nameController.text.trim());
      _asignatura  = _toTitleCase(_subjectController.text.trim());
      _isEditing   = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Información guardada')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Eduprsso', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Color.fromARGB(255, 21, 101, 192),
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
                                labelStyle: TextStyle(color: primaryColor),
                                border: OutlineInputBorder(
                                  borderSide: BorderSide(color: primaryColor),
                                ),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _subjectController,
                              decoration: InputDecoration(
                                labelText: 'Asignatura',
                                labelStyle: TextStyle(color: primaryColor),
                                border: OutlineInputBorder(
                                  borderSide: BorderSide(color: primaryColor),
                                ),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            onPressed: _saveInfo,
                            child: Text('Guardar'),
                          ),
                        ],
                      ),

                    // ─── VIEW MODE ───
                    if (!_isEditing)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Docente: ${_docenteName.isNotEmpty ? _docenteName : '--'}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Asignatura: ${_asignatura.isNotEmpty ? _asignatura : '--'}',
                                style: TextStyle(color: Colors.black87),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: Icon(Icons.edit, color: const Color.fromARGB(255, 21, 101, 192)),
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

                    SizedBox(height: 16),

                    // ─── BOTONES ───
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                shape: StadiumBorder(),
                              ),
                              onPressed: () => Navigator.pushNamed(
                                context,
                                '/evaluaciones',
                                arguments: widget.escuela,
                              ),
                              child: Text('Evaluaciones'),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: secondaryColor),
                                shape: StadiumBorder(),
                                foregroundColor: secondaryColor,
                              ),
                              onPressed: () => Navigator.pushNamed(
                                context,
                                '/calendario',
                                arguments: widget.escuela,
                              ),
                              child: Text('Mi Calendario'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 24),

            // ───────────── GRID RESPONSIVO ─────────────
            Expanded(
              child: LayoutBuilder(builder: (context, constraints) {
                final width         = constraints.maxWidth;
                final crossAxisCount = width < 600 ? 2 : 4;
                final childAspect    = (width / crossAxisCount) / 180;

                return GridView.count(
                  physics: NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: childAspect,
                  children: [
                    _menuItem(context, Icons.insert_drive_file, 'Planificaciones', '/planificaciones'),
                    _menuItem(context, Icons.calendar_today,    'Períodos y Boletín', '/periodos'),
                    _menuItem(context, Icons.lightbulb,         'Estrategias', '/estrategias'),
                    _menuItem(context, Icons.book,              'Currículo', '/curriculo'),
                    _menuItem(context, Icons.group,             'Estudiantes', '/estudiantes'),
                    _menuItem(context, Icons.chat_bubble,       'Chat', '/chat'),
                    _menuItem(context, Icons.edit,              'Planificación\nDocente', '/planificacionDocente'),
                    _menuItem(context, Icons.check_box,         'Colocar\nCalificaciones', '/colocarCalificaciones'),
                  ],
                );
              }),
            ),

          ],
        ),
      ),
    );
  }

  Widget _menuItem(BuildContext context, IconData icon, String label, String route) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.pushNamed(context, route, arguments: widget.escuela),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: secondaryColor.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(12),
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
