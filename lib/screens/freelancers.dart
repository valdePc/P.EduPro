import 'package:flutter/material.dart';
import '../widgets/sidebar_menu.dart';

class FreelancersScreen extends StatelessWidget {
  const FreelancersScreen({Key? key}) : super(key: key);

  void _handleNavigation(BuildContext context, String route) {
    if (ModalRoute.of(context)?.settings.name != route) {
      Navigator.pushReplacementNamed(context, route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    const currentRoute = '/freelancers';

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
          ? _buildBodyMobile()
          : Row(
              children: [
                Container(
                  width: 220,
                  color: Colors.blue.shade900,
                  child: SidebarMenu(
                    currentRoute: currentRoute,
                    onItemSelected: (route) =>
                        _handleNavigation(context, route),
                  ),
                ),
                // Tabla en escritorio
                Expanded(child: _buildBodyDesktop()),
              ],
            ),
    );
  }

  // Versión móvil: tarjetas
  Widget _buildBodyMobile() {
    final freelancers = [
      {'nombre': 'María Torres', 'codigo': 'F1234', 'estudiantes': '12', 'estado': 'Pagado'},
      {'nombre': 'Juan Méndez', 'codigo': 'F5612', 'estudiantes': '8',  'estado': 'Pendiente'},
      {'nombre': 'Rosa Martínez','codigo': 'F8844', 'estudiantes': '15', 'estado': 'Pagado'},
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: freelancers.length,
      itemBuilder: (context, i) {
        final f = freelancers[i];
        final isPaid = f['estado'] == 'Pagado';
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            title: Text(
              f['nombre']!,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            subtitle: Text('Código: ${f['codigo']}  •  Estudiantes: ${f['estudiantes']}'),
            trailing: Icon(
              isPaid ? Icons.check_circle : Icons.hourglass_empty,
              color: isPaid ? Colors.green : Colors.orange,
            ),
            onTap: () {
              // Acción al pulsar la tarjeta (opcional)
            },
          ),
        );
      },
    );
  }

  // Versión escritorio/web: tabla
  Widget _buildBodyDesktop() {
    final freelancers = [
      {'nombre': 'María Torres', 'codigo': 'F1234', 'estudiantes': '12', 'estado': 'Pagado'},
      {'nombre': 'Juan Méndez', 'codigo': 'F5612', 'estudiantes': '8',  'estado': 'Pendiente'},
      {'nombre': 'Rosa Martínez','codigo': 'F8844', 'estudiantes': '15', 'estado': 'Pagado'},
    ];

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera grande como en tu diseño
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Freelancers',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('Registrar freelancer'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Tabla desplazable horizontalmente
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Nombre')),
                  DataColumn(label: Text('Código')),
                  DataColumn(label: Text('Estudiantes')),
                  DataColumn(label: Text('Estado de pago')),
                  DataColumn(label: Text('Acciones')),
                ],
                rows: freelancers.map((f) {
                  final estado = f['estado']!;
                  final color = estado == 'Pagado' ? Colors.green : Colors.orange;
                  return DataRow(cells: [
                    DataCell(Text(f['nombre']!)),
                    DataCell(Text(f['codigo']!)),
                    DataCell(Text(f['estudiantes']!)),
                    DataCell(Text(estado, style: TextStyle(color: color))),
                    DataCell(Row(
                      children: const [
                        Text('Ver', style: TextStyle(color: Colors.blue)),
                        SizedBox(width: 12),
                        Text('PDF', style: TextStyle(color: Colors.blue)),
                        SizedBox(width: 12),
                        Text('Enviar', style: TextStyle(color: Colors.blue)),
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
  }
}
