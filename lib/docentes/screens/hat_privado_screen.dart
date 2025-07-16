import 'package:flutter/material.dart';
import 'package:edupro/models/escuela.dart';

class ChatScreen extends StatefulWidget {
  final Escuela escuela;

  const ChatScreen({Key? key, required this.escuela}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  static const Color primaryColor = Color(0xFF1A5276);
  static const Color secondaryColor = Color(0xFF2874A6);

  late TabController _tabController;
  String gradoSeleccionado = '1ro';

  final List<String> grados = [
    '1ro', '2do', '3ro', '4to', '5to', '6to'
  ];

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
    String nombreDocente = 'Nombre del Docente'; // ← Este nombre vendrá del login en el futuro

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
          // Nombre del docente y dropdown de grado
          Container(
            color: secondaryColor.withOpacity(0.1),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Docente: $nombreDocente', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: gradoSeleccionado,
                  onChanged: (String? newValue) {
                    setState(() {
                      gradoSeleccionado = newValue!;
                    });
                  },
                  items: grados.map((String grado) {
                    return DropdownMenuItem<String>(
                      value: grado,
                      child: Text('Grado: $grado'),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // CHAT GRUPAL
                Center(
                  child: Text(
                    'Chat grupal con estudiantes de $gradoSeleccionado',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                // CHAT INDIVIDUAL
                ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: 5, // ← Temporal, simula 5 estudiantes
                  itemBuilder: (context, index) {
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text('Estudiante ${index + 1}'),
                        subtitle: Text('Mensaje reciente...'),
                        trailing: const Icon(Icons.chat),
                        onTap: () {
                          // Aquí puedes abrir ChatPrivadoScreen en el futuro
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // BOTÓN DE CONTACTO CON ADMINISTRACIÓN
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                // Aquí puedes implementar tu lógica para contactar al admin
              },
              icon: const Icon(Icons.admin_panel_settings),
              label: const Text('Contactar administración'),
            ),
          ),
        ],
      ),
    );
  }
}
