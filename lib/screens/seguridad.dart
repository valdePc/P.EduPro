// lib/screens/seguridad_screen.dart
import 'package:flutter/material.dart';
import '../widgets/sidebar_menu.dart';
import '../widgets/config_menu.dart';

class SeguridadScreen extends StatefulWidget {
  const SeguridadScreen({super.key});

  @override
  State<SeguridadScreen> createState() => _SeguridadScreenState();
}

class _SeguridadScreenState extends State<SeguridadScreen> {
  bool _twoFA = false;
  List<String> _devices = ['Firefox – Windows', 'Safari – iOS'];
  List<String> _ips = ['192.168.1.100', '203.0.113.42'];
  final _ipController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    const currentRoute = '/seguridad';
    const selectedKey = 'seguridad';
    final isMobile = MediaQuery.of(context).size.width < 800;

    Widget content = ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SwitchListTile(
          title: const Text('Autenticación 2FA'),
          subtitle: const Text('Protege tu cuenta con un segundo factor'),
          value: _twoFA,
          onChanged: (v) => setState(() => _twoFA = v),
        ),
        const Divider(),
        ExpansionTile(
          title: const Text('Dispositivos confiables'),
          subtitle: Text('${_devices.length} guardados'),
          children: [
            for (var d in _devices)
              ListTile(
                dense: true,
                title: Text(d),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () => setState(() => _devices.remove(d)),
                ),
              ),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Agregar dispositivo'),
              onPressed: () => setState(() => _devices.add('Nuevo dispositivo')),
            )
          ],
        ),
        const Divider(),
        ExpansionTile(
          title: const Text('IPs permitidas'),
          subtitle: Text('${_ips.length} registradas'),
          children: [
            for (var ip in _ips)
              ListTile(
                dense: true,
                title: Text(ip),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () => setState(() => _ips.remove(ip)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ipController,
                      decoration: const InputDecoration(
                        labelText: 'Nueva IP',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final ip = _ipController.text.trim();
                      if (ip.isNotEmpty) {
                        setState(() {
                          _ips.add(ip);
                          _ipController.clear();
                        });
                      }
                    },
                    child: const Text('Agregar'),
                  )
                ],
              ),
            )
          ],
        ),
        const Divider(),
        ExpansionTile(
          title: const Text('Historial de acceso'),
          children: const [
            ListTile(
              dense: true,
              title: Text('2025-05-07 10:15 — Inicio de sesión exitoso'),
            ),
            ListTile(
              dense: true,
              title: Text('2025-05-06 22:03 — Intento fallido (IP 203.0.113.5)'),
            ),
            ListTile(
              dense: true,
              title: Text('2025-05-05 14:27 — Cambio de contraseña'),
            ),
          ],
        ),
        const Divider(),
        ListTile(
          title: const Text('Política de contraseñas'),
          subtitle: const Text('– Mínimo 8 caracteres\n'
              '– Al menos 1 mayúscula\n'
              '– Al menos 1 número\n'
              '– Al menos 1 carácter especial'),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ajustes de seguridad guardados')),
            );
          },
          child: const Text('Guardar cambios'),
        ),
      ],
    );

    return Scaffold(
      drawer: isMobile
          ? Drawer(
              child: SidebarMenu(
                currentRoute: currentRoute,
                onItemSelected: (r) => Navigator.pushReplacementNamed(context, r),
              ),
              backgroundColor: Colors.blue.shade900,
            )
          : null,
      appBar: isMobile
          ? AppBar(title: const Text('Seguridad'))
          : PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Container(
                color: Colors.blue.shade700,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Text(
                  'Configuración General',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            ),
      body: isMobile
          ? Column(
              children: [
                ConfigMenu(
                  selectedKey: selectedKey,
                  onItemSelected: (r) => Navigator.pushReplacementNamed(context, r),
                ),
                const Divider(height: 1),
                Expanded(child: content),
              ],
            )
          : Row(
              children: [
                SidebarMenu(
                  currentRoute: currentRoute,
                  onItemSelected: (r) => Navigator.pushReplacementNamed(context, r),
                ),
                ConfigMenu(
                  selectedKey: selectedKey,
                  onItemSelected: (r) => Navigator.pushReplacementNamed(context, r),
                ),
                const SizedBox(width: 24),
                Expanded(child: content),
              ],
            ),
    );
  }
}
