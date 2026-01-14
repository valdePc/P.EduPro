// lib/screens/gestiondeacceso.dart
import 'package:flutter/material.dart';
import '../widgets/sidebar_menu.dart';
import '../widgets/config_menu.dart' as config;
import 'dart:math' show max;

class User {
  final String nombre;
  final String correo;
  final Set<String> permisos;

  User({
    required this.nombre,
    required this.correo,
    Set<String>? permisos,
  }) : permisos = permisos ?? <String>{};
}

class GestionDeAccesoScreen extends StatefulWidget {
  const GestionDeAccesoScreen({Key? key}) : super(key: key);

  @override
  State<GestionDeAccesoScreen> createState() => _GestionDeAccesoScreenState();
}

class _GestionDeAccesoScreenState extends State<GestionDeAccesoScreen> {
  // ✅ Colores iguales a Colegios / Configuración
  static const Color _kEduProBlue = Color(0xFF0D47A1);
  static const Color _kPageBg = Color(0xFFF0F0F0);
  static const Color _kCardBg = Color(0xFFF7F2FA);

  final List<User> _usuarios = [
    User(nombre: 'Carlos Pérez', correo: 'carlos.perez@ejemplo.com'),
    User(nombre: 'Laura Gómez', correo: 'laura.gomez@ejemplo.com'),
    User(nombre: 'David Martín', correo: 'david.martin@ejemplo.com'),
  ];

  late List<User> _filtrados;
  final TextEditingController _searchController = TextEditingController();

  final List<String> _availablePermissions = [
    'Panel principal',
    'Colegios',
    'Freelancers',
    'Pagos & Facturación',
    'Cuenta & Perfil',
    'Gestión de Accesos',
    'Preferencias del Sistema',
    'Branding & Apariencia',
    'Seguridad',
    'Notificaciones',
  ];

  final Map<String, List<String>> _rolePresets = {
    'Administrador': [
      'Panel principal',
      'Colegios',
      'Freelancers',
      'Pagos & Facturación',
      'Cuenta & Perfil',
      'Gestión de Accesos',
      'Preferencias del Sistema',
      'Branding & Apariencia',
      'Seguridad',
      'Notificaciones',
    ],
    'Profesor': [
      'Panel principal',
      'Colegios',
      'Colegios', // doble no importa (Set lo elimina)
      'Cuenta & Perfil',
    ],
    'Contable': [
      'Panel principal',
      'Pagos & Facturación',
    ],
  };

  @override
  void initState() {
    super.initState();
    _filtrados = List.from(_usuarios);
    _searchController.addListener(_filtrar);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filtrar);
    _searchController.dispose();
    super.dispose();
  }

  void _filtrar() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtrados = List.from(_usuarios);
      } else {
        _filtrados = _usuarios.where((u) {
          return u.nombre.toLowerCase().contains(q) ||
              u.correo.toLowerCase().contains(q) ||
              u.permisos.any((p) => p.toLowerCase().contains(q));
        }).toList();
      }
    });
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

  void _mostrarFormularioAgregar() {
    String nombre = '', correo = '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Añadir usuario'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Nombre'),
              onChanged: (v) => nombre = v,
            ),
            TextField(
              decoration: const InputDecoration(labelText: 'Correo'),
              keyboardType: TextInputType.emailAddress,
              onChanged: (v) => correo = v,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nombre.trim().isEmpty || correo.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Completa nombre y correo')),
                );
                return;
              }
              final exists = _usuarios.any(
                (u) => u.correo.toLowerCase() == correo.toLowerCase(),
              );
              if (exists) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Ya existe un usuario con ese correo')),
                );
                return;
              }

              setState(() {
                _usuarios.add(User(
                    nombre: nombre.trim(), correo: correo.trim()));
                _filtrados = List.from(_usuarios);
              });
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _confirmEliminar(User u) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text(
            '¿Seguro que deseas eliminar a ${u.nombre}? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                _usuarios.removeWhere((x) => x.correo == u.correo);
                _filtrados = List.from(_usuarios);
              });
              Navigator.pop(ctx);
            },
            child: const Text('Eliminar'),
          )
        ],
      ),
    );
  }

  void _editarPermisos(User user) {
    final temp = <String>{...user.permisos};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setSheetState) {
          void togglePerm(String perm, bool enabled) {
            setSheetState(() {
              if (enabled) temp.add(perm);
              else temp.remove(perm);
            });
          }

          void applyPreset(String presetName) {
            final preset = _rolePresets[presetName] ?? [];
            setSheetState(() {
              temp
                ..clear()
                ..addAll(preset);
            });
          }

          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(ctx2).size.height * 0.78,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Permisos de ${user.nombre}',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx2),
                          icon: const Icon(Icons.close),
                        )
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          const Text('Presets: ',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          ..._rolePresets.keys.map(
                            (k) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: OutlinedButton(
                                onPressed: () => applyPreset(k),
                                child: Text(k,
                                    style: const TextStyle(fontSize: 12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: _availablePermissions.map((perm) {
                        final has = temp.contains(perm);
                        return CheckboxListTile(
                          title: Text(perm),
                          value: has,
                          activeColor: _kEduProBlue,
                          onChanged: (v) => togglePerm(perm, v ?? false),
                        );
                      }).toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            user.permisos
                              ..clear()
                              ..addAll(temp);
                          });
                          Navigator.pop(ctx2);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kEduProBlue,
                        ),
                        child: const Text('Guardar cambios'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Gestión de Accesos & Roles',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar usuario, correo o permiso...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _filtrados = List.from(_usuarios);
                              setState(() {});
                            },
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _mostrarFormularioAgregar,
                icon: const Icon(Icons.person_add),
                label: const Text('Añadir'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kEduProBlue,
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Acciones masivas',
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  if (v == 'export') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Exportando lista...')),
                    );
                  } else if (v == 'import') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Importar (no implementado)')),
                    );
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'export', child: Text('Exportar CSV')),
                  PopupMenuItem(value: 'import', child: Text('Importar CSV')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _filtrados.isEmpty
                ? const Center(child: Text('No se encontraron usuarios'))
                : ListView.builder(
                    itemCount: _filtrados.length,
                    itemBuilder: (_, i) {
                      final u = _filtrados[i];
                      final initial =
                          u.nombre.trim().isNotEmpty ? u.nombre.trim()[0] : '?';

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _kEduProBlue.withOpacity(0.12),
                            foregroundColor: _kEduProBlue,
                            child: Text(initial),
                          ),
                          title: Text(u.nombre),
                          subtitle: Text(u.correo),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (u.permisos.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: GestureDetector(
                                    onTap: () => _editarPermisos(u),
                                    child: Chip(
                                      label: Text('${u.permisos.length} permisos'),
                                      backgroundColor:
                                          _kEduProBlue.withOpacity(0.08),
                                    ),
                                  ),
                                ),
                              PopupMenuButton<String>(
                                onSelected: (action) {
                                  if (action == 'perms') _editarPermisos(u);
                                  if (action == 'delete') _confirmEliminar(u);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'perms',
                                    child: ListTile(
                                      leading: Icon(Icons.security),
                                      title: Text('Permisos'),
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: ListTile(
                                      leading:
                                          Icon(Icons.delete, color: Colors.red),
                                      title: Text('Eliminar'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    final currentRoute =
        ModalRoute.of(context)?.settings.name ?? '/gestion-accesos';

    void _handleNavigation(String route) {
      if (route != currentRoute) {
        Navigator.pushReplacementNamed(context, route);
      }
    }

    // Card wrapper (para que se vea igual al layout de Configuración)
    Widget wrappedContent() {
      return Card(
        color: _kCardBg,
        margin: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 24,
          vertical: isMobile ? 16 : 24,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        child: _buildContent(),
      );
    }

    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: _buildTopBar(isMobile: isMobile),
      drawer: isMobile
          ? Drawer(
              child: Container(
                color: _kEduProBlue,
                child: SidebarMenu(
                  currentRoute: currentRoute,
                  onItemSelected: _handleNavigation,
                ),
              ),
            )
          : null,
      body: isMobile
          ? wrappedContent()
          : Row(
              children: [
                // Menú lateral global (azul)
                Container(
                  width: 260,
                  color: _kEduProBlue,
                  child: SidebarMenu(
                    currentRoute: currentRoute,
                    onItemSelected: _handleNavigation,
                  ),
                ),

                // Submenú de Configuración (blanco)
                SizedBox(
                  width: 280,
                  child: config.ConfigMenu(
                    selectedKey: 'gestion-accesos',
                    onItemSelected: _handleNavigation,
                  ),
                ),

                // Contenido
                Expanded(child: wrappedContent()),
              ],
            ),
    );
  }
}
