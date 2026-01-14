// lib/screens/seguridad.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/sidebar_menu.dart';
import '../widgets/config_menu.dart';

class SeguridadScreen extends StatefulWidget {
  const SeguridadScreen({super.key});

  @override
  State<SeguridadScreen> createState() => _SeguridadScreenState();
}

class _SeguridadScreenState extends State<SeguridadScreen> {
  static const currentRoute = '/seguridad';
  static const selectedKey = 'seguridad';

  // ✅ Paleta igual a Colegios / Configuración
  static const Color _kEduProBlue = Color(0xFF0D47A1);
  static const Color _kPageBg = Color(0xFFF0F0F0);
  static const Color _kCardBg = Color(0xFFF7F2FA);

  // Estado local (persistido en SharedPreferences)
  bool _twoFA = false;
  List<String> _devices = ['Firefox – Windows', 'Safari – iOS'];
  List<String> _ips = ['192.168.1.100', '203.0.113.42'];
  List<String> _history = [
    '2025-05-07 10:15 — Inicio de sesión exitoso',
    '2025-05-06 22:03 — Intento fallido (IP 203.0.113.5)',
    '2025-05-05 14:27 — Cambio de contraseña',
  ];

  final _ipController = TextEditingController();
  final _deviceController = TextEditingController();
  bool _loading = true;

  // Firestore
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Key para SharedPreferences
  static const _prefsKey = 'seguridad_config_v1';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _deviceController.dispose();
    super.dispose();
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

  Future<void> _loadPrefs() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final Map<String, dynamic> data = jsonDecode(raw);
        _twoFA = data['twoFA'] == true;
        _devices = List<String>.from(data['devices'] ?? _devices);
        _ips = List<String>.from(data['ips'] ?? _ips);
        _history = List<String>.from(data['history'] ?? _history);
      }
    } catch (_) {
      // defaults
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final out = {
      'twoFA': _twoFA,
      'devices': _devices,
      'ips': _ips,
      'history': _history,
    };
    await prefs.setString(_prefsKey, jsonEncode(out));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajustes de seguridad guardados')),
      );
    }
  }

  bool _isValidIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  Future<bool?> _confirmDialog(String title, String body) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportConfig() async {
    final map = {
      'twoFA': _twoFA,
      'devices': _devices,
      'ips': _ips,
      'history': _history,
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(map);
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración copiada al portapapeles (JSON)')),
      );
    }
  }

  Future<void> _importConfigFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text ?? '';
    if (text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Portapapeles vacío')),
        );
      }
      return;
    }
    try {
      final Map<String, dynamic> map = jsonDecode(text);
      setState(() {
        _twoFA = map['twoFA'] == true;
        _devices = List<String>.from(map['devices'] ?? []);
        _ips = List<String>.from(map['ips'] ?? []);
        _history = List<String>.from(map['history'] ?? []);
      });
      await _savePrefs();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('JSON inválido')),
        );
      }
    }
  }

  Future<void> _blockIp(String ip, {String reason = 'admin_block'}) async {
    try {
      await _db.collection('blocked_ips').doc(ip).set({
        'blockedAt': FieldValue.serverTimestamp(),
        'reason': reason,
        'blockedBy': 'admin_manual',
      });
      setState(() {
        _history.insert(
          0,
          '${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())} — IP bloqueada: $ip',
        );
      });
      await _savePrefs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('IP bloqueada')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error bloqueando IP: $e')),
        );
      }
    }
  }

  Future<void> _blockDevice(String device, {String reason = 'admin_block'}) async {
    try {
      final id = device.hashCode.toString();
      await _db.collection('blocked_devices').doc(id).set({
        'deviceLabel': device,
        'blockedAt': FieldValue.serverTimestamp(),
        'reason': reason,
        'blockedBy': 'admin_manual',
      });
      setState(() {
        _history.insert(
          0,
          '${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())} — Device bloqueado: $device',
        );
      });
      await _savePrefs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dispositivo bloqueado')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error bloqueando dispositivo: $e')),
        );
      }
    }
  }

  Widget _logsWidget({int limit = 50}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('access_logs')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No hay eventos registrados.'),
          );
        }

        final docs = snap.data!.docs;

        final rows = docs.map((d) {
          final data = d.data();
          final ts = data['timestamp'] as Timestamp?;
          final fecha = ts != null ? DateFormat.yMd().add_Hm().format(ts.toDate()) : '-';
          final ip = (data['ip'] ?? '-') as String;
          final device = (data['device'] ?? '-') as String;
          final user = (data['username'] ?? data['userId'] ?? '-') as String;
          final route = (data['route'] ?? '-') as String;
          final action = (data['action'] ?? '-') as String;
          final risk = (data['riskScore'] ?? 0).toString();
          final flags = (data['suspiciousFlags'] ?? []).join(', ');

          return DataRow(cells: [
            DataCell(Text(fecha)),
            DataCell(Text(ip)),
            DataCell(SizedBox(width: 160, child: Text(device, overflow: TextOverflow.ellipsis))),
            DataCell(SizedBox(width: 120, child: Text(user, overflow: TextOverflow.ellipsis))),
            DataCell(SizedBox(width: 120, child: Text(route, overflow: TextOverflow.ellipsis))),
            DataCell(Text(action)),
            DataCell(Text(risk)),
            DataCell(
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'Ver flags',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Detalles de evento'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('IP: $ip'),
                          Text('Device: $device'),
                          Text('Usuario: $user'),
                          Text('Ruta: $route'),
                          Text('Acción: $action'),
                          const SizedBox(height: 8),
                          Text('Flags: $flags'),
                        ],
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            final ok = await _confirmDialog('Bloquear IP', 'Bloquear IP $ip?');
                            if (ok == true) await _blockIp(ip);
                          },
                          child: const Text('Bloquear IP'),
                        ),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            final ok = await _confirmDialog('Bloquear dispositivo', 'Bloquear dispositivo "$device"?');
                            if (ok == true) await _blockDevice(device);
                          },
                          child: const Text('Bloquear dispositivo'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ]);
        }).toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Fecha')),
              DataColumn(label: Text('IP')),
              DataColumn(label: Text('Dispositivo')),
              DataColumn(label: Text('Usuario')),
              DataColumn(label: Text('Ruta')),
              DataColumn(label: Text('Acción')),
              DataColumn(label: Text('Risk')),
              DataColumn(label: Text('Acciones')),
            ],
            rows: rows,
          ),
        );
      },
    );
  }

  Widget _buildContent() {
    final titleStyle = Theme.of(context).textTheme.titleLarge ??
        const TextStyle(fontSize: 18, fontWeight: FontWeight.w600);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Seguridad', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),

        SwitchListTile(
          title: const Text('Autenticación 2FA'),
          subtitle: const Text('Protege tu cuenta con un segundo factor (ej. app autenticadora)'),
          value: _twoFA,
          onChanged: (v) => setState(() => _twoFA = v),
          activeColor: _kEduProBlue,
        ),

        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
              onPressed: _savePrefs,
              icon: const Icon(Icons.save),
              label: const Text('Guardar cambios'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await _confirmDialog(
                  'Restaurar valores por defecto',
                  '¿Deseas restaurar la configuración de seguridad por defecto?',
                );
                if (ok == true) {
                  setState(() {
                    _twoFA = false;
                    _devices = ['Firefox – Windows', 'Safari – iOS'];
                    _ips = ['192.168.1.100', '203.0.113.42'];
                    _history = [
                      '2025-05-07 10:15 — Inicio de sesión exitoso',
                      '2025-05-06 22:03 — Intento fallido (IP 203.0.113.5)',
                      '2025-05-05 14:27 — Cambio de contraseña',
                    ];
                  });
                  await _savePrefs();
                }
              },
              icon: const Icon(Icons.restore),
              label: const Text('Restaurar por defecto'),
            ),
            const SizedBox(width: 12),
            PopupMenuButton<String>(
              tooltip: 'Más opciones',
              onSelected: (t) async {
                if (t == 'export') await _exportConfig();
                if (t == 'import') await _importConfigFromClipboard();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'export', child: Text('Exportar configuración (copiar JSON)')),
                PopupMenuItem(value: 'import', child: Text('Importar desde portapapeles (JSON)')),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.more_horiz),
                    SizedBox(width: 8),
                    Text('Más'),
                  ],
                ),
              ),
            ),
          ],
        ),

        const Divider(height: 24),

        ExpansionTile(
          title: const Text('Dispositivos confiables'),
          subtitle: Text('${_devices.length} guardados'),
          children: [
            for (var d in List<String>.from(_devices))
              ListTile(
                dense: true,
                title: Text(d),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () async {
                    final ok = await _confirmDialog('Eliminar dispositivo', '¿Eliminar "$d" de la lista?');
                    if (ok == true) {
                      setState(() => _devices.remove(d));
                      await _savePrefs();
                    }
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _deviceController,
                      decoration: const InputDecoration(
                        labelText: 'Nuevo dispositivo (ej. Chrome – Windows)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (val) async {
                        final v = val.trim();
                        if (v.isEmpty) return;
                        setState(() => _devices.add(v));
                        _deviceController.clear();
                        await _savePrefs();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
                    onPressed: () async {
                      final v = _deviceController.text.trim();
                      if (v.isEmpty) return;
                      setState(() {
                        _devices.add(v);
                        _deviceController.clear();
                      });
                      await _savePrefs();
                    },
                    child: const Text('Agregar'),
                  ),
                ],
              ),
            ),
          ],
        ),

        const Divider(height: 24),

        ExpansionTile(
          title: const Text('IPs permitidas'),
          subtitle: Text('${_ips.length} registradas'),
          children: [
            for (var ip in List<String>.from(_ips))
              ListTile(
                dense: true,
                title: Text(ip),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () async {
                    final ok = await _confirmDialog('Eliminar IP', '¿Eliminar la IP $ip?');
                    if (ok == true) {
                      setState(() => _ips.remove(ip));
                      await _savePrefs();
                    }
                  },
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
                        labelText: 'Nueva IP (IPv4)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
                    onPressed: () async {
                      final ip = _ipController.text.trim();
                      if (ip.isEmpty) return;
                      if (!_isValidIp(ip)) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('IP inválida (usa formato IPv4)')),
                          );
                        }
                        return;
                      }
                      if (_ips.contains(ip)) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('IP ya está en la lista')),
                          );
                        }
                        return;
                      }
                      setState(() {
                        _ips.add(ip);
                        _ipController.clear();
                      });
                      await _savePrefs();
                    },
                    child: const Text('Agregar'),
                  ),
                ],
              ),
            ),
          ],
        ),

        const Divider(height: 24),

        ExpansionTile(
          title: const Text('Historial de acceso (local)'),
          children: [
            for (final h in List<String>.from(_history)) ListTile(dense: true, title: Text(h)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: () async {
                      final ok = await _confirmDialog('Borrar historial', '¿Deseas borrar todo el historial local?');
                      if (ok == true) {
                        setState(() => _history.clear());
                        await _savePrefs();
                      }
                    },
                    child: const Text('Borrar historial'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
                    onPressed: () {
                      setState(() {
                        final now = DateTime.now();
                        final pretty =
                            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
                            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
                        _history.insert(0, '$pretty — Evento simulado');
                      });
                      _savePrefs();
                    },
                    child: const Text('Simular evento'),
                  ),
                ],
              ),
            ),
          ],
        ),

        const Divider(height: 24),

        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Logs globales (Firestore)', style: titleStyle),
        ),
        const SizedBox(height: 8),

        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('Últimos eventos:'),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Información'),
                          content: const Text('La tabla muestra eventos. Desde ahí puedes bloquear IPs o dispositivos.'),
                          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
                        ),
                      ),
                      child: const Text('¿Cómo funciona?'),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: _kEduProBlue),
                      onPressed: () => _db.collection('access_logs').limit(1).get().then((_) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Conectado a Firestore')));
                        }
                      }).catchError((e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error conexión Firestore: $e')));
                        }
                      }),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Probar conexión'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: _logsWidget(limit: 100),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final routeNow = ModalRoute.of(context)?.settings.name ?? currentRoute;
    void go(String r) {
      if (r != routeNow) Navigator.pushReplacementNamed(context, r);
    }

    Widget wrappedContent() {
      return Card(
        color: _kCardBg,
        margin: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 0,
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
              backgroundColor: _kEduProBlue,
              child: SidebarMenu(currentRoute: currentRoute, onItemSelected: go),
            )
          : null,
      body: isMobile
          ? Column(
              children: [
                ConfigMenu(selectedKey: selectedKey, onItemSelected: go),
                Expanded(child: wrappedContent()),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 260,
                  color: _kEduProBlue,
                  child: SidebarMenu(currentRoute: currentRoute, onItemSelected: go),
                ),

                // ✅ borde azul + submenú blanco (igual a Branding)
                Container(
                  width: 286, // 6px borde + 280 menú
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(left: BorderSide(color: _kEduProBlue, width: 6)),
                  ),
                  child: ConfigMenu(selectedKey: selectedKey, onItemSelected: go),
                ),

                const SizedBox(width: 24),
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
