// lib/screens/notificaciones_screen.dart
import 'package:flutter/material.dart';
import '../widgets/sidebar_menu.dart';
import '../widgets/config_menu.dart';

class NotificacionesScreen extends StatefulWidget {
  const NotificacionesScreen({super.key});

  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  // Definimos los canales disponibles
  final _channels = ['Email', 'Push', 'SMS'];

  // Mapa: categoría → lista de eventos con estados por canal
  final Map<String, List<NotificationEvent>> _sections = {
    'Usuarios & Acceso': [
      NotificationEvent('Nuevo colegio registrado'),
      NotificationEvent('Maestro pendiente de aprobación'),
      NotificationEvent('Nuevo alumno registrado'),
      NotificationEvent('Solicitud de restablecer contraseña'),
      NotificationEvent('Bloqueo de cuenta (intentos fallidos)'),
    ],
    'Finanzas & Suscripción': [
      NotificationEvent('Pago realizado / recibo generado'),
      NotificationEvent('Pago fallido / suscripción vencida'),
      NotificationEvent('Recordatorio de renovación de plan'),
    ],
    'Seguridad & Sistema': [
      NotificationEvent('Actividad inusual detectada'),
      NotificationEvent('Backup completado / fallido'),
      NotificationEvent('Mantenimiento programado'),
      NotificationEvent('Error crítico de sistema'),
    ],
    'Operaciones & Uso': [
      NotificationEvent('90% de cupos alcanzados'),
      NotificationEvent('Nuevo reporte generado'),
      NotificationEvent('Integración externa caída / recuperada'),
    ],
  };

  @override
  Widget build(BuildContext context) {
    const currentRoute = '/notificaciones';
    const selectedKey = 'notificaciones';
    final isMobile = MediaQuery.of(context).size.width < 800;

    Widget content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final entry in _sections.entries) ...[
          Text(entry.key,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (final event in entry.value) ...[
            ExpansionTile(
              title: Text(event.label),
              childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              children: [
                for (final channel in _channels)
                  SwitchListTile(
                    title: Text(channel),
                    value: event.channels[channel]!,
                    onChanged: (v) {
                      setState(() {
                        event.channels[channel] = v;
                      });
                    },
                  ),
              ],
            ),
            const Divider(),
          ],
          const SizedBox(height: 16),
        ],
        Center(
          child: ElevatedButton(
            onPressed: () {
              // Aquí iría la lógica de guardar en backend
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Notificaciones guardadas')),
              );
            },
            child: const Text('Guardar cambios'),
          ),
        ),
      ],
    );

    return Scaffold(
      drawer: isMobile
          ? Drawer(
              child: SidebarMenu(
                currentRoute: currentRoute,
                onItemSelected: (r) =>
                    Navigator.pushReplacementNamed(context, r),
              ),
              backgroundColor: Colors.blue.shade900,
            )
          : null,
    appBar: isMobile
  ? AppBar(title: const Text('Notificaciones'))
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
                  onItemSelected: (r) =>
                      Navigator.pushReplacementNamed(context, r),
                ),
                const Divider(height: 1),
                Expanded(child: content),
              ],
            )
          : Row(
              children: [
                SidebarMenu(
                  currentRoute: currentRoute,
                  onItemSelected: (r) =>
                      Navigator.pushReplacementNamed(context, r),
                ),
                ConfigMenu(
                  selectedKey: selectedKey,
                  onItemSelected: (r) =>
                      Navigator.pushReplacementNamed(context, r),
                ),
                Expanded(child: content),
              ],
            ),
    );
  }
}

/// Modelo para un evento de notificación con estados por canal
class NotificationEvent {
  final String label;
  final Map<String, bool> channels = {};

  NotificationEvent(this.label) {
    // Inicializamos todos los canales en true
    for (var ch in ['Email', 'Push', 'SMS']) {
      channels[ch] = true;
    }
  }
}
