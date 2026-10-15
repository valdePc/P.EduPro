import 'package:flutter/material.dart';

import 'equipoedupro.dart';
import '../widgets/config_menu.dart' as config;
import '../widgets/sidebar_menu.dart';
import '../widgets/team_section_navigation.dart';

class GestionDeAccesoScreen extends StatelessWidget {
  const GestionDeAccesoScreen({Key? key}) : super(key: key);

  static const Color _kEduProBlue = Color(0xFF1A237E);
  static const Color _kPageBg = Color(0xFFF5F7FC);
  static const Color _kCardBg = Color(0xFFF7F2FA);

  PreferredSizeWidget _buildTopBar(
    BuildContext context, {
    required bool isMobile,
  }) {
    return AppBar(
      backgroundColor: _kEduProBlue,
      elevation: 0,
      toolbarHeight: 64,
      automaticallyImplyLeading: isMobile,
      leading:
          isMobile
              ? null
              : TeamSectionNavigation.backButton(
                context,
                targetRoute: '/configuracion',
                color: Colors.white,
              ),
      iconTheme: const IconThemeData(color: Colors.white),
      titleSpacing: isMobile ? null : 24,
      title: const Text(
        'EduPro',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: [
        if (isMobile)
          TeamSectionNavigation.backButton(
            context,
            targetRoute: '/configuracion',
            color: Colors.white,
          ),
        if (!isMobile)
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.18)),
                ),
                child: const Text(
                  'Configuracion General',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    final currentRoute =
        ModalRoute.of(context)?.settings.name ?? '/gestion-accesos';

    void handleNavigation(String route) {
      if (route != currentRoute) {
        Navigator.pushReplacementNamed(context, route);
      }
    }

    const title = 'Roles y permisos';
    const subtitle =
        'Aqui gestionas usuarios internos de EduPro, sus roles, accesos, horarios y dias permitidos desde un solo lugar.';

    Widget wrappedContent() {
      return Card(
        color: _kCardBg,
        margin: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 24,
          vertical: isMobile ? 16 : 24,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: EquipoEduProManager(
            embedded: true,
            title: title,
            subtitle: subtitle,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: _buildTopBar(context, isMobile: isMobile),
      drawer:
          isMobile
              ? Drawer(
                child: Container(
                  color: _kEduProBlue,
                  child: SidebarMenu(
                    currentRoute: currentRoute,
                    onItemSelected: handleNavigation,
                  ),
                ),
              )
              : null,
      body:
          isMobile
              ? wrappedContent()
              : Row(
                children: [
                  Container(
                    width: 240,
                    color: _kEduProBlue,
                    child: SidebarMenu(
                      currentRoute: currentRoute,
                      onItemSelected: handleNavigation,
                    ),
                  ),
                  SizedBox(
                    width: 310,
                    child: config.ConfigMenu(
                      selectedKey: 'gestion-accesos',
                      onItemSelected: handleNavigation,
                    ),
                  ),
                  Expanded(child: wrappedContent()),
                ],
              ),
    );
  }
}
