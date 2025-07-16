// lib/docentes/screens/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';
import 'package:edupro/docentes/screens/chat_grupal_screen.dart';
import 'package:edupro/docentes/screens/chat_privado_screen.dart';

class ChatScreen extends StatefulWidget {
  final Escuela escuela;
  const ChatScreen({Key? key, required this.escuela}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  static const Color primaryColor = Color(0xFF1A5276);
  static const Color secondaryColor = Color(0xFF2874A6);

  late final TabController _tabController;
  String gradoSeleccionado = '1ro';
  final List<String> grados = ['1ro', '2do', '3ro', '4to', '5to', '6to'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Usa el nombre de la escuela para mostrar el docente o institución
    final String nombreDocente = widget.escuela.nombre;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        backgroundColor: primaryColor,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.group), text: 'Grupal'),
            Tab(icon: Icon(Icons.person), text: 'Individual'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Cabecera con nombre y selector de grado
          Container(
            color: secondaryColor.withOpacity(0.1),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Docente: $nombreDocente',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                DropdownButton<String>(
                  value: gradoSeleccionado,
                  items: grados.map((g) => DropdownMenuItem(
                        value: g,
                        child: Text('Grado $g'),
                      )).toList(),
                  onChanged: (v) => setState(() {
                    if (v != null) gradoSeleccionado = v;
                  }),
                ),
              ],
            ),
          ),

          // Pestañas de chat
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ChatGrupalScreen(grado: gradoSeleccionado),
                ChatPrivadoScreen(estudiante: 'Estudiante 1'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
