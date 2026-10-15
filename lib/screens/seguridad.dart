// lib/screens/seguridad.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:edupro/services/edupro_trusted_device_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../widgets/sidebar_menu.dart';
import '../widgets/config_menu.dart';
import '../widgets/team_section_navigation.dart';

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

  bool _twoFA = false;
  List<String> _devices = <String>[];
  List<Map<String, String>> _deviceEntries = <Map<String, String>>[];
  List<String> _ips = <String>[];
  List<String> _history = <String>[];
  List<String> _blockedIps = <String>[];
  List<String> _blockedDevices = <String>[];
  List<Map<String, String>> _pendingDeviceEntries = <Map<String, String>>[];
  String? _currentDeviceId;
  String? _currentDeviceLabel;
  bool _currentDeviceLoading = true;

  final _ipController = TextEditingController();
  final _deviceController = TextEditingController();
  bool _loading = true;

  // Firestore
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadSecurityState();
    _loadCurrentDeviceIdentity();
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
      leading:
          isMobile
              ? null
              : TeamSectionNavigation.backButton(
                context,
                targetRoute: '/configuracion',
                color: Colors.white,
              ),
      iconTheme: const IconThemeData(color: Colors.white),
      title: const SizedBox.shrink(),
      actions: [
        if (isMobile)
          TeamSectionNavigation.backButton(
            context,
            targetRoute: '/configuracion',
            color: Colors.white,
          ),
        if (!isMobile)
          const Center(
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

  DocumentReference<Map<String, dynamic>> _securityDocRef() {
    return _db.collection('app_config').doc('security');
  }

  String _timestampLabel() {
    final now = DateTime.now();
    return DateFormat('yyyy-MM-dd HH:mm').format(now);
  }

  List<Map<String, String>> _normalizeDeviceEntries(dynamic rawEntries) {
    if (rawEntries is List) {
      final parsed =
          rawEntries
              .map((entry) {
                if (entry is Map) {
                  final deviceId = (entry['deviceId'] ?? '').toString().trim();
                  final deviceLabel =
                      (entry['deviceLabel'] ?? entry['label'] ?? '')
                          .toString()
                          .trim();
                  if (deviceId.isEmpty || deviceLabel.isEmpty) return null;
                  return <String, String>{
                    'deviceId': deviceId,
                    'deviceLabel': deviceLabel,
                  };
                }
                return null;
              })
              .whereType<Map<String, String>>()
              .toList();
      if (parsed.isNotEmpty) return parsed;
    }

    if (rawEntries is List) {
      return rawEntries
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .map(
            (value) => <String, String>{
              'deviceId': value,
              'deviceLabel': value,
            },
          )
          .toList();
    }

    return <Map<String, String>>[];
  }

  void _syncDeviceLabelsFromEntries() {
    _devices =
        _deviceEntries
            .map((entry) => (entry['deviceLabel'] ?? '').trim())
            .where((label) => label.isNotEmpty)
            .toList();
  }

  List<Map<String, String>> _normalizePendingDeviceEntries(dynamic rawEntries) {
    if (rawEntries is! List) return <Map<String, String>>[];
    return rawEntries
        .map((entry) {
          if (entry is! Map) return null;
          final deviceId = (entry['deviceId'] ?? '').toString().trim();
          final deviceLabel =
              (entry['deviceLabel'] ?? entry['label'] ?? '').toString().trim();
          if (deviceId.isEmpty || deviceLabel.isEmpty) return null;
          return <String, String>{
            'deviceId': deviceId,
            'deviceLabel': deviceLabel,
            'audience': (entry['audience'] ?? '').toString().trim(),
            'schoolId': (entry['schoolId'] ?? '').toString().trim(),
            'lastAttemptAt': (entry['lastAttemptAt'] ?? '').toString().trim(),
          };
        })
        .whereType<Map<String, String>>()
        .toList();
  }

  bool get _currentDeviceTrusted {
    final currentId = (_currentDeviceId ?? '').trim();
    if (currentId.isEmpty) return false;
    return _deviceEntries.any((entry) => entry['deviceId'] == currentId);
  }

  Future<void> _loadCurrentDeviceIdentity() async {
    try {
      final identity = await EduProTrustedDeviceService.currentIdentity();
      if (!mounted) return;
      setState(() {
        _currentDeviceId = identity.deviceId;
        _currentDeviceLabel = identity.deviceLabel;
        _currentDeviceLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _currentDeviceLoading = false);
    }
  }

  List<String> _historyWithEntry(String message) {
    final next = <String>['${_timestampLabel()} — $message', ..._history];
    if (next.length > 80) {
      return next.take(80).toList();
    }
    return next;
  }

  Future<void> _saveSecurityState({
    bool showSavedMessage = true,
    String? historyEntry,
  }) async {
    _syncDeviceLabelsFromEntries();
    final nextHistory =
        historyEntry == null
            ? List<String>.from(_history)
            : _historyWithEntry(historyEntry);

    await _securityDocRef().set({
      'twoFAEnabled': _twoFA,
      'trustedDevices': _devices,
      'trustedDeviceEntries': _deviceEntries,
      'allowedIps': _ips,
      'securityHistory': nextHistory,
      'blockedIps': _blockedIps,
      'blockedDevices': _blockedDevices,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (historyEntry != null && mounted) {
      setState(() => _history = nextHistory);
    }

    if (showSavedMessage && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ajustes de seguridad guardados')),
      );
    }
  }

  Future<void> _savePrefs() async {
    await _saveSecurityState(showSavedMessage: false);
  }

  Future<void> _loadSecurityState() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }
    try {
      final doc = await _securityDocRef().get();
      final data = doc.data() ?? const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _twoFA = data['twoFAEnabled'] == true;
        _deviceEntries = _normalizeDeviceEntries(
          data['trustedDeviceEntries'] ??
              data['trustedDevices'] ??
              const <String>[],
        );
        _syncDeviceLabelsFromEntries();
        _ips = List<String>.from(data['allowedIps'] ?? const <String>[]);
        _history = List<String>.from(
          data['securityHistory'] ?? const <String>[],
        );
        _blockedIps = List<String>.from(data['blockedIps'] ?? const <String>[]);
        _blockedDevices = List<String>.from(
          data['blockedDevices'] ?? const <String>[],
        );
        _pendingDeviceEntries = _normalizePendingDeviceEntries(
          data['pendingTrustedDeviceEntries'] ?? const <dynamic>[],
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _twoFA = false;
        _devices = <String>[];
        _deviceEntries = <Map<String, String>>[];
        _ips = <String>[];
        _history = <String>[];
        _blockedIps = <String>[];
        _blockedDevices = <String>[];
        _pendingDeviceEntries = <Map<String, String>>[];
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
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
      builder:
          (ctx) => AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: _blueButtonStyle(),
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
      'trustedDeviceEntries': _deviceEntries,
      'ips': _ips,
      'history': _history,
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(map);
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuración copiada al portapapeles (JSON)'),
        ),
      );
    }
  }

  Future<void> _importConfigFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text ?? '';
    if (text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Portapapeles vacío')));
      }
      return;
    }
    try {
      final Map<String, dynamic> map = jsonDecode(text);
      setState(() {
        _twoFA = map['twoFAEnabled'] == true || map['twoFA'] == true;
        _deviceEntries = _normalizeDeviceEntries(
          map['trustedDeviceEntries'] ??
              map['trustedDevices'] ??
              map['devices'] ??
              const <String>[],
        );
        _syncDeviceLabelsFromEntries();
        _ips = List<String>.from(
          map['allowedIps'] ?? map['ips'] ?? const <String>[],
        );
        _history = List<String>.from(
          map['securityHistory'] ?? map['history'] ?? const <String>[],
        );
        _blockedIps = List<String>.from(map['blockedIps'] ?? const <String>[]);
        _blockedDevices = List<String>.from(
          map['blockedDevices'] ?? const <String>[],
        );
        _pendingDeviceEntries = _normalizePendingDeviceEntries(
          map['pendingTrustedDeviceEntries'] ?? const <dynamic>[],
        );
      });
      await _saveSecurityState(
        historyEntry: 'Configuracion importada desde portapapeles',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('JSON inválido')));
      }
    }
  }

  Future<void> _blockIpLegacy(
    String ip, {
    String reason = 'admin_block',
  }) async {
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('IP bloqueada')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error bloqueando IP: $e')));
      }
    }
  }

  Future<void> _blockDeviceLegacy(
    String device, {
    String reason = 'admin_block',
  }) async {
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Dispositivo bloqueado')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error bloqueando dispositivo: $e')),
        );
      }
    }
  }

  Future<void> _blockIp(String ip) async {
    if (_blockedIps.contains(ip)) return;
    setState(() => _blockedIps = <String>[ip, ..._blockedIps]);
    try {
      await _saveSecurityState(
        showSavedMessage: false,
        historyEntry: 'IP bloqueada manualmente: $ip',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('IP bloqueada')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _blockedIps.remove(ip));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error bloqueando IP: $e')));
    }
  }

  Future<void> _blockDevice(String device) async {
    if (_blockedDevices.contains(device)) return;
    setState(() => _blockedDevices = <String>[device, ..._blockedDevices]);
    try {
      await _saveSecurityState(
        showSavedMessage: false,
        historyEntry: 'Dispositivo bloqueado manualmente: $device',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Dispositivo bloqueado')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _blockedDevices.remove(device));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error bloqueando dispositivo: $e')),
      );
    }
  }

  Future<void> _addCurrentTrustedDevice() async {
    final deviceId = (_currentDeviceId ?? '').trim();
    final deviceLabel = (_currentDeviceLabel ?? '').trim();
    if (deviceId.isEmpty || deviceLabel.isEmpty) return;
    if (_deviceEntries.any((entry) => entry['deviceId'] == deviceId)) return;

    setState(() {
      _deviceEntries = <Map<String, String>>[
        <String, String>{'deviceId': deviceId, 'deviceLabel': deviceLabel},
        ..._deviceEntries,
      ];
      _syncDeviceLabelsFromEntries();
    });

    try {
      await _saveSecurityState(
        showSavedMessage: false,
        historyEntry: 'Dispositivo confiable agregado: $deviceLabel',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dispositivo actual agregado como confiable'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deviceEntries.removeWhere((entry) => entry['deviceId'] == deviceId);
        _syncDeviceLabelsFromEntries();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar el dispositivo: $e')),
      );
    }
  }

  Future<void> _removeTrustedDevice(Map<String, String> entry) async {
    final deviceId = (entry['deviceId'] ?? '').trim();
    final deviceLabel = (entry['deviceLabel'] ?? '').trim();
    if (deviceId.isEmpty) return;

    setState(() {
      _deviceEntries.removeWhere((row) => row['deviceId'] == deviceId);
      _syncDeviceLabelsFromEntries();
    });

    try {
      await _saveSecurityState(
        showSavedMessage: false,
        historyEntry: 'Dispositivo confiable eliminado: $deviceLabel',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deviceEntries = <Map<String, String>>[entry, ..._deviceEntries];
        _syncDeviceLabelsFromEntries();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar el dispositivo: $e')),
      );
    }
  }

  Future<void> _approvePendingDevice(Map<String, String> entry) async {
    final deviceId = (entry['deviceId'] ?? '').trim();
    final deviceLabel = (entry['deviceLabel'] ?? '').trim();
    if (deviceId.isEmpty || deviceLabel.isEmpty) return;

    if (!_deviceEntries.any((row) => row['deviceId'] == deviceId)) {
      _deviceEntries = <Map<String, String>>[
        <String, String>{'deviceId': deviceId, 'deviceLabel': deviceLabel},
        ..._deviceEntries,
      ];
    }
    _pendingDeviceEntries.removeWhere((row) => row['deviceId'] == deviceId);

    setState(() {
      _syncDeviceLabelsFromEntries();
    });

    try {
      await _securityDocRef().set({
        'trustedDevices': _devices,
        'trustedDeviceEntries': _deviceEntries,
        'pendingTrustedDeviceEntries': _pendingDeviceEntries,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _saveSecurityState(
        showSavedMessage: false,
        historyEntry: 'Dispositivo aprobado como confiable: $deviceLabel',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Dispositivo aprobado')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo aprobar el dispositivo: $e')),
      );
      await _loadSecurityState();
    }
  }

  Future<void> _discardPendingDevice(Map<String, String> entry) async {
    final deviceId = (entry['deviceId'] ?? '').trim();
    final deviceLabel = (entry['deviceLabel'] ?? '').trim();
    if (deviceId.isEmpty) return;

    setState(() {
      _pendingDeviceEntries.removeWhere((row) => row['deviceId'] == deviceId);
    });

    try {
      await _securityDocRef().set({
        'pendingTrustedDeviceEntries': _pendingDeviceEntries,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _saveSecurityState(
        showSavedMessage: false,
        historyEntry: 'Solicitud de dispositivo descartada: $deviceLabel',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo descartar el dispositivo: $e')),
      );
      await _loadSecurityState();
    }
  }

  ButtonStyle _blueButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: _kEduProBlue,
      foregroundColor: Colors.white,
      disabledBackgroundColor: _kEduProBlue.withOpacity(0.55),
      disabledForegroundColor: Colors.white70,
    );
  }

  Widget _logsWidget({int limit = 50}) {
    final entries = _history.take(limit).toList();
    return Padding(
      padding: const EdgeInsets.all(8),
      child:
          entries.isEmpty
              ? const Text('No hay eventos reales registrados en seguridad.')
              : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:
                    entries
                        .map(
                          (entry) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.history_rounded),
                            title: Text(entry),
                          ),
                        )
                        .toList(),
              ),
    );
  }

  Widget _logsWidgetLegacy({int limit = 50}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream:
          _db
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
        if (snap.hasError) {
          final msg = snap.error.toString();
          final permissionDenied =
              msg.contains('permission-denied') ||
              msg.contains('insufficient permissions');
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              permissionDenied
                  ? 'Los logs globales no estan habilitados para lectura con la configuracion actual de Firestore.'
                  : 'No se pudieron leer los logs globales: $msg',
            ),
          );
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No hay eventos registrados.'),
          );
        }

        final docs = snap.data!.docs;

        final rows =
            docs.map((d) {
              final data = d.data();
              final ts = data['timestamp'] as Timestamp?;
              final fecha =
                  ts != null
                      ? DateFormat.yMd().add_Hm().format(ts.toDate())
                      : '-';
              final ip = (data['ip'] ?? '-') as String;
              final device = (data['device'] ?? '-') as String;
              final user =
                  (data['username'] ?? data['userId'] ?? '-') as String;
              final route = (data['route'] ?? '-') as String;
              final action = (data['action'] ?? '-') as String;
              final risk = (data['riskScore'] ?? 0).toString();
              final flags = (data['suspiciousFlags'] ?? []).join(', ');

              return DataRow(
                cells: [
                  DataCell(Text(fecha)),
                  DataCell(Text(ip)),
                  DataCell(
                    SizedBox(
                      width: 160,
                      child: Text(device, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 120,
                      child: Text(user, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  DataCell(
                    SizedBox(
                      width: 120,
                      child: Text(route, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  DataCell(Text(action)),
                  DataCell(Text(risk)),
                  DataCell(
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      tooltip: 'Ver flags',
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder:
                              (_) => AlertDialog(
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
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cerrar'),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      Navigator.pop(context);
                                      final ok = await _confirmDialog(
                                        'Bloquear IP',
                                        'Bloquear IP $ip?',
                                      );
                                      if (ok == true) await _blockIp(ip);
                                    },
                                    child: const Text('Bloquear IP'),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      Navigator.pop(context);
                                      final ok = await _confirmDialog(
                                        'Bloquear dispositivo',
                                        'Bloquear dispositivo "$device"?',
                                      );
                                      if (ok == true)
                                        await _blockDevice(device);
                                    },
                                    child: const Text('Bloquear dispositivo'),
                                  ),
                                ],
                              ),
                        );
                      },
                    ),
                  ),
                ],
              );
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
    final titleStyle =
        Theme.of(context).textTheme.titleLarge ??
        const TextStyle(fontSize: 18, fontWeight: FontWeight.w600);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Seguridad',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),

        SwitchListTile(
          title: const Text('Autenticación 2FA'),
          subtitle: const Text(
            'Protege tu cuenta con un segundo factor (ej. app autenticadora)',
          ),
          value: _twoFA,
          onChanged: (v) => setState(() => _twoFA = v),
          activeColor: _kEduProBlue,
        ),

        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              style: _blueButtonStyle(),
              onPressed:
                  () => _saveSecurityState(
                    historyEntry: 'Configuracion de seguridad actualizada',
                  ),
              icon: const Icon(Icons.save),
              label: const Text('Guardar cambios'),
            ),
            const SizedBox(width: 12),
            PopupMenuButton<String>(
              tooltip: 'Más opciones',
              onSelected: (t) async {
                if (t == 'export') await _exportConfig();
                if (t == 'import') await _importConfigFromClipboard();
              },
              itemBuilder:
                  (_) => const [
                    PopupMenuItem(
                      value: 'export',
                      child: Text('Exportar configuración (copiar JSON)'),
                    ),
                    PopupMenuItem(
                      value: 'import',
                      child: Text('Importar desde portapapeles (JSON)'),
                    ),
                  ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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
          subtitle: Text('${_deviceEntries.length} guardados'),
          children: [
            ListTile(
              leading: const Icon(Icons.devices_rounded),
              title: Text(
                _currentDeviceLoading
                    ? 'Detectando dispositivo actual...'
                    : (_currentDeviceLabel ??
                        'No se pudo detectar el dispositivo'),
              ),
              subtitle: Text(
                _currentDeviceTrusted
                    ? 'Este dispositivo ya está marcado como confiable'
                    : 'Úsalo para autorizar el equipo actual con datos reales',
              ),
              trailing: ElevatedButton.icon(
                style: _blueButtonStyle(),
                onPressed:
                    _currentDeviceLoading ||
                            _currentDeviceId == null ||
                            _currentDeviceTrusted
                        ? null
                        : _addCurrentTrustedDevice,
                icon: const Icon(Icons.verified_user_rounded),
                label: Text(
                  _currentDeviceTrusted ? 'Confiado' : 'Confiar este equipo',
                ),
              ),
            ),
            const Divider(height: 1),
            for (final entry in List<Map<String, String>>.from(_deviceEntries))
              ListTile(
                dense: true,
                leading: const Icon(Icons.laptop_chromebook_rounded),
                title: Text((entry['deviceLabel'] ?? '').trim()),
                subtitle: Text(
                  'ID: ${(entry['deviceId'] ?? '').trim().substring(0, ((entry['deviceId'] ?? '').trim().length < 12) ? (entry['deviceId'] ?? '').trim().length : 12)}...',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () async {
                    final label = (entry['deviceLabel'] ?? '').trim();
                    final ok = await _confirmDialog(
                      'Eliminar dispositivo',
                      '¿Eliminar "$label" de la lista de dispositivos confiables?',
                    );
                    if (ok == true) {
                      await _removeTrustedDevice(entry);
                    }
                  },
                ),
              ),
            if (_deviceEntries.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Aún no hay dispositivos confiables registrados. Si la lista queda vacía, no se aplicará restricción por dispositivo.',
                  ),
                ),
              )
            else
              const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Cuando esta lista tiene equipos, solo esos dispositivos podrán entrar a admin general, admin escolar y docentes.',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            ),
          ],
        ),

        const Divider(height: 24),

        ExpansionTile(
          title: const Text('Dispositivos pendientes por aprobar'),
          subtitle: Text('${_pendingDeviceEntries.length} detectados'),
          initiallyExpanded: _pendingDeviceEntries.isNotEmpty,
          children: [
            if (_pendingDeviceEntries.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'No hay equipos nuevos pendientes. Cuando un dispositivo no confiable intente entrar, aparecerá aquí.',
                  ),
                ),
              )
            else
              for (final entry in List<Map<String, String>>.from(
                _pendingDeviceEntries,
              ))
                ListTile(
                  leading: const Icon(Icons.device_unknown_rounded),
                  title: Text((entry['deviceLabel'] ?? '').trim()),
                  subtitle: Text(
                    [
                      if ((entry['audience'] ?? '').trim().isNotEmpty)
                        'Acceso: ${(entry['audience'] ?? '').trim()}',
                      if ((entry['schoolId'] ?? '').trim().isNotEmpty)
                        'Colegio: ${(entry['schoolId'] ?? '').trim()}',
                    ].join(' • '),
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => _discardPendingDevice(entry),
                        child: const Text('Descartar'),
                      ),
                      ElevatedButton(
                        style: _blueButtonStyle(),
                        onPressed: () => _approvePendingDevice(entry),
                        child: const Text('Aprobar'),
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
                    final ok = await _confirmDialog(
                      'Eliminar IP',
                      '¿Eliminar la IP $ip?',
                    );
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
                    style: _blueButtonStyle(),
                    onPressed: () async {
                      final ip = _ipController.text.trim();
                      if (ip.isEmpty) return;
                      if (!_isValidIp(ip)) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('IP inválida (usa formato IPv4)'),
                            ),
                          );
                        }
                        return;
                      }
                      if (_ips.contains(ip)) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('IP ya está en la lista'),
                            ),
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
          title: const Text('Historial real de seguridad'),
          children: [
            for (final h in List<String>.from(_history))
              ListTile(dense: true, title: Text(h)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: () async {
                      final ok = await _confirmDialog(
                        'Borrar historial',
                        'Deseas borrar todo el historial real guardado?',
                      );
                      if (ok == true) {
                        setState(() => _history.clear());
                        await _saveSecurityState(showSavedMessage: false);
                      }
                    },
                    child: const Text('Borrar historial'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kEduProBlue,
                    ),
                    onPressed: () {
                      return;
                      setState(() {
                        final now = DateTime.now();
                        final pretty =
                            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
                            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
                        _history.insert(0, '$pretty — Evento simulado');
                      });
                      _savePrefs();
                    },
                    child: const Text('Solo lectura'),
                  ),
                ],
              ),
            ),
          ],
        ),

        const Divider(height: 24),

        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text('Estado real en Firestore', style: titleStyle),
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
                      style: _blueButtonStyle(),
                      onPressed:
                          () => showDialog(
                            context: context,
                            builder:
                                (_) => AlertDialog(
                                  title: const Text('Información'),
                                  content: const Text(
                                    'La tabla muestra eventos. Desde ahí puedes bloquear IPs o dispositivos.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Cerrar'),
                                    ),
                                  ],
                                ),
                          ),
                      child: const Text('¿Cómo funciona?'),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      style: _blueButtonStyle(),
                      onPressed:
                          () => _securityDocRef()
                              .get()
                              .then((_) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Conectado a Firestore y configuracion de seguridad disponible',
                                      ),
                                    ),
                                  );
                                }
                              })
                              .catchError((e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Error conexión Firestore: $e',
                                      ),
                                    ),
                                  );
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
      return Scaffold(
        appBar: _buildTopBar(isMobile: isMobile),
        body: const Center(child: CircularProgressIndicator()),
      );
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
      drawer:
          isMobile
              ? Drawer(
                backgroundColor: _kEduProBlue,
                child: SidebarMenu(
                  currentRoute: currentRoute,
                  onItemSelected: go,
                ),
              )
              : null,
      body:
          isMobile
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
                    child: SidebarMenu(
                      currentRoute: currentRoute,
                      onItemSelected: go,
                    ),
                  ),

                  // ✅ borde azul + submenú blanco (igual a Branding)
                  Container(
                    width: 286, // 6px borde + 280 menú
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        left: BorderSide(color: _kEduProBlue, width: 6),
                      ),
                    ),
                    child: ConfigMenu(
                      selectedKey: selectedKey,
                      onItemSelected: go,
                    ),
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
