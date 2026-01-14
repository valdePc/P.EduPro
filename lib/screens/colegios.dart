// lib/screens/colegios.dart
import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/sidebar_menu.dart' as sidebar;
import 'package:edupro/models/escuela.dart';

class ColegiosScreen extends StatelessWidget {
  const ColegiosScreen({Key? key}) : super(key: key);

  // 🔧 Cambia si tus Functions están en otra región
  static const String _functionsRegion = 'us-central1';

  FirebaseFunctions get _fn => FirebaseFunctions.instanceFor(region: _functionsRegion);

  // =========================
  // Navegación
  // =========================
  void _handleNavigation(BuildContext context, String route) {
    const currentRoute = '/colegios';
    if (route != currentRoute) {
      Navigator.pushReplacementNamed(context, route);
    }
  }

  void _goColeAdmin(BuildContext context, Escuela escuela) {
    Navigator.pushNamed(context, '/coleAdmin', arguments: escuela);
  }

  // =========================
  // Firestore
  // =========================
  Stream<QuerySnapshot<Map<String, dynamic>>> _schoolsStream() {
    return FirebaseFirestore.instance.collection('schools').snapshots();
  }

  int _toMillis(dynamic v) {
    if (v is int) return v;
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    if (v is DateTime) return v.millisecondsSinceEpoch;
    return DateTime.now().millisecondsSinceEpoch;
  }

  Escuela _escuelaFromDoc(String code, Map<String, dynamic> d) {
    final nombre = (d['name'] ?? d['nombre'] ?? '').toString();
    final activo = (d['active'] ?? d['activo'] ?? true) == true;

    final createdAtLocal = _toMillis(d['createdAtLocal'] ?? d['createdAt'] ?? d['fecha']);

    final e = Escuela(
      nombre: nombre,
      adminLink: (d['adminLink'] ?? 'https://edupro.app/admin/$code').toString(),
      profLink: (d['profLink'] ?? 'https://edupro.app/profesores/$code').toString(),
      alumLink: (d['alumLink'] ?? 'https://edupro.app/alumnos/$code').toString(),
      fecha: DateTime.fromMillisecondsSinceEpoch(createdAtLocal),

      // Legacy (compatibilidad)
      password: (d['password'] ?? '').toString(),

      grados: (d['grados'] is List) ? List<String>.from(d['grados']) : <String>[],
    );

    e.activo = activo;
    return e;
  }

  bool _adminPasswordSetFromDoc(Map<String, dynamic> d) {
    return (d['adminPasswordSet'] == true) ||
        ((d['adminUid'] ?? '').toString().trim().isNotEmpty);
  }

  // =========================
  // UX helpers
  // =========================
  void _snack(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    String okText = 'Confirmar',
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(okText),
          ),
        ],
      ),
    );
    return res == true;
  }

  // =========================
  // Seguridad: validaciones
  // =========================
  bool _isValidEmail(String email) {
    final e = email.trim().toLowerCase();
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return re.hasMatch(e);
  }

  bool _isStrongPassword(String p) {
    final s = p;
    if (s.trim().length < 10) return false;
    final hasUpper = RegExp(r'[A-Z]').hasMatch(s);
    final hasLower = RegExp(r'[a-z]').hasMatch(s);
    final hasDigit = RegExp(r'\d').hasMatch(s);
    final hasSymbol = RegExp(r'[^A-Za-z0-9]').hasMatch(s);
    final score = [hasUpper, hasLower, hasDigit, hasSymbol].where((x) => x).length;
    return score >= 3;
  }

  Random _rng() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  String _generateStrongPassword({int length = 14}) {
    const upper = 'ABCDEFGHJKMNPQRSTUVWXYZ';
    const lower = 'abcdefghjkmnpqrstuvwxyz';
    const digits = '23456789';
    const symbols = '@#%&*_-+=!?';
    final all = upper + lower + digits + symbols;

    final r = _rng();

    final chars = <String>[
      upper[r.nextInt(upper.length)],
      lower[r.nextInt(lower.length)],
      digits[r.nextInt(digits.length)],
      symbols[r.nextInt(symbols.length)],
    ];

    while (chars.length < length) {
      chars.add(all[r.nextInt(all.length)]);
    }
    chars.shuffle(r);
    return chars.join();
  }

  Future<void> _copy(
    BuildContext context,
    String text, {
    String okMsg = 'Copiado ✅',
  }) async {
    await Clipboard.setData(ClipboardData(text: text));
    _snack(context, okMsg);
  }

  // =========================
  // Admin creds -> Auth via Cloud Function + Firestore solo email/flags
  // =========================
  Future<void> _editAdminCredsDialog(
    BuildContext context, {
    required String schoolId,
    required String schoolName,
    required String currentEmail,
    required bool adminPasswordSet,
  }) async {
    final emailCtrl = TextEditingController(text: currentEmail);
    final passCtrl = TextEditingController(text: ''); // NO autogenerar
    bool show = false;
    bool loading = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            final emailNow = emailCtrl.text.trim().toLowerCase();
            final passNow = passCtrl.text;
            final passProvided = passNow.trim().isNotEmpty;

            final emailChanged =
                currentEmail.trim().toLowerCase() != emailNow.trim().toLowerCase();

            final needsCloudFunction =
                (!adminPasswordSet) || passProvided || emailChanged;

            return AlertDialog(
              title: Text('Acceso Admin Escolar • $schoolName'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) => setSt(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Correo admin (adminEmail)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        adminPasswordSet
                            ? 'Contraseña actual: Asignada (no visible)'
                            : 'Contraseña actual: No asignada',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: adminPasswordSet ? Colors.green : Colors.orange,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passCtrl,
                      obscureText: !show,
                      onChanged: (_) => setSt(() {}),
                      decoration: InputDecoration(
                        labelText: adminPasswordSet
                            ? 'Nueva contraseña (opcional)'
                            : 'Contraseña (requerida para crear el admin)',
                        helperText: adminPasswordSet
                            ? 'Déjala vacía para mantener la contraseña actual.\n'
                                'Si escribes una nueva, se RESETEA en Auth.'
                            : 'Escribe una contraseña o usa “Generar”.\n'
                                'Guárdala ahora; luego no podrás verla aquí.',
                        border: const OutlineInputBorder(),
                        suffixIcon: Wrap(
                          spacing: 0,
                          children: [
                            IconButton(
                              tooltip: 'Generar',
                              onPressed: loading
                                  ? null
                                  : () => setSt(() {
                                        passCtrl.text =
                                            _generateStrongPassword(length: 14);
                                      }),
                              icon: const Icon(Icons.auto_fix_high),
                            ),
                            if (adminPasswordSet && passProvided)
                              IconButton(
                                tooltip: 'Mantener actual (vaciar)',
                                onPressed: loading
                                    ? null
                                    : () => setSt(() => passCtrl.clear()),
                                icon: const Icon(Icons.undo),
                              ),
                            IconButton(
                              tooltip: show ? 'Ocultar' : 'Ver',
                              onPressed: loading ? null : () => setSt(() => show = !show),
                              icon: Icon(show ? Icons.visibility_off : Icons.visibility),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Seguridad: la contraseña NO se guarda en Firestore.\n'
                      'Se aplica en Firebase Auth mediante Cloud Function.',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: loading ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  icon: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(loading ? 'Guardando...' : 'Guardar'),
                  onPressed: loading
                      ? null
                      : () async {
                          final email = emailCtrl.text.trim().toLowerCase();
                          final pass = passCtrl.text;
                          final passProvidedNow = pass.trim().isNotEmpty;

                          if (!_isValidEmail(email)) {
                            _snack(context, 'Escribe un correo válido.');
                            return;
                          }

                          if (!adminPasswordSet && !passProvidedNow) {
                            _snack(context,
                                'Debes asignar una contraseña para crear el admin por primera vez.');
                            return;
                          }

                          if (passProvidedNow && !_isStrongPassword(pass)) {
                            _snack(
                              context,
                              'Contraseña débil. Usa mínimo 10 caracteres y mezcla letras/números/símbolos.',
                            );
                            return;
                          }

                          final ok = await _confirm(
                            context,
                            title: 'Confirmar cambios',
                            message:
                                'Colegio: $schoolId\n'
                                'Correo: $email\n'
                                'Contraseña: ${passProvidedNow ? 'SE CAMBIA (reset)' : 'se mantiene igual'}\n\n'
                                '¿Deseas continuar?',
                            okText: 'Sí, guardar',
                          );
                          if (!ok) return;

                          setSt(() => loading = true);

                          try {
                            // 1) Firestore: guardar correo SIEMPRE
                            await FirebaseFirestore.instance
                                .collection('schools')
                                .doc(schoolId)
                                .set(
                              {
                                'adminEmail': email,
                                'adminUpdatedAt': FieldValue.serverTimestamp(),
                              },
                              SetOptions(merge: true),
                            );

                            // 2) Si no hay que tocar Auth: cerrar y listo ✅
                            if (!needsCloudFunction) {
                              if (ctx.mounted) Navigator.pop(ctx);
                              _snack(context, 'Listo ✅ (no se tocó la contraseña).');
                              return;
                            }

                            _snack(
                              context,
                              passProvidedNow
                                  ? 'Correo guardado ✅. Actualizando contraseña en Auth...'
                                  : 'Correo guardado ✅. Verificando/actualizando acceso...',
                            );

                            // 3) Cloud Function con timeout REAL
                            final callable = _fn.httpsCallable(
                              'upsertSchoolAdmin',
                              options: HttpsCallableOptions(
                                timeout: const Duration(seconds: 25),
                              ),
                            );

                            final payload = <String, dynamic>{
                              'schoolId': schoolId,
                              'email': email,
                              'adminEmail': email,
                              if (passProvidedNow) ...{
                                'password': pass,
                                'adminPassword': pass,
                              },
                            };

                            final res = await callable.call(payload);

                            final data = (res.data is Map)
                                ? Map<String, dynamic>.from(res.data as Map)
                                : <String, dynamic>{};

                            final adminUid = (data['uid'] ?? '').toString().trim();

                            // 4) Flags en Firestore
                            await FirebaseFirestore.instance
                                .collection('schools')
                                .doc(schoolId)
                                .set(
                              {
                                if (adminUid.isNotEmpty) 'adminUid': adminUid,
                                'adminPasswordSet': true,
                                'adminUpdatedAt': FieldValue.serverTimestamp(),
                              },
                              SetOptions(merge: true),
                            );

                            // 5) Cerrar modal
                            if (ctx.mounted) Navigator.pop(ctx);

                            if (!context.mounted) return;

                            // 6) Mostrar credenciales SOLO si creaste/cambiaste contraseña
                            if (passProvidedNow || !adminPasswordSet) {
                              await showDialog<void>(
                                context: context,
                                builder: (c2) => AlertDialog(
                                  title: const Text('Listo ✅'),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Comparte esto con el Admin Escolar:'),
                                      const SizedBox(height: 10),
                                      SelectableText('Correo: $email'),
                                      const SizedBox(height: 6),
                                      SelectableText('Contraseña: $pass'),
                                      const SizedBox(height: 10),
                                      const Text(
                                        'Recomendado: cambiar contraseña al primer inicio.',
                                        style: TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () async {
                                        await _copy(
                                          c2,
                                          'Correo: $email\nContraseña: $pass',
                                          okMsg: 'Credenciales copiadas ✅',
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
                            } else {
                              _snack(context, 'Correo actualizado ✅ (contraseña se mantuvo).');
                            }
                          } on FirebaseFunctionsException catch (e) {
                            _snack(
                              context,
                              'Auth falló: ${e.code} • ${e.message ?? ''}',
                            );
                          } on TimeoutException {
                            _snack(
                              context,
                              'Auth tardó demasiado (timeout). Reintenta. '
                              'Si pasa siempre, revisa región/logs de Functions.',
                            );
                          } catch (e) {
                            _snack(context, 'Ocurrió un error: $e');
                          } finally {
                            if (ctx.mounted) setSt(() => loading = false);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );

    emailCtrl.dispose();
    passCtrl.dispose();
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 800;
    const String currentRoute = '/colegios';

    return Scaffold(
      drawer: isMobile
          ? Drawer(
              child: Container(
                color: Colors.blue.shade900,
                child: sidebar.SidebarMenu(
                  currentRoute: currentRoute,
                  onItemSelected: (route) => _handleNavigation(context, route),
                ),
              ),
            )
          : null,
      appBar: isMobile
          ? AppBar(title: const Text('EduPro'))
          : PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Container(
                color: Colors.blue.shade900,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: const Text('...',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
      body: isMobile
          ? _buildBodyMobile(context)
          : Row(
              children: [
                Container(
                  width: 220,
                  color: Colors.blue.shade900,
                  child: sidebar.SidebarMenu(
                    currentRoute: currentRoute,
                    onItemSelected: (route) => _handleNavigation(context, route),
                  ),
                ),
                Expanded(child: _buildBodyDesktop(context)),
              ],
            ),
    );
  }

  Widget _buildBodyMobile(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _schoolsStream(),
      builder: (ctx, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No hay colegios registrados'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (ctx2, i) {
            final doc = docs[i];
            final d = doc.data();

            final schoolId = doc.id;
            final nombre = (d['name'] ?? d['nombre'] ?? '').toString();
            final activo = (d['active'] ?? d['activo'] ?? true) == true;
            final adminEmail = (d['adminEmail'] ?? '').toString().trim();

            final adminPasswordSet = _adminPasswordSetFromDoc(d);
            final adminReady = adminEmail.isNotEmpty && adminPasswordSet;

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                title: Text(
                  nombre,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Código: $schoolId\n'
                  'Correo admin: ${adminEmail.isNotEmpty ? adminEmail : '—'}\n'
                  'Acceso admin: ${adminReady ? 'Configurado ✅' : 'Pendiente ⚠️'}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      activo ? Icons.check_circle : Icons.cancel,
                      color: activo ? Colors.green : Colors.red,
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'coleAdmin') {
                          final escuela = _escuelaFromDoc(schoolId, d);
                          _goColeAdmin(context, escuela);
                        } else if (v == 'adminCreds') {
                          await _editAdminCredsDialog(
                            context,
                            schoolId: schoolId,
                            schoolName: nombre,
                            currentEmail: adminEmail,
                            adminPasswordSet: adminPasswordSet,
                          );
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'coleAdmin',
                          child: Text('Abrir coleAdmin'),
                        ),
                        PopupMenuItem(
                          value: 'adminCreds',
                          child: Text('Editar acceso admin'),
                        ),
                      ],
                    ),
                  ],
                ),
                onTap: () {
                  final escuela = _escuelaFromDoc(schoolId, d);
                  _goColeAdmin(context, escuela);
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBodyDesktop(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _schoolsStream(),
      builder: (ctx, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('No hay colegios registrados'));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Colegios',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pushReplacementNamed(context, '/panel'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                    child: const Text('+ Nuevo Colegio'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Colegios')),
                    DataColumn(label: Text('Códigos')),
                    DataColumn(label: Text('Correos administrativo')),
                    DataColumn(label: Text('Estados')),
                    DataColumn(label: Text('Acciones')),
                  ],
                  rows: docs.map((doc) {
                    final d = doc.data();

                    final schoolId = doc.id;
                    final nombre = (d['name'] ?? d['nombre'] ?? '').toString();
                    final activo = (d['active'] ?? d['activo'] ?? true) == true;
                    final adminEmail = (d['adminEmail'] ?? '').toString().trim();
                    final adminPasswordSet = _adminPasswordSetFromDoc(d);

                    return DataRow(cells: [
                      DataCell(
                        InkWell(
                          onTap: () {
                            final escuela = _escuelaFromDoc(schoolId, d);
                            _goColeAdmin(context, escuela);
                          },
                          child: Text(
                            nombre,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                      DataCell(Text(schoolId)),
                      DataCell(
                        InkWell(
                          onTap: () async {
                            await _editAdminCredsDialog(
                              context,
                              schoolId: schoolId,
                              schoolName: nombre,
                              currentEmail: adminEmail,
                              adminPasswordSet: adminPasswordSet,
                            );
                          },
                          child: Text(
                            adminEmail.isEmpty ? '— (click para configurar)' : adminEmail,
                            style: TextStyle(
                              decoration: TextDecoration.underline,
                              color: adminEmail.isEmpty ? Colors.grey : null,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Icon(activo ? Icons.check : Icons.close,
                            color: activo ? Colors.green : Colors.red),
                      ),
                      DataCell(
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Abrir coleAdmin',
                              icon: const Icon(Icons.admin_panel_settings, size: 18),
                              onPressed: () {
                                final escuela = _escuelaFromDoc(schoolId, d);
                                _goColeAdmin(context, escuela);
                              },
                            ),
                            IconButton(
                              tooltip: 'Editar acceso admin',
                              icon: const Icon(Icons.key, size: 18),
                              onPressed: () async {
                                await _editAdminCredsDialog(
                                  context,
                                  schoolId: schoolId,
                                  schoolName: nombre,
                                  currentEmail: adminEmail,
                                  adminPasswordSet: adminPasswordSet,
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Ver',
                              icon: const Icon(Icons.remove_red_eye, size: 18),
                              onPressed: () {
                                final escuela = _escuelaFromDoc(schoolId, d);
                                Navigator.pushNamed(context, '/admincole', arguments: escuela);
                              },
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Editar',
                              icon: const Icon(Icons.edit, size: 18),
                              onPressed: () {
                                final escuela = _escuelaFromDoc(schoolId, d);
                                Navigator.pushNamed(context, '/editarColegio', arguments: escuela);
                              },
                            ),
                          ],
                        ),
                      ),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
