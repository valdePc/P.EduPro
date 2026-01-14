import 'package:flutter/material.dart';
import '../widgets/sidebar_menu.dart';
import 'pagos_facturacion.dart'; // Pantalla interna de Configuración

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({Key? key}) : super(key: key);

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  // ✅ Azul exacto del header/side en tu pantalla “Colegios”
  static const Color _kEduProBlue = Color(0xFF0D47A1);
  static const Color _kPageBg = Color(0xFFF0F0F0);
  static const Color _kCardBg = Color(0xFFF7F2FA);

  // Rutas del submenú
  final List<Map<String, String>> _menuItems = [
    {'label': 'Cuenta & Perfil', 'route': '/configuracion'},
    {'label': 'Gestión de Accesos & Roles', 'route': '/gestion-accesos'},
    {'label': 'Preferencias del Sistema', 'route': '/preferencias-sistema'},
    {'label': 'Branding & Apariencia', 'route': '/branding'},
    {'label': 'Pagos & Facturación', 'route': '/pagos-facturacion'},
    {'label': 'Seguridad', 'route': '/seguridad'},
    {'label': 'Notificaciones', 'route': '/notificaciones'},
  ];

  String? _selectedSubRoute;

  bool _isRouteInMenu(String? route) {
    if (route == null) return false;
    return _menuItems.any((e) => e['route'] == route);
  }

  String _safeDropdownValue(String currentRoute) {
    if (_isRouteInMenu(_selectedSubRoute)) return _selectedSubRoute!;
    if (_isRouteInMenu(currentRoute)) return currentRoute;
    return _menuItems.first['route']!;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context)?.settings.name;
    if (_isRouteInMenu(route)) _selectedSubRoute = route;
    _selectedSubRoute ??= _menuItems.first['route'];
  }

  void _handleNavigation(BuildContext context, String route) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    if (route != currentRoute) {
      Navigator.pushReplacementNamed(context, route);
    } else {
      setState(() => _selectedSubRoute = route);
    }
  }

  PreferredSizeWidget _buildTopBar({required bool isMobile}) {
    return AppBar(
      backgroundColor: _kEduProBlue,
      elevation: 0,
      toolbarHeight: 64,
      automaticallyImplyLeading: isMobile,
      iconTheme: const IconThemeData(color: Colors.white),
      title: const SizedBox.shrink(),
      actions: const [
        Center(
          child: Padding(
            padding: EdgeInsets.only(right: 24),
            child: Text(
              'Configuración General',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInnerMenu(String currentRoute) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _menuItems.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final item = _menuItems[i];
          final route = item['route']!;
          final selected = route == currentRoute || route == _selectedSubRoute;

          return ListTile(
            selected: selected,
            selectedTileColor: _kEduProBlue.withOpacity(0.08),
            leading: Icon(
              _iconForRoute(route),
              color: selected ? _kEduProBlue : Colors.grey.shade700,
            ),
            title: Text(
              item['label']!,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            trailing: selected
                ? const Icon(Icons.check, size: 18, color: Colors.amber)
                : null,
            onTap: () => _handleNavigation(context, route),
          );
        },
      ),
    );
  }

  IconData _iconForRoute(String r) {
    switch (r) {
      case '/gestion-accesos':
        return Icons.security;
      case '/preferencias-sistema':
        return Icons.tune;
      case '/branding':
        return Icons.brush;
      case '/pagos-facturacion':
        return Icons.receipt_long;
      case '/seguridad':
        return Icons.lock;
      case '/notificaciones':
        return Icons.notifications;
      default:
        return Icons.person;
    }
  }

  Widget _buildContent(String currentRoute) {
    switch (currentRoute) {
      case '/gestion-accesos':
        return _buildAccessRolesSection();
      case '/preferencias-sistema':
        return _buildPreferencesSection();
      case '/branding':
        return _buildBrandingSection();
      case '/pagos-facturacion':
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

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    final currentRoute = ModalRoute.of(context)?.settings.name ?? '/configuracion';

    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: _buildTopBar(isMobile: isMobile),
      drawer: isMobile
          ? Drawer(
              child: Container(
                color: _kEduProBlue,
                child: SidebarMenu(
                  currentRoute: currentRoute,
                  onItemSelected: (route) => _handleNavigation(context, route),
                ),
              ),
            )
          : null,
      body: isMobile
          ? Column(
              children: [
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<String>(
                    value: _safeDropdownValue(currentRoute),
                    items: _menuItems
                        .map((item) => DropdownMenuItem(
                              value: item['route'],
                              child: Text(item['label']!),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) _handleNavigation(context, val);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Secciones',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Card(
                    color: _kCardBg,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildContent(currentRoute),
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                // Sidebar global (igual que Colegios: azul)
                Container(
                  width: 260,
                  color: _kEduProBlue,
                  child: SidebarMenu(
                    currentRoute: currentRoute,
                    onItemSelected: (route) => _handleNavigation(context, route),
                  ),
                ),

                // Submenú de configuración (blanco)
                _buildInnerMenu(currentRoute),

                // Contenido (card)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                    child: Card(
                      color: _kCardBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _buildContent(currentRoute),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ------------------------ Secciones ------------------------
  Widget _buildProfileSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Cuenta & Perfil',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _labeledInput('Nombre de usuario', 'Valde (EduPro Admin)'),
        _labeledInput('Correo electrónico', 'admin@edupro.com'),
        _labeledInput('Contraseña', '••••••••', isPassword: true),
        const SizedBox(height: 12),
        _labeledDropdown('Idioma', ['Español', 'Inglés']),
        _labeledDropdown('Zona horaria', ['UTC-04:00', 'UTC-05:00']),
      ],
    );
  }

  Widget _buildAccessRolesSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Gestión de Accesos & Roles',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Text('• Invitar nuevos usuarios por rol'),
        const Text('• Listado y estado de usuarios'),
        const Text('• Asignar permisos finos (crear, editar, ver)'),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.group_add),
          label: const Text('Invitar usuario'),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () {},
          child: const Text('Ver listado de usuarios'),
        ),
      ],
    );
  }

  Widget _buildPreferencesSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Preferencias del Sistema',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _labeledDropdown('Formato de fecha', ['DD/MM/YYYY', 'MM/DD/YYYY']),
        _labeledDropdown('Formato de hora', ['24 horas', '12 horas']),
        const SizedBox(height: 16),
        _labeledInput('Plantilla correo (asunto)', 'Notificación EduPro'),
        _labeledInput('Plantilla correo (cuerpo)', 'Estimado/a ...',
            multiline: true),
      ],
    );
  }

  Widget _buildBrandingSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Branding & Apariencia',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.upload_file),
          label: const Text('Subir logo institucional'),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.palette),
          label: const Text('Elegir paleta de colores'),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Tema oscuro por defecto'),
          value: false,
          onChanged: (v) {},
        ),
      ],
    );
  }

  Widget _buildSecuritySection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Seguridad',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
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
        ElevatedButton(
          onPressed: () {},
          child: const Text('Ver registros de actividad'),
        ),
      ],
    );
  }

  Widget _buildNotificationsSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Notificaciones',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
    );
  }

  // ------------------------ Helpers UI ------------------------
  Widget _labeledInput(String label, String value,
      {bool isPassword = false, bool multiline = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          SizedBox(
            width: 240,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              initialValue: value,
              obscureText: isPassword,
              maxLines: multiline ? 4 : 1,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                suffix: isPassword
                    ? TextButton(
                        onPressed: () {},
                        child: const Text('Cambiar'),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _labeledDropdown(String label, List<String> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          SizedBox(
            width: 240,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: items.first,
              items: items
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (val) {},
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
        ],
      ),
    );
  }
}
