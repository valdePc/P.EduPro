import 'package:flutter/material.dart';

class ConfigMenu extends StatelessWidget {
  final String selectedKey;
  final void Function(String route) onItemSelected;

  const ConfigMenu({
    Key? key,
    required this.selectedKey,
    required this.onItemSelected,
  }) : super(key: key);

  static const Color _kEduProBlue = Color(0xFF1A237E);

  IconData _iconForKey(String key) {
    switch (key) {
      case 'configuracion':
        return Icons.person;
      case 'gestion-accesos':
        return Icons.security;
      case 'seguridad':
        return Icons.lock;
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
        'label': 'Roles y permisos',
        'route': '/gestion-accesos',
      },
      {
        'key': 'seguridad',
        'label': 'Seguridad',
        'route': '/seguridad',
      },
    ];

    if (isMobile) {
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
              borderRadius: BorderRadius.circular(14),
              onTap: () => onItemSelected(item['route']!),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? _kEduProBlue.withOpacity(0.12) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? _kEduProBlue.withOpacity(0.24)
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _iconForKey(key),
                      color: isSelected ? _kEduProBlue : Colors.grey.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item['label']!,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isSelected ? _kEduProBlue : Colors.black87,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
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

    return Container(
      width: 310,
      decoration: BoxDecoration(
        color: _kEduProBlue,
        border: Border(right: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        itemCount: items.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: Colors.white.withOpacity(0.08)),
        itemBuilder: (context, i) {
          final item = items[i];
          final key = item['key']!;
          final isSelected = key == selectedKey;

          return ListTile(
            selected: isSelected,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            selectedTileColor: Colors.white.withOpacity(0.14),
            leading: Icon(
              _iconForKey(key),
              size: 24,
              color: isSelected ? Colors.amber : Colors.white.withOpacity(0.92),
            ),
            title: Text(
              item['label']!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.12,
                color: Colors.white,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            trailing: isSelected
                ? Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check, color: Colors.amber, size: 18),
                  )
                : null,
            onTap: () => onItemSelected(item['route']!),
          );
        },
      ),
    );
  }
}
