import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../utils/equipo_edupro_access.dart';

class SidebarMenu extends StatelessWidget {
  static const Color _kEduProBlue = Color(0xFF1A237E);
  final String currentRoute;
  final Function(String) onItemSelected;
  final String? teamRole;

  const SidebarMenu({
    Key? key,
    required this.currentRoute,
    required this.onItemSelected,
    this.teamRole,
  }) : super(key: key);

  bool _matchesRoute(String route) {
    if (route == '/facturacion') {
      return const <String>{
        '/facturacion',
        '/pagos-facturacion',
      }.contains(currentRoute);
    }
    if (route == '/configuracion') {
      return const <String>{
        '/configuracion',
        '/gestion-accesos',
        '/seguridad',
      }.contains(currentRoute);
    }
    return route == currentRoute;
  }

  Widget _menuItem(IconData icon, String label, String route) {
    final isSelected = _matchesRoute(route);
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
      selectedTileColor: Colors.white.withOpacity(0.12),
      onTap: () => onItemSelected(route),
    );
  }

  Future<String?> _loadTeamRole() async {
    if (teamRole != null) return teamRole;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      return await EquipoEduProAccess.currentTeamRole(user);
    } catch (_) {
      return null;
    }
  }

  Widget _buildMenuList(String? resolvedRole) {
    final canViewSchools =
        resolvedRole != null &&
        EquipoEduProPermissions.canViewSchools(resolvedRole);
    final canViewInsights =
        resolvedRole != null &&
        EquipoEduProPermissions.canViewInsights(resolvedRole);
    final canViewBilling =
        resolvedRole != null &&
        EquipoEduProPermissions.canViewBilling(resolvedRole);
    final canViewSensitiveConfig =
        resolvedRole != null &&
        EquipoEduProPermissions.canViewSensitiveConfig(resolvedRole);

    return ListView(
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
        if (canViewSchools) _menuItem(Icons.school, 'Colegios', '/colegios'),
        if (canViewInsights)
          _menuItem(Icons.insights_rounded, 'Analisis', '/analisis-general'),
        if (canViewInsights)
          _menuItem(Icons.public_rounded, 'Red Escolar', '/red-escolar'),
        if (canViewBilling)
          _menuItem(Icons.receipt_long, 'Facturacion', '/facturacion'),
        if (canViewSensitiveConfig)
          _menuItem(Icons.settings, 'Configuracion', '/configuracion'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    return FutureBuilder<String?>(
      future: _loadTeamRole(),
      builder: (context, snapshot) {
        final resolvedRole = snapshot.data;
        final menuList = _buildMenuList(resolvedRole);

        if (isMobile) {
          return menuList;
        }
        return Container(
          width: 220,
          color: _kEduProBlue,
          child: menuList,
        );
      },
    );
  }
}
