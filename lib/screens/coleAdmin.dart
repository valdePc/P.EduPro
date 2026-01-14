// lib/screens/coleAdmin.dart
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

class ColeAdminScreen extends StatefulWidget {
  const ColeAdminScreen({super.key});

  @override
  State<ColeAdminScreen> createState() => _ColeAdminScreenState();
}

class _ColeAdminScreenState extends State<ColeAdminScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// ⚠️ CAMBIA ESTA REGIÓN si tus Functions están en otra (ej: us-east1)
  static const String _functionsRegion = 'us-central1';
  late final FirebaseFunctions _fn =
      FirebaseFunctions.instanceFor(region: _functionsRegion);

  bool _initDone = false;
  bool _loading = true;

  Escuela? _escuela;
  late String _schoolIdPrimary;
  late String _schoolIdAlt;
  late String _schoolId; // el que realmente existe en Firestore

  Map<String, dynamic>? _schoolData;

  String _search = '';

  // ------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------
  String _normalizeSchoolIdLikeAGrados(Escuela e) {
    final raw = (e.nombre ?? 'school-${e.hashCode}').toString();
    var normalized = raw
        .replaceAll(RegExp(r'https?:\/\/'), '')
        .replaceAll(RegExp(r'\/\/+'), '/');
    normalized = normalized
        .replaceAll('/', '_')
        .replaceAll(RegExp(r'[^A-Za-z0-9\-_]'), '');
    if (normalized.isEmpty) normalized = 'school-${e.hashCode}';
    return normalized;
  }

  DateTime? _asDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '—';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = d.year.toString();
    return '$dd/$mm/$yy';
  }

  Random _rng() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  String _generateTempPassword({int length = 10}) {
    const chars =
        'ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789@#%';
    final r = _rng();
    return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _refreshSchool() async {
    try {
      final schoolDoc = await _db.collection('schools').doc(_schoolId).get();
      _schoolData = schoolDoc.data();
    } catch (_) {
      // no rompas la pantalla
    }
    if (mounted) setState(() {});
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ------------------------------------------------------------
  // Init / Resolve school doc
  // ------------------------------------------------------------
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initDone) return;
    _initDone = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! Escuela) {
      setState(() => _loading = false);
      return;
    }

    _escuela = args;
    _schoolIdPrimary = normalizeSchoolIdFromEscuela(_escuela!);
    _schoolIdAlt = _normalizeSchoolIdLikeAGrados(_escuela!);
    _schoolId = _schoolIdPrimary;

    _resolveSchoolIdAndLoad();
  }

  Future<void> _resolveSchoolIdAndLoad() async {
    setState(() => _loading = true);

    try {
      if (_schoolIdPrimary == _schoolIdAlt) {
        _schoolId = _schoolIdPrimary;
      } else {
        final d1 = await _db.collection('schools').doc(_schoolIdPrimary).get();
        if (d1.exists) {
          _schoolId = _schoolIdPrimary;
        } else {
          final d2 = await _db.collection('schools').doc(_schoolIdAlt).get();
          _schoolId = d2.exists ? _schoolIdAlt : _schoolIdPrimary;
        }
      }

      final schoolDoc = await _db.collection('schools').doc(_schoolId).get();
      _schoolData = schoolDoc.data();
    } catch (_) {
      // no rompas la pantalla
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------------------------------------------------
  // Cloud Functions (debes tenerlas creadas)
  // ------------------------------------------------------------
  Future<Map<String, dynamic>> _createSchoolAdminAccount({
    required String schoolId,
    required String name,
    required String email,
    required String phone,
    required String tempPassword,
  }) async {
    final callable = _fn.httpsCallable('createSchoolAdminAccount');
    final res = await callable.call(<String, dynamic>{
      'schoolId': schoolId,
      'name': name.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'tempPassword': tempPassword,
    });

    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> _setAdminStatus({
    required String schoolId,
    required String adminUid,
    required String status, // "active" | "paused" | "deleted"
  }) async {
    final callable = _fn.httpsCallable('setSchoolAdminStatus');
    await callable.call(<String, dynamic>{
      'schoolId': schoolId,
      'adminUid': adminUid,
      'status': status,
    });
  }

  // ✅ Admin principal (correo + contraseña)
  Future<Map<String, dynamic>> _upsertSchoolAdmin({
    required String schoolId,
    required String email,
    required String password,
  }) async {
    final callable = _fn.httpsCallable('upsertSchoolAdmin');
    final res = await callable.call(<String, dynamic>{
      'schoolId': schoolId,
      'email': email.trim().toLowerCase(),
      'password': password,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  // ------------------------------------------------------------
  // UI: Acceso principal (correo + clave admin) + clave del colegio
  // ------------------------------------------------------------
  Future<void> _openPrimaryAdminDialog() async {
    final currentEmail = (_schoolData?['adminEmail'] ?? '').toString();
    final emailCtrl = TextEditingController(text: currentEmail);
    final passCtrl = TextEditingController();

    bool show = false;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, st) => AlertDialog(
          title: const Text('Acceso principal • Admin Escolar'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo principal (adminEmail)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passCtrl,
                  obscureText: !show,
                  decoration: InputDecoration(
                    labelText: 'Nueva contraseña (se aplica en Auth)',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(show ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => st(() => show = !show),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '⚠️ Seguridad: esta contraseña NO se guarda en Firestore.\n'
                    'Se aplica por Cloud Function en Firebase Auth.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dlgCtx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(saving ? 'Guardando...' : 'Guardar'),
              onPressed: saving
                  ? null
                  : () async {
                      final email = emailCtrl.text.trim().toLowerCase();
                      final pass = passCtrl.text;

                      if (email.isEmpty || !email.contains('@')) {
                        _snack('Escribe un correo válido.');
                        return;
                      }
                      if (pass.trim().length < 6) {
                        _snack('La contraseña debe tener mínimo 6 caracteres.');
                        return;
                      }

                      st(() => saving = true);

                      try {
                        // 1) Guardar correo en Firestore (esto debe funcionar sí o sí si tienes permisos)
                        await _db.collection('schools').doc(_schoolId).set(
                          {
                            'adminEmail': email,
                            'adminUpdatedAt': FieldValue.serverTimestamp(),
                            // Si falla la Function, lo dejamos explícito:
                            'adminPasswordSet': false,
                          },
                          SetOptions(merge: true),
                        );

                        // Refresca UI aunque la Function falle
                        await _refreshSchool();

                        // 2) Intentar crear/actualizar en Auth (Cloud Function) con TIMEOUT
                        Map<String, dynamic> res;
                        try {
                          res = await _upsertSchoolAdmin(
                            schoolId: _schoolId,
                            email: email,
                            password: pass,
                          ).timeout(const Duration(seconds: 12));
                        } on TimeoutException {
                          if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                          _snack(
                            'Correo guardado ✅ pero la Function se quedó esperando (timeout). '
                            'Revisa región/Logs de Functions.',
                          );
                          return;
                        }

                        final uid = (res['uid'] ?? '').toString();

                        // 3) Marcar como listo
                        await _db.collection('schools').doc(_schoolId).set(
                          {
                            if (uid.isNotEmpty) 'adminUid': uid,
                            'adminPasswordSet': true,
                            'adminUpdatedAt': FieldValue.serverTimestamp(),
                          },
                          SetOptions(merge: true),
                        );

                        await _refreshSchool();

                        if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                        _snack('Acceso principal actualizado ✅');
                      } on FirebaseFunctionsException catch (e) {
                        // Firestore se guardó arriba; esto es solo la parte Auth
                        if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                        _snack(
                          'Correo guardado ✅ pero Auth falló: ${e.message ?? e.code}',
                        );
                      } catch (e) {
                        // Si esto ocurre, casi siempre es PERMISSION_DENIED en Firestore
                        _snack('Error guardando: $e');
                      } finally {
                        if (ctx.mounted) st(() => saving = false);
                      }
                    },
            ),
          ],
        ),
      ),
    );

    emailCtrl.dispose();
    passCtrl.dispose();
  }

  Future<void> _openSchoolPasswordDialog() async {
    final currentPass = (_schoolData?['password'] ?? '').toString();
    final passCtrl = TextEditingController(
      text: currentPass.isNotEmpty ? currentPass : _generateTempPassword(length: 10),
    );

    bool show = false;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, st) => AlertDialog(
          title: const Text('Contraseña del colegio (campo password)'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: passCtrl,
                  obscureText: !show,
                  decoration: InputDecoration(
                    labelText: 'Contraseña del colegio',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: Wrap(
                      spacing: 0,
                      children: [
                        IconButton(
                          tooltip: show ? 'Ocultar' : 'Ver',
                          icon: Icon(show ? Icons.visibility_off : Icons.visibility),
                          onPressed: saving ? null : () => st(() => show = !show),
                        ),
                        IconButton(
                          tooltip: 'Regenerar',
                          icon: const Icon(Icons.refresh),
                          onPressed: saving
                              ? null
                              : () => st(() {
                                    passCtrl.text = _generateTempPassword(length: 10);
                                  }),
                        ),
                        IconButton(
                          tooltip: 'Copiar',
                          icon: const Icon(Icons.copy),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: passCtrl.text.trim()),
                            );
                            _snack('Contraseña copiada');
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Esta contraseña sí se guarda en Firestore dentro del colegio.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dlgCtx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(saving ? 'Guardando...' : 'Guardar'),
              onPressed: saving
                  ? null
                  : () async {
                      final pass = passCtrl.text.trim();
                      if (pass.isEmpty) {
                        _snack('La contraseña no puede estar vacía.');
                        return;
                      }

                      st(() => saving = true);
                      try {
                        await _db.collection('schools').doc(_schoolId).set(
                          {'password': pass},
                          SetOptions(merge: true),
                        );

                        await _refreshSchool();

                        if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                        _snack('Contraseña del colegio actualizada ✅');
                      } catch (e) {
                        _snack('Error guardando: $e');
                      } finally {
                        if (ctx.mounted) st(() => saving = false);
                      }
                    },
            ),
          ],
        ),
      ),
    );

    passCtrl.dispose();
  }

  // ------------------------------------------------------------
  // UI: Add Admin dialog
  // ------------------------------------------------------------
  Future<void> _openAddAdminDialog() async {
    String tempPass = _generateTempPassword(length: 10);

    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final tempCtrl = TextEditingController(text: tempPass);

    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, st) => AlertDialog(
          title: const Text('Agregar administrador'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo (para login)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  readOnly: true,
                  controller: tempCtrl,
                  decoration: InputDecoration(
                    labelText: 'Contraseña provisional',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: Wrap(
                      spacing: 0,
                      children: [
                        IconButton(
                          tooltip: 'Regenerar',
                          icon: const Icon(Icons.refresh),
                          onPressed: saving
                              ? null
                              : () => st(() {
                                    tempPass = _generateTempPassword(length: 10);
                                    tempCtrl.text = tempPass;
                                  }),
                        ),
                        IconButton(
                          tooltip: 'Copiar',
                          icon: const Icon(Icons.copy),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: tempPass));
                            _snack('Contraseña copiada');
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Nota: La contraseña NO se guarda en Firestore.\n'
                    'Solo se crea en Auth y se muestra una vez aquí.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dlgCtx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      final email = emailCtrl.text.trim();
                      final phone = phoneCtrl.text.trim();

                      if (name.isEmpty || email.isEmpty) {
                        _snack('Nombre y correo son obligatorios.');
                        return;
                      }

                      st(() => saving = true);

                      try {
                        final created = await _createSchoolAdminAccount(
                          schoolId: _schoolId,
                          name: name,
                          email: email,
                          phone: phone,
                          tempPassword: tempPass,
                        );

                        final createdEmail = (created['email'] ?? email).toString();

                        if (ctx.mounted) Navigator.pop(dlgCtx);

                        await showDialog<void>(
                          context: context,
                          builder: (c2) => AlertDialog(
                            title: const Text('Admin creado'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Comparte estos datos con el admin:'),
                                const SizedBox(height: 10),
                                SelectableText('Correo: $createdEmail'),
                                const SizedBox(height: 6),
                                SelectableText('Contraseña provisional: $tempPass'),
                                const SizedBox(height: 10),
                                const Text(
                                  'Recomendado: que cambie la contraseña al primer inicio.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: 'Correo: $createdEmail\nClave: $tempPass'),
                                  );
                                  if (c2.mounted) Navigator.pop(c2);
                                },
                                child: const Text('Copiar y cerrar'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(c2),
                                child: const Text('Cerrar'),
                              ),
                            ],
                          ),
                        );
                      } catch (e) {
                        _snack('Error creando admin: $e');
                      } finally {
                        if (mounted) st(() => saving = false);
                      }
                    },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );

    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    tempCtrl.dispose();
  }

  // ------------------------------------------------------------
  // Admin list stream
  // ------------------------------------------------------------
  Stream<List<Map<String, dynamic>>> _adminsStream() {
    return _db
        .collection('schools')
        .doc(_schoolId)
        .collection('admins')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) {
      return snap.docs.map((d) {
        final m = d.data();
        m['__id'] = d.id; // normalmente sería uid
        return m;
      }).toList();
    });
  }

  // ------------------------------------------------------------
  // Row actions
  // ------------------------------------------------------------
  Future<void> _confirmDeleteAdmin(String uid, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminar administrador'),
        content: Text('¿Seguro que deseas eliminar a "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _setAdminStatus(schoolId: _schoolId, adminUid: uid, status: 'deleted');
      _snack('Admin eliminado (ya no puede iniciar sesión).');
    } catch (e) {
      _snack('Error eliminando: $e');
    }
  }

  Future<void> _changeStatus(String uid, String status) async {
    try {
      await _setAdminStatus(schoolId: _schoolId, adminUid: uid, status: status);
      final msg = status == 'active'
          ? 'Admin activado.'
          : status == 'paused'
              ? 'Admin en pausa (no puede iniciar sesión).'
              : 'Admin eliminado.';
      _snack(msg);
    } catch (e) {
      _snack('Error cambiando estado: $e');
    }
  }

  // ------------------------------------------------------------
  // Build
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final escuela = _escuela;

    if (!_initDone || escuela == null) {
      return const Scaffold(
        body: Center(child: Text('No se recibió la escuela.')),
      );
    }

    final createdAt = _asDate(_schoolData?['createdAt'] ?? _schoolData?['createdAtLocal']);
    final schoolNameFromDb = (_schoolData?['name'] ?? _schoolData?['nombre'])?.toString().trim();
    final schoolName = (schoolNameFromDb != null && schoolNameFromDb.isNotEmpty)
        ? schoolNameFromDb
        : escuela.nombre;

    final adminEmail = (_schoolData?['adminEmail'] ?? '').toString().trim();
    final hasAdmin = adminEmail.isNotEmpty && ((_schoolData?['adminPasswordSet'] ?? false) == true);

    final schoolPassword = (_schoolData?['password'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue.shade900,
        title: Text('Administradores • $schoolName'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _openAddAdminDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Agregar Admin'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _HeaderCard(
                    schoolName: schoolName,
                    createdAtText: _formatDate(createdAt),
                  ),
                  const SizedBox(height: 12),

                  // ✅ Acceso principal + contraseña del colegio
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Acceso principal (Admin Escolar)',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  adminEmail.isEmpty ? 'Correo admin: —' : 'Correo admin: $adminEmail',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: hasAdmin ? Colors.green.shade50 : Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  hasAdmin ? 'Listo' : 'Pendiente',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: hasAdmin ? Colors.green.shade900 : Colors.orange.shade900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: _openPrimaryAdminDialog,
                                icon: const Icon(Icons.key),
                                label: Text(adminEmail.isEmpty ? 'Asignar' : 'Cambiar'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Divider(),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  schoolPassword.isEmpty
                                      ? 'Contraseña del colegio: —'
                                      : 'Contraseña del colegio: ••••••••',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _openSchoolPasswordDialog,
                                icon: const Icon(Icons.vpn_key),
                                label: Text(schoolPassword.isEmpty ? 'Asignar' : 'Cambiar'),
                              ),
                              if (schoolPassword.isNotEmpty)
                                IconButton(
                                  tooltip: 'Copiar contraseña del colegio',
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(text: schoolPassword));
                                    _snack('Contraseña del colegio copiada');
                                  },
                                  icon: const Icon(Icons.copy),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar admin por nombre o correo...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 12),

                  Expanded(
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _adminsStream(),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Center(child: Text('Error: ${snap.error}'));
                        }
                        if (!snap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final list = snap.data ?? [];
                        final q = _search.trim().toLowerCase();

                        final filtered = list.where((a) {
                          final name = (a['name'] ?? '').toString().toLowerCase();
                          final email = (a['email'] ?? '').toString().toLowerCase();
                          return q.isEmpty || name.contains(q) || email.contains(q);
                        }).toList();

                        if (filtered.isEmpty) {
                          return const Center(child: Text('No hay administradores.'));
                        }

                        return ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final a = filtered[i];
                            final uid = (a['uid'] ?? a['__id'] ?? '').toString();
                            final name = (a['name'] ?? '—').toString();
                            final email = (a['email'] ?? '—').toString();
                            final phone = (a['phone'] ?? '').toString();
                            final status = (a['status'] ?? 'active').toString();

                            final isDeleted = status == 'deleted';
                            final isPaused = status == 'paused';

                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isDeleted
                                      ? Colors.red.shade200
                                      : isPaused
                                          ? Colors.orange.shade200
                                          : Colors.green.shade200,
                                  child: Icon(
                                    isDeleted
                                        ? Icons.block
                                        : isPaused
                                            ? Icons.pause
                                            : Icons.verified_user,
                                    color: Colors.black87,
                                  ),
                                ),
                                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(email),
                                    if (phone.trim().isNotEmpty) Text(phone),
                                    const SizedBox(height: 6),
                                    Text(
                                      isDeleted
                                          ? 'Estado: Eliminado (sin acceso)'
                                          : isPaused
                                              ? 'Estado: En pausa (sin acceso)'
                                              : 'Estado: Activo (con acceso)',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
                                trailing: Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton(
                                      onPressed: (status == 'active') ? null : () => _changeStatus(uid, 'active'),
                                      child: const Text('Activo'),
                                    ),
                                    TextButton(
                                      onPressed: (status == 'paused') ? null : () => _changeStatus(uid, 'paused'),
                                      child: const Text('En pausa'),
                                    ),
                                    IconButton(
                                      tooltip: 'Eliminar',
                                      onPressed: isDeleted ? null : () => _confirmDeleteAdmin(uid, name),
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 70),
                ],
              ),
            ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final String schoolName;
  final String createdAtText;

  const _HeaderCard({
    required this.schoolName,
    required this.createdAtText,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.blue.shade50,
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Image.asset(
                  'assets/logo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    schoolName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Creado: $createdAtText',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
