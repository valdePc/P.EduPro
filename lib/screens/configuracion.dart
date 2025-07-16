import 'package:flutter/material.dart';
import '../widgets/sidebar_menu.dart';
import 'pagos_facturacion.dart'; // Importa tu pantalla de configuración de Pagos & Facturación
import '../widgets/config_header.dart';

class ConfiguracionScreen extends StatelessWidget {
  const ConfiguracionScreen({super.key});

  void _handleNavigation(BuildContext context, String route) {
    final currentRoute = ModalRoute.of(context)!.settings.name;
    if (route != currentRoute) {
      Navigator.pushReplacementNamed(context, route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    final currentRoute = ModalRoute.of(context)!.settings.name ?? '/configuracion';

    // Definimos las nuevas opciones con su ruta correspondiente
    final menuItems = [
      {'label': 'Cuenta & Perfil',           'route': '/configuracion'},
      {'label': 'Gestión de Accesos & Roles','route': '/gestion-accesos'},
      {'label': 'Preferencias del Sistema',   'route': '/preferencias-sistema'},
      {'label': 'Branding & Apariencia',     'route': '/branding'},
      {'label': 'Pagos & Facturación',       'route': '/pagos-facturacion'}, // ← actualizado
      {'label': 'Seguridad',                 'route': '/seguridad'},
      {'label': 'Notificaciones',            'route': '/notificaciones'},
    ];

    Widget buildInnerMenu() {
      return Container(
        width: 220,
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: Colors.grey.shade300)),
        ),
        child: ListView(
          children: menuItems.map((item) {
            final isSelected = item['route'] == currentRoute;
            return ListTile(
              selected: isSelected,
              title: Text(item['label']!),
              onTap: () => _handleNavigation(context, item['route']!),
            );
          }).toList(),
        ),
      );
    }

    Widget buildContent() {
      switch (currentRoute) {
        case '/gestion-accesos':
          return _buildAccessRolesSection();
        case '/preferencias-sistema':
          return _buildPreferencesSection();
        case '/branding':
          return _buildBrandingSection();
        case '/pagos-facturacion':                                  // ← nuevo caso
          return const PagosFacturacionScreen();
        case '/seguridad':
          return _buildSecuritySection();
        case '/notificaciones':
          return _buildNotificationsSection();
        case '/configuracion':
        default:
          return _buildProfileSection();
      }
    }

return Scaffold(
  drawer: isMobile
      ? Drawer(
          child: Container(
            color: const Color.fromARGB(255, 13, 161, 82),
            child: SidebarMenu(
              currentRoute: currentRoute,
              onItemSelected: (route) => _handleNavigation(context, route),
            ),
          ),
        )
      : null,
  appBar: isMobile
      ? AppBar(
          title: const Text('EduPro'),
          backgroundColor: const Color.fromARGB(255, 13, 201, 160),
        )
      : null,



body: isMobile
  ? Column(
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonFormField<String>(
            value: menuItems.first['route'],
            items: menuItems
                .map((item) => DropdownMenuItem(
                      value: item['route'],
                      child: Text(item['label']!),
                    ))
                .toList(),
            onChanged: (val) {
              if (val != null) {
                _handleNavigation(context, val);
              }
            },
            decoration: const InputDecoration(
              labelText: 'Secciones de configuración',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(child: buildContent()),
      ],
    )

  : Column(
      children: [
        // 1) Banda azul fija arriba
        const ConfigHeader(title: '...'),

            // 2) Sidebar + submenú + contenido
        Expanded(
          child: Row(
            children: [
              Container(
                width: 240,
                color: const Color.fromARGB(255, 13, 161, 55),
                child: SidebarMenu(
                  currentRoute: currentRoute,
                  onItemSelected: (route) => _handleNavigation(context, route),
                ),
              ),
              buildInnerMenu(),
              const SizedBox(width: 24),
              Expanded(child: buildContent()),
            ],
                  ),
                ),
              ],
            ),
    );
  }

  // 1. Cuenta & Perfil
  Widget _buildProfileSection() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: ListView(
        children: [
          const Text('Cuenta & Perfil',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _inputField('Nombre de usuario', 'Valde (Edupro Admin)'),
          _inputField('Correo electrónico', 'admin@edupro.com'),
          _inputField('Contraseña', '••••••••', isPassword: true),
          _dropdownField('Idioma', ['Español', 'Inglés']),
          _dropdownField('Zona horaria', ['UTC-04:00', 'UTC-05:00']),
        ],
      ),
    );
  }

  // 2. Gestión de Accesos & Roles
  Widget _buildAccessRolesSection() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Gestión de Accesos & Roles',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text('• Invitar nuevos usuarios por rol'),
          const Text('• Listado y estado de usuarios'),
          const Text('• Asignar permisos finos (crear, editar, ver)'),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () {}, child: const Text('Ver listado de usuarios')),
        ],
      ),
    );
  }

  // 3. Preferencias del Sistema
  Widget _buildPreferencesSection() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: ListView(
        children: [
          const Text('Preferencias del Sistema',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _dropdownField('Formato de fecha', ['DD/MM/YYYY', 'MM/DD/YYYY']),
          _dropdownField('Formato de hora', ['24 horas', '12 horas']),
          const SizedBox(height: 16),
          _inputField('Plantilla correo (asunto)', 'Notificación Edupro'),
          _inputField('Plantilla correo (cuerpo)', 'Estimado/a ...'),
        ],
      ),
    );
  }

  // 4. Branding & Apariencia
  Widget _buildBrandingSection() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: ListView(
        children: [
          const Text('Branding & Apariencia',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () {}, child: const Text('Subir logo institucional')),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: () {}, child: const Text('Elegir paleta de colores')),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Tema oscuro por defecto'),
            value: false,
            onChanged: (v) {},
          ),
        ],
      ),
    );
  }

  // 5. Seguridad
  Widget _buildSecuritySection() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: ListView(
        children: [
          const Text('Seguridad',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Requerir 2FA en login'),
            value: true,
            onChanged: (v) {},
          ),
          SwitchListTile(
            title: const Text('Bloquear IP tras 5 intentos fallidos'),
            value: false,
            onChanged: (v) {},
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: () {}, child: const Text('Ver registros de actividad')),
        ],
      ),
    );
  }

  // 6. Notificaciones
Widget _buildNotificationsSection() {
  return Padding(
    padding: const EdgeInsets.all(24.0),
    child: ListView(
      children: [
        const Text(
          'Notificaciones',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Push notifications'),
          value: true,
          onChanged: (v) {},
        ),
        SwitchListTile(
          title: const Text('Alertas por email'),
          value: true,
          onChanged: (v) {},
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () {},
          child: const Text('Editar plantillas de notificación'),
        ),
      ],
    ),
  );
}

  // Helpers
  Widget _inputField(String label, String value, {bool isPassword = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          SizedBox(width: 200, child: Text(label)),
          Expanded(
            child: TextFormField(
              initialValue: value,
              obscureText: isPassword,
              decoration: isPassword
                  ? InputDecoration(
                      suffixIcon: TextButton(onPressed: () {}, child: const Text('Cambiar')))
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdownField(String label, List<String> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          SizedBox(width: 200, child: Text(label)),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: items.first,
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (val) {},
            ),
          ),
        ],
      ),
    );
  }
}
