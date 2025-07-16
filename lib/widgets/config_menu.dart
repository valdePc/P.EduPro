// lib/widgets/config_menu.dart
import 'package:flutter/material.dart';

/// Submenú de Configuración (responsive)
class ConfigMenu extends StatelessWidget {
  /// Clave del ítem activo: 'configuracion', 'gestion-accesos', etc.
  final String selectedKey;
  /// Callback que navega a la ruta que le pases
  final void Function(String route) onItemSelected;

  const ConfigMenu({
    Key? key,
    required this.selectedKey,
    required this.onItemSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    final items = <Map<String, String>>[
      {
        'key': 'configuracion',
        'label': 'Cuenta & Perfil',
        'route': '/configuracion'
      },
      {
        'key': 'gestion-accesos',
        'label': 'Gestión de Accesos & Roles',
        'route': '/gestion-accesos'
      },
      {
        'key': 'preferencias-sistema',
        'label': 'Preferencias del Sistema',
        'route': '/preferencias-sistema'
      },
      {
        'key': 'branding',
        'label': 'Branding & Apariencia',
        'route': '/branding'
      },
      {
        'key': 'pagos-facturacion',               // ← clave actualizada
        'label': 'Pagos & Facturación',           // ← etiqueta
        'route': '/pagos-facturacion'             // ← ruta actualizada
      },
      {
        'key': 'seguridad',
        'label': 'Seguridad',
        'route': '/seguridad'
      },
      {
        'key': 'notificaciones',
        'label': 'Notificaciones',
        'route': '/notificaciones'
      },
    ];

    if (isMobile) {
      // Mostrar menú horizontal en móvil
      return SizedBox(
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const VerticalDivider(width: 8),
          itemBuilder: (context, index) {
            final item = items[index];
            final isSelected = item['key'] == selectedKey;
            return TextButton(
              onPressed: () => onItemSelected(item['route']!),
              style: TextButton.styleFrom(
                backgroundColor:
                    isSelected ? Colors.indigo.shade50 : Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(
                item['label']!,
                style: TextStyle(
                  color: isSelected ? Colors.indigo : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            );
          },
        ),
      );
    }

    // Menú vertical en escritorio/tablet
    return Container(
      width: 200,
      color: Colors.grey.shade100,
      child: ListView(
        children: items.map((item) {
          final isSelected = item['key'] == selectedKey;
          return ListTile(
            title: Text(
              item['label']!,
              style: TextStyle(
                color: isSelected ? Colors.indigo : Colors.black,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            selected: isSelected,
            selectedTileColor: Colors.indigo.shade50,
            onTap: () => onItemSelected(item['route']!),
          );
        }).toList(),
      ),
    );
  }
}
