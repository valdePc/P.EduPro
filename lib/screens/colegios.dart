import 'package:flutter/material.dart';
import '../widgets/sidebar_menu.dart' as sidebar;

class ColegiosScreen extends StatelessWidget {
  const ColegiosScreen({Key? key}) : super(key: key);

  void _handleNavigation(BuildContext context, String route) {
    const currentRoute = '/colegios';
    if (route != currentRoute) {
      Navigator.pushReplacementNamed(context, route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 800;
    const String currentRoute = '/colegios';

    return Scaffold(
      drawer: isMobile
          ? Drawer(
              child: Container(
                color: Colors.blue.shade900,
                child: sidebar.SidebarMenu(
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
          ? _buildBodyMobile()
          : Row(
              children: [
                Container(
                  width: 220,
                  color: Colors.blue.shade900,
                  child: sidebar.SidebarMenu(
                    currentRoute: currentRoute,
                    onItemSelected: (route) => _handleNavigation(context, route),
                  ),
                ),
                Expanded(child: _buildBodyDesktop()),
              ],
            ),
    );
  }

  /// Muestra tarjetas en la vista móvil.
  Widget _buildBodyMobile() {
    // Definimos el tipo dinámico para que acepte bool y string
    final List<Map<String, dynamic>> colegios = [
      {'nombre': 'Colegio San Juan', 'codigo': 'ABC123', 'usuarios': '350', 'pago': true},
      {'nombre': 'Instituto Moderno', 'codigo': 'XYZ456', 'usuarios': '420', 'pago': true},
      {'nombre': 'Escuela Manuel Rodriguez', 'codigo': 'LMN789', 'usuarios': '275', 'pago': true},
      {'nombre': 'Colegio Nuevo Amanecer', 'codigo': 'DEF012', 'usuarios': '310', 'pago': false},
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: colegios.length,
      itemBuilder: (ctx, i) {
        final colegio = colegios[i];
        final String nombre = colegio['nombre'] as String;
        final String codigo = colegio['codigo'] as String;
        final String usuarios = colegio['usuarios'] as String;
        final bool pago = colegio['pago'] as bool;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            title: Text(
              nombre,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            subtitle: Text('Código: $codigo • Usuarios: $usuarios'),
            trailing: Icon(
              pago ? Icons.check_circle : Icons.cancel,
              color: pago ? Colors.green : Colors.red,
            ),
            onTap: () {},
          ),
        );
      },
    );
  }

  /// Muestra tabla en la vista de escritorio.
  Widget _buildBodyDesktop() {
    final List<Map<String, dynamic>> colegios = [
      {'nombre': 'Colegio San Juan', 'codigo': 'ABC123', 'usuarios': '350', 'pago': true},
      {'nombre': 'Instituto Moderno', 'codigo': 'XYZ456', 'usuarios': '420', 'pago': true},
      {'nombre': 'Escuela Manuel Rodriguez', 'codigo': 'LMN789', 'usuarios': '275', 'pago': true},
      {'nombre': 'Colegio Nuevo Amanecer', 'codigo': 'DEF012', 'usuarios': '310', 'pago': false},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Colegios',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), 
                child: const Text('+ Nuevo Colegio'), 
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Nombre del colegio')),
                DataColumn(label: Text('Código')),
                DataColumn(label: Text('Usuarios')),
                DataColumn(label: Text('Pago')),
                DataColumn(label: Text('Acciones')),
              ],
              rows: colegios.map((colegio) {
                final String nombre = colegio['nombre'] as String;
                final String codigo = colegio['codigo'] as String;
                final String usuarios = colegio['usuarios'] as String;
                final bool pago = colegio['pago'] as bool;

                return DataRow(cells: [
                  DataCell(Text(nombre)),
                  DataCell(Text(codigo)),
                  DataCell(Text(usuarios)),
                  DataCell(Icon(
                    pago ? Icons.check : Icons.close,
                    color: pago ? Colors.green : Colors.red,
                  )),
                  DataCell(Row(
                    children: const [
                      Icon(Icons.remove_red_eye, size: 18),
                      SizedBox(width: 8),
                      Icon(Icons.edit, size: 18),
                      SizedBox(width: 8),
                      Icon(Icons.bookmark_border, size: 18),
                    ],
                  )),
                ]);
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}