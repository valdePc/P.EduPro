// lib/screens/notificaciones_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/sidebar_menu.dart';
import '../widgets/config_menu.dart';

class NotificacionesScreen extends StatefulWidget {
  const NotificacionesScreen({super.key});

  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  static const currentRoute = '/notificaciones';
  static const selectedKey = 'notificaciones';

  // ✅ Paleta igual a Colegios / Configuración
  static const Color _kEduProBlue = Color(0xFF0D47A1);
  static const Color _kPageBg = Color(0xFFF0F0F0);
  static const Color _kCardBg = Color(0xFFF7F2FA);

  // Canales disponibles (orden importante para la UI)
  final List<String> _channels = ['Email', 'Push', 'SMS'];

  // Secciones / eventos
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

  bool _loading = true;
  static const _prefsKey = 'notificaciones_config_v1';

  @override
  void initState() {
    super.initState();
    _loadFromPrefs();
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

  Future<void> _loadFromPrefs() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsKey);

      if (jsonStr != null && jsonStr.isNotEmpty) {
        final Map<String, dynamic> data = jsonDecode(jsonStr);

        // Aplicar configuración guardada sobre la estructura actual
        data.forEach((section, list) {
          final events = list as List<dynamic>;
          if (!_sections.containsKey(section)) return;

          final targetList = _sections[section]!;
          for (var i = 0; i < events.length && i < targetList.length; i++) {
            final map = (events[i] as Map).cast<String, dynamic>();

            // ✅ soporta 2 formatos: (a) Email/Push/SMS directo, (b) dentro de "channels"
            final channelsMap =
                (map['channels'] is Map) ? (map['channels'] as Map).cast<String, dynamic>() : map;

            targetList[i].channels.clear();
            for (final ch in _channels) {
              targetList[i].channels[ch] = channelsMap[ch] == true;
            }
          }
        });
      }
    } catch (_) {
      // defaults
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> out = {};
    _sections.forEach((section, events) {
      out[section] = events.map((e) => e.toMap()).toList();
    });
    await prefs.setString(_prefsKey, jsonEncode(out));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Notificaciones guardadas')));
    }
  }

  Future<void> _resetToDefaults() async {
    setState(() {
      for (final events in _sections.values) {
        for (final e in events) {
          for (final ch in _channels) e.channels[ch] = true;
        }
      }
    });
    await _saveToPrefs();
  }

  void _toggleChannelGlobally(String channel, bool value) {
    setState(() {
      for (final events in _sections.values) {
        for (final e in events) e.channels[channel] = value;
      }
    });
  }

  void _toggleSection(String section, bool value) {
    setState(() {
      final events = _sections[section];
      if (events == null) return;
      for (final e in events) {
        for (final ch in _channels) e.channels[ch] = value;
      }
    });
  }

  Widget _buildControlsHeader() {
    bool allChannelActive(String channel) {
      for (final events in _sections.values) {
        for (final e in events) {
          if (e.channels[channel] != true) return false;
        }
      }
      return true;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Canales globales',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                for (final ch in _channels)
                  Row(
                    children: [
                      Text(ch),
                      Checkbox(
                        activeColor: _kEduProBlue,
                        value: allChannelActive(ch),
                        onChanged: (v) => _toggleChannelGlobally(ch, v ?? false),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _resetToDefaults,
                  child: const Text('Restaurar por defecto'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
                  onPressed: _saveToPrefs,
                  child: const Text('Guardar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String sectionTitle, List<NotificationEvent> events) {
    bool sectionFullyOn() {
      for (final e in events) {
        for (final ch in _channels) {
          if (e.channels[ch] != true) return false;
        }
      }
      return true;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(
          children: [
            Expanded(
              child: Text(sectionTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            TextButton.icon(
              onPressed: () => _toggleSection(sectionTitle, !sectionFullyOn()),
              icon: Icon(sectionFullyOn()
                  ? Icons.check_box
                  : Icons.check_box_outline_blank),
              label: Text(
                  sectionFullyOn() ? 'Desactivar sección' : 'Activar sección'),
            ),
          ],
        ),
        children: [
          const Divider(height: 1),
          ...events.map((e) {
            return Column(
              children: [
                ListTile(
                  title: Text(e.label),
                  subtitle: Wrap(
                    spacing: 8,
                    children: _channels.map((ch) {
                      return FilterChip(
                        label: Text(ch),
                        selected: e.channels[ch] == true,
                        selectedColor: _kEduProBlue.withOpacity(0.12),
                        checkmarkColor: _kEduProBlue,
                        onSelected: (sel) {
                          setState(() => e.channels[ch] = sel);
                        },
                      );
                    }).toList(),
                  ),
                ),
                const Divider(height: 1),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    void go(String r) => Navigator.pushReplacementNamed(context, r);

    final content = ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 18),
      children: [
        _buildControlsHeader(),
        const SizedBox(height: 8),
        for (final entry in _sections.entries) _buildSection(entry.key, entry.value),
        const SizedBox(height: 24),
        Center(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
            icon: const Icon(Icons.save),
            label: const Text('Guardar configuración'),
            onPressed: _saveToPrefs,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );

    Widget wrappedContent() {
      return Card(
        color: _kCardBg,
        margin: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 0,
          vertical: isMobile ? 16 : 24,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        child: Padding(padding: const EdgeInsets.all(12), child: content),
      );
    }

    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: _buildTopBar(isMobile: isMobile),
      drawer: isMobile
          ? Drawer(
              backgroundColor: _kEduProBlue,
              child: SidebarMenu(currentRoute: currentRoute, onItemSelected: go),
            )
          : null,
      body: isMobile
          ? Column(
              children: [
                ConfigMenu(selectedKey: selectedKey, onItemSelected: go),
                const Divider(height: 1),
                Expanded(child: wrappedContent()),
              ],
            )
          : Row(
              children: [
                // ✅ Sidebar azul fijo
                Container(
                  width: 260,
                  color: _kEduProBlue,
                  child: SidebarMenu(currentRoute: currentRoute, onItemSelected: go),
                ),

                // ✅ Borde azul + submenú blanco (AQUÍ está el cambio que pediste)
                Container(
                  width: 286, // 6px borde + 280 menu
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(left: BorderSide(color: _kEduProBlue, width: 6)),
                  ),
                  child: ConfigMenu(selectedKey: selectedKey, onItemSelected: go),
                ),

                const SizedBox(width: 24),

                // ✅ Contenido
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 24),
                    child: wrappedContent(),
                  ),
                ),
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
    for (var ch in ['Email', 'Push', 'SMS']) {
      channels[ch] = true;
    }
  }

  // ✅ Importante: este formato coincide con tu _loadFromPrefs (y soporta legacy)
  Map<String, dynamic> toMap() {
    return {
      'label': label,
      for (final e in channels.entries) e.key: e.value,
      // opcional: también lo guardamos anidado para futuro
      'channels': Map<String, bool>.from(channels),
    };
  }
}
