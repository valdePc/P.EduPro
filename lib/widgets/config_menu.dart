// lib/widgets/config_menu.dart
import 'package:flutter/material.dart';

/// Submenú de Configuración (responsive) — con iconos + check amarillo
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

  // Estilos como tu captura
  static const Color _kIconBlue = Color(0xFF2E489B);
  static const Color _kSelectedText = Color(0xFF64529F);
  static const Color _kDivider = Color(0xFFD5CFEA);

  IconData _iconForKey(String key) {
    switch (key) {
      case 'configuracion':
        return Icons.person;
      case 'gestion-accesos':
        return Icons.security;
      case 'preferencias-sistema':
        return Icons.tune;
      case 'branding':
        return Icons.brush;
      case 'pagos-facturacion':
        return Icons.receipt_long;
      case 'seguridad':
        return Icons.lock;
      case 'notificaciones':
        return Icons.notifications;
      default:
        return Icons.settings;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    final items = <Map<String, String>>[
      {
        'key': 'configuracion',
        'label': 'Cuenta & Perfil',
        'route': '/configuracion',
      },
      {
        'key': 'gestion-accesos',
        'label': 'Gestión de Accesos & Roles',
        'route': '/gestion-accesos',
      },
      {
        'key': 'preferencias-sistema',
        'label': 'Preferencias del Sistema',
        'route': '/preferencias-sistema',
      },
      {
        'key': 'branding',
        'label': 'Branding & Apariencia',
        'route': '/branding',
      },
      {
        'key': 'pagos-facturacion',
        'label': 'Pagos & Facturación',
        'route': '/pagos-facturacion',
      },
      {
        'key': 'seguridad',
        'label': 'Seguridad',
        'route': '/seguridad',
      },
      {
        'key': 'notificaciones',
        'label': 'Notificaciones',
        'route': '/notificaciones',
      },
    ];

    if (isMobile) {
      // Móvil: compacta horizontal con icono + texto (más pequeño)
      return SizedBox(
        height: 58,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final item = items[index];
            final key = item['key']!;
            final isSelected = key == selectedKey;

            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onItemSelected(item['route']!),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? _kIconBlue.withOpacity(0.08) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? _kDivider : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _iconForKey(key),
                      color: isSelected ? _kIconBlue : Colors.grey.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 170),
                      child: Text(
                        item['label']!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isSelected ? _kSelectedText : Colors.black87,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.check, color: Colors.amber, size: 16),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    // Escritorio/Tablet: vertical (icono + texto + check + separadores) — letras más pequeñas
    return Container(
      width: 280,
      color: Colors.white,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: _kDivider),
        itemBuilder: (context, i) {
          final item = items[i];
          final key = item['key']!;
          final isSelected = key == selectedKey;

          return InkWell(
            onTap: () => onItemSelected(item['route']!),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    _iconForKey(key),
                    size: 24,
                    color: isSelected ? _kIconBlue : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      item['label']!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.12,
                        color: isSelected ? _kSelectedText : Colors.black,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isSelected)
                    const Padding(
                      padding: EdgeInsets.only(left: 10),
                      child: Icon(Icons.check, color: Colors.amber, size: 20),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
