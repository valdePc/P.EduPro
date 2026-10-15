import 'package:flutter/material.dart';

import '../widgets/sidebar_menu.dart';
import '../widgets/team_section_navigation.dart';

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({Key? key}) : super(key: key);

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  static const Color _kEduProBlue = Color(0xFF1A237E);
  static const Color _kPageBg = Color(0xFFF5F7FC);
  static const Color _kCardBg = Color(0xFFF7F2FA);

  final List<Map<String, String>> _menuItems = const [
    {'label': 'Cuenta & Perfil', 'route': '/configuracion'},
    {'label': 'Roles y permisos', 'route': '/gestion-accesos'},
    {'label': 'Seguridad', 'route': '/seguridad'},
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
      leading:
          isMobile
              ? null
              : TeamSectionNavigation.backButton(context, color: Colors.white),
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
          TeamSectionNavigation.backButton(context, color: Colors.white),
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

  Widget _buildInnerMenu(String currentRoute) {
    return Container(
      width: 310,
      decoration: BoxDecoration(
        color: _kEduProBlue,
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        boxShadow: [
          BoxShadow(
            color: _kEduProBlue.withOpacity(0.16),
            blurRadius: 14,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        itemCount: _menuItems.length,
        separatorBuilder:
            (_, __) =>
                Divider(height: 1, color: Colors.white.withOpacity(0.08)),
        itemBuilder: (context, i) {
          final item = _menuItems[i];
          final route = item['route']!;
          final selected = route == currentRoute || route == _selectedSubRoute;

          return ListTile(
            selected: selected,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            selectedTileColor: Colors.white.withOpacity(0.14),
            leading: Icon(
              _iconForRoute(route),
              color: selected ? Colors.amber : Colors.white.withOpacity(0.92),
            ),
            title: Text(
              item['label']!,
              style: TextStyle(
                color: Colors.white,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            trailing:
                selected
                    ? Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 18,
                        color: Colors.amber,
                      ),
                    )
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
      case '/facturacion':
        return Icons.receipt_long;
      case '/seguridad':
        return Icons.lock;
      default:
        return Icons.person;
    }
  }

  Widget _buildContent(String currentRoute) {
    switch (currentRoute) {
      case '/gestion-accesos':
        return _buildAccessRolesSection();
      case '/seguridad':
        return _buildSecuritySection();
      case '/configuracion':
      default:
        return _buildProfileSection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    final currentRoute =
        ModalRoute.of(context)?.settings.name ?? '/configuracion';

    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: _buildTopBar(isMobile: isMobile),
      drawer:
          isMobile
              ? Drawer(
                child: Container(
                  color: _kEduProBlue,
                  child: SidebarMenu(
                    currentRoute: currentRoute,
                    onItemSelected:
                        (route) => _handleNavigation(context, route),
                  ),
                ),
              )
              : null,
      body:
          isMobile
              ? Column(
                children: [
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: DropdownButtonFormField<String>(
                      value: _safeDropdownValue(currentRoute),
                      items:
                          _menuItems
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item['route'],
                                  child: Text(item['label']!),
                                ),
                              )
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
                        borderRadius: BorderRadius.circular(22),
                      ),
                      elevation: 3,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: _buildContent(currentRoute),
                      ),
                    ),
                  ),
                ],
              )
              : Row(
                children: [
                  Container(
                    width: 240,
                    color: _kEduProBlue,
                    child: SidebarMenu(
                      currentRoute: currentRoute,
                      onItemSelected:
                          (route) => _handleNavigation(context, route),
                    ),
                  ),
                  _buildInnerMenu(currentRoute),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                      child: Card(
                        color: _kCardBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                        elevation: 3,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: _buildContent(currentRoute),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _buildProfileSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kEduProBlue, Color(0xFF2D64C8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _kEduProBlue.withOpacity(0.18),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cuenta & Perfil',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Administra tu identidad, preferencias base y los datos principales del superadministrador.',
                          style: TextStyle(color: Colors.white70, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _ProfileBadge(label: 'Rol', value: 'Super Admin'),
                  _ProfileBadge(label: 'Acceso', value: 'Activo'),
                  _ProfileBadge(label: 'Seguridad', value: 'Alta'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 18,
          runSpacing: 18,
          children: [
            _miniStatCard(
              icon: Icons.person_outline_rounded,
              title: 'Perfil principal',
              value: 'Valde',
              accent: _kEduProBlue,
            ),
            _miniStatCard(
              icon: Icons.email_outlined,
              title: 'Correo base',
              value: 'valdeymse@gmail.com',
              accent: Colors.teal,
            ),
            _miniStatCard(
              icon: Icons.schedule_rounded,
              title: 'Zona horaria',
              value: 'UTC-04:00',
              accent: Colors.orange,
            ),
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          'Datos principales',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        _labeledInput('Nombre de usuario', 'Administrador EduPro'),
        _labeledInput('Correo electronico', 'valdeymse@gmail.com'),
        _labeledInput('Contrasena', '........', isPassword: true),
        const SizedBox(height: 8),
        const Text(
          'Preferencias regionales',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        _labeledDropdown('Idioma', ['Espanol', 'Ingles']),
        _labeledDropdown('Zona horaria', ['UTC-04:00', 'UTC-05:00']),
      ],
    );
  }

  Widget _buildAccessRolesSection() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kEduProBlue, Color(0xFF2D64C8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _kEduProBlue.withOpacity(0.18),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_outlined,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Roles y permisos',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Controla invitaciones, niveles de acceso y la salud operativa de cada perfil dentro de EduPro.',
                          style: TextStyle(color: Colors.white70, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _ProfileBadge(label: 'Admins', value: '1 activo'),
                  _ProfileBadge(label: 'Operaciones', value: '2 roles'),
                  _ProfileBadge(label: 'Permisos', value: 'Granulares'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 18,
          runSpacing: 18,
          children: [
            _miniStatCard(
              icon: Icons.manage_accounts_outlined,
              title: 'Usuarios con acceso',
              value: '12',
              accent: _kEduProBlue,
            ),
            _miniStatCard(
              icon: Icons.verified_user_outlined,
              title: 'Roles definidos',
              value: '6',
              accent: Colors.green,
            ),
            _miniStatCard(
              icon: Icons.warning_amber_rounded,
              title: 'Pendientes',
              value: '2 invitaciones',
              accent: Colors.orange,
            ),
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          'Capacidades principales',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 18,
          runSpacing: 18,
          children: const [
            _AccessFeatureCard(
              icon: Icons.person_add_alt_1_rounded,
              title: 'Invitaciones por rol',
              description:
                  'Crea accesos para soporte, operaciones, facturacion o supervision con una ruta clara por perfil.',
            ),
            _AccessFeatureCard(
              icon: Icons.rule_folder_outlined,
              title: 'Permisos granulares',
              description:
                  'Define quien puede crear, editar, aprobar, facturar o solo visualizar informacion sensible.',
            ),
            _AccessFeatureCard(
              icon: Icons.history_toggle_off_rounded,
              title: 'Trazabilidad',
              description:
                  'Revisa cambios recientes, roles otorgados y movimientos importantes para auditoria interna.',
            ),
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          'Acciones rapidas',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.group_add),
              label: const Text('Invitar usuario'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kEduProBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.groups_rounded),
              label: const Text('Ver listado de usuarios'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kEduProBlue,
                side: const BorderSide(color: _kEduProBlue),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.admin_panel_settings_rounded),
              label: const Text('Editar permisos'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kEduProBlue,
                side: const BorderSide(color: _kEduProBlue),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
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
        _labeledInput('Plantilla correo (asunto)', 'Notificacion EduPro'),
        _labeledInput(
          'Plantilla correo (cuerpo)',
          'Estimado/a ...',
          multiline: true,
        ),
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

  Widget _labeledInput(
    String label,
    String value, {
    bool isPassword = false,
    bool multiline = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFDDE4FF)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 240,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: value,
                obscureText: isPassword,
                maxLines: multiline ? 4 : 1,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF8FAFF),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFD7DEFA)),
                  ),
                  suffix:
                      isPassword
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
      ),
    );
  }

  Widget _labeledDropdown(String label, List<String> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFDDE4FF)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 240,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: items.first,
                items:
                    items
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                onChanged: (val) {},
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF8FAFF),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFD7DEFA)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color accent,
  }) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileBadge extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileBadge({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AccessFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _AccessFeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE4FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFE8ECFF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: _ConfiguracionScreenState._kEduProBlue),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(color: Colors.grey.shade700, height: 1.4),
          ),
        ],
      ),
    );
  }
}
