// lib/screens/gestiondeacceso.dart
import 'package:flutter/material.dart';
import '../widgets/sidebar_menu.dart';
import '../widgets/config_menu.dart' as config;
import '../widgets/config_header.dart';

class User {
  final String nombre;
  final String correo;
  List<String> permisos;

  User({
    required this.nombre,
    required this.correo,
    this.permisos = const [],
  });
}

class GestionDeAccesoScreen extends StatefulWidget {
  const GestionDeAccesoScreen({Key? key}) : super(key: key);

  @override
  State<GestionDeAccesoScreen> createState() => _GestionDeAccesoScreenState();
}

class _GestionDeAccesoScreenState extends State<GestionDeAccesoScreen> {
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

  @override
  void initState() {
    super.initState();
    _filtrados = List.from(_usuarios);
    _searchController.addListener(_filtrar);
  }

  void _filtrar() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filtrados = _usuarios.where((u) =>
        u.nombre.toLowerCase().contains(q) ||
        u.correo.toLowerCase().contains(q)
      ).toList();
    });
  }

  void _mostrarFormularioAgregar() {
    String nombre = '', correo = '';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
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
              onChanged: (v) => correo = v,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nombre.isNotEmpty && correo.isNotEmpty) {
                setState(() {
                  _usuarios.add(User(nombre: nombre, correo: correo));
                  _filtrados = List.from(_usuarios);
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _eliminarUsuario(int index) {
    final u = _filtrados[index];
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Eliminar usuario?'),
        content: Text('¿Deseas eliminar a ${u.nombre}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                _usuarios.removeWhere((x) => x.correo == u.correo);
                _filtrados = List.from(_usuarios);
              });
              Navigator.pop(context);
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _editarPermisos(User user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SizedBox(
              height: 450,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Permisos de ${user.nombre}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: _availablePermissions.map((perm) {
                        final has = user.permisos.contains(perm);
                        return CheckboxListTile(
                          title: Text(perm),
                          value: has,
                          onChanged: (v) => setSheetState(() {
                            setState(() {
                              if (v == true) user.permisos.add(perm);
                              else user.permisos.remove(perm);
                            });
                          }),
                        );
                      }).toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Guardar cambios'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Buscar usuario...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _mostrarFormularioAgregar,
                icon: const Icon(Icons.person_add),
                label: const Text('Añadir'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              itemCount: _filtrados.length,
              itemBuilder: (_, i) {
                final u = _filtrados[i];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(u.nombre),
                    subtitle: Text(u.correo),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.security),
                          tooltip: 'Permisos',
                          onPressed: () => _editarPermisos(u),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _eliminarUsuario(i),
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
        ModalRoute.of(context)!.settings.name ?? '/gestion-accesos';

    void _handleNavigation(String route) {
      if (route != currentRoute) {
        Navigator.pushReplacementNamed(context, route);
      }
    }

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gestión de Accesos')),
        drawer: Drawer(
          child: SidebarMenu(
            currentRoute: currentRoute,
            onItemSelected: _handleNavigation,
          ),
        ),
        body: _buildContent(),
      );
    }

    // Escritorio: header + sidebar + submenú + contenido
    return Scaffold(
      body: Column(
        children: [
          // 1) Banda azul fija arriba
          const ConfigHeader(title: 'Configuración General'),

          // 2) Resto de la pantalla
          Expanded(
            child: Row(
              children: [
                // 2.1) Menú lateral
                SidebarMenu(
                  currentRoute: currentRoute,
                  onItemSelected: _handleNavigation,
                ),

                // 2.2) Submenú justo debajo del header
                config.ConfigMenu(
                  selectedKey: 'gestion-accesos',
                  onItemSelected: _handleNavigation,
                ),

                // 2.3) Contenido a la derecha
                Expanded(child: _buildContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
