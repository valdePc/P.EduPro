import 'package:flutter/material.dart';

class SidebarMenu extends StatelessWidget {
  final String currentRoute;
  final Function(String) onItemSelected;

  const SidebarMenu({
    Key? key,
    required this.currentRoute,
    required this.onItemSelected,
  }) : super(key: key);

  Widget _menuItem(IconData icon, String label, String route) {
    final isSelected = route == currentRoute;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? Colors.amber : Colors.white,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.amber : Colors.white,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedTileColor: Colors.blue.shade700,
      onTap: () => onItemSelected(route),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    final menuList = ListView(
      padding: const EdgeInsets.symmetric(vertical: 40),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'EduPro',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 30),
        _menuItem(Icons.dashboard, 'Panel principal', '/panel'),
        _menuItem(Icons.school, 'Colegios', '/colegios'),
        _menuItem(Icons.person, 'Freelancers', '/freelancers'),
        _menuItem(Icons.receipt_long, 'Facturación', '/facturacion'),
        _menuItem(Icons.settings, 'Configuración', '/configuracion'),
      ],
    );

    if (isMobile) {
      return menuList;
    } else {
      return Container(
        width: 220,
        color: Colors.blue.shade900,
        child: menuList,
      );
    }
  }
}
