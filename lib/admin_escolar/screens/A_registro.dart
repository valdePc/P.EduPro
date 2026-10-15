// lib/admin_escolar/screens/A_registro.dart
import 'dart:developer' as developer;
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart'
    show normalizeSchoolIdFromEscuela;

class ARegistro extends StatefulWidget {
  final Escuela escuela;

  // ✅ IMPORTANTE: para usar el schoolId real que resolviste en el login
  final String? schoolIdOverride;

  const ARegistro({super.key, required this.escuela, this.schoolIdOverride});

  @override
  State<ARegistro> createState() => _ARegistroState();
}

class _ARegistroState extends State<ARegistro> {
  static const Color _blue = Color(0xFF1A237E);
  static const Color _orange = Color(0xFFFFA000);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _fn = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  late final String _schoolId;
  late final DocumentReference<Map<String, dynamic>> _ref;
  late final CollectionReference<Map<String, dynamic>> _gradosCol;

  final TextEditingController _passCtrl = TextEditingController();
  bool _showPass = false;

  bool _permitirFotoAlumno = true;
  bool _permitirEditarEstudiantes = true;
  bool _hasExistingPassword = false;

  bool _hydrated = false;
  bool _saving = false;
  bool _dirty = false;

  void _logRegistro(String message, [Object? data]) {
    if (!kDebugMode) return;
    final suffix = data == null ? '' : ' $data';
    final line = '[REGISTRO_CONFIG] $message$suffix';
    developer.log(line, name: 'ARegistro');
    debugPrint(line);
  }

  @override
  void initState() {
    super.initState();

    // ✅ 1) usa override si viene; si no, calcula como antes
    final override = (widget.schoolIdOverride ?? '').trim();
    _schoolId =
        override.isNotEmpty
            ? override
            : normalizeSchoolIdFromEscuela(widget.escuela);

    // ✅ 2) todo en "schools"
    _ref = _db
        .collection('schools')
        .doc(_schoolId)
        .collection('config')
        .doc('registro');

    _gradosCol = _db.collection('schools').doc(_schoolId).collection('grados');

    _logRegistro('init', {
      'schoolId': _schoolId,
      'override': widget.schoolIdOverride,
      'escuelaId': widget.escuela.id,
      'escuelaNombre': widget.escuela.nombre,
    });

    _passCtrl.addListener(() {
      if (_hydrated) _dirty = true;
    });
  }

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  Future<bool> _confirmSalirSinGuardar() async {
    if (!_dirty || _saving) return true;

    final res = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Cambios sin guardar'),
            content: const Text(
              'Tienes cambios pendientes. ¿Salir sin guardar?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _orange),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Salir'),
              ),
            ],
          ),
    );

    return res ?? false;
  }

  String _genPassword({int len = 10}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789@#';
    final rnd = Random.secure();
    return List.generate(len, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> _copy(String text) async {
    final t = text.trim();
    if (t.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay contraseña para copiar')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copiado al portapapeles')));
  }

  String _friendlyFirestoreError(Object e) {
    if (e is FirebaseFunctionsException) {
      return e.message?.trim().isNotEmpty == true ? e.message!.trim() : e.code;
    }
    if (e is FirebaseException) {
      if (e.code == 'permission-denied') {
        return 'Permiso denegado por Rules. Falta permitir: schools/$_schoolId/config/registro';
      }
      return '${e.code}: ${e.message ?? e.toString()}';
    }
    return e.toString();
  }

  Future<bool> _save({bool showOkSnack = true, bool clearField = true}) async {
    final pass = _passCtrl.text;
    _logRegistro('save_start', {
      'schoolId': _schoolId,
      'passLength': pass.length,
      'hasExistingPassword': _hasExistingPassword,
      'permitirFotoAlumno': _permitirFotoAlumno,
      'permitirEditarEstudiantes': _permitirEditarEstudiantes,
    });

    if (pass.isEmpty && !_hasExistingPassword) {
      _logRegistro('save_blocked_empty_password');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La contraseña no puede estar vacía')),
      );
      return false;
    }
    if (pass.isNotEmpty && (pass.length < 12 || pass.length > 128)) {
      _logRegistro('save_blocked_short_password', {'passLength': pass.length});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usa entre 12 y 128 caracteres')),
      );
      return false;
    }

    setState(() => _saving = true);
    try {
      final callable = _fn.httpsCallable('setSchoolRegistroConfig');
      final payload = <String, dynamic>{
        'schoolId': _schoolId,
        if (pass.isNotEmpty) 'password': pass,
        'permitirFotoAlumno': _permitirFotoAlumno,
        'permitirEditarEstudiantes': _permitirEditarEstudiantes,
      };
      final payloadForLog = Map<String, dynamic>.from(payload);
      if (payloadForLog.containsKey('password')) {
        payloadForLog['password'] = '***';
      }
      _logRegistro('calling_setSchoolRegistroConfig', payloadForLog);
      final result = await callable.call(payload);
      _logRegistro('setSchoolRegistroConfig_ok', result.data);

      final verifySnap = await _ref.get();
      final verifyData = verifySnap.data() ?? <String, dynamic>{};
      final hasPasswordHash =
          (verifyData['passwordHash'] ?? '').toString().trim().isNotEmpty;
      final hasLegacyPassword =
          (verifyData['password'] ?? '').toString().trim().isNotEmpty;
      _logRegistro('post_save_verify', {
        'schoolId': _schoolId,
        'exists': verifySnap.exists,
        'hasPasswordHash': hasPasswordHash,
        'hasLegacyPassword': hasLegacyPassword,
      });
      if (!hasPasswordHash && !hasLegacyPassword) {
        throw StateError(
          'La función respondió OK, pero config/registro no quedó con passwordHash.',
        );
      }

      _dirty = false;
      _hasExistingPassword = true;
      if (clearField) {
        _passCtrl.clear();
      }

      if (!mounted) return true;
      if (showOkSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuración de registro guardada')),
        );
      }
      return true;
    } catch (e) {
      _logRegistro('setSchoolRegistroConfig_error', {
        'runtimeType': e.runtimeType.toString(),
        'error': e.toString(),
      });
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error guardando: ${_friendlyFirestoreError(e)}'),
        ),
      );
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showGeneratedPasswordDialog(String password) async {
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Clave generada'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'La clave ya quedó guardada. Guárdala o cópiala ahora.',
                ),
                const SizedBox(height: 12),
                SelectableText(
                  password,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: password));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Clave copiada al portapapeles'),
                    ),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copiar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombre =
        (widget.escuela.nombre ?? '—').trim().isEmpty
            ? '—'
            : widget.escuela.nombre!.trim();

    return WillPopScope(
      onWillPop: _confirmSalirSinGuardar,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6FB),
        appBar: AppBar(
          backgroundColor: _blue,
          foregroundColor: Colors.white,
          title: Text('Registro • $nombre', overflow: TextOverflow.ellipsis),
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _ref.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error leyendo config: ${_friendlyFirestoreError(snap.error!)}',
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }

            final data = snap.data?.data() ?? {};
            _logRegistro('stream_snapshot', {
              'hasData': snap.hasData,
              'exists': snap.data?.exists,
              'schoolId': _schoolId,
              'hasPasswordHash':
                  (data['passwordHash'] ?? '').toString().trim().isNotEmpty,
              'hasLegacyPassword':
                  (data['password'] ?? '').toString().trim().isNotEmpty,
            });

            if (!_hydrated && snap.hasData) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;

                final permitirFoto =
                    (data['permitirFotoAlumno'] is bool)
                        ? data['permitirFotoAlumno'] as bool
                        : true;
                final permitirEditar =
                    (data['permitirEditarEstudiantes'] is bool)
                        ? data['permitirEditarEstudiantes'] as bool
                        : true;

                setState(() {
                  _permitirFotoAlumno = permitirFoto;
                  _permitirEditarEstudiantes = permitirEditar;
                  _hasExistingPassword =
                      (data['passwordHash'] ?? '')
                          .toString()
                          .trim()
                          .isNotEmpty ||
                      (data['password'] ?? '').toString().trim().isNotEmpty;
                  _hydrated = true;
                  _dirty = false;
                });
              });
            }

            return ListView(
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width < 700 ? 14 : 26,
                20,
                MediaQuery.sizeOf(context).width < 700 ? 14 : 26,
                24,
              ),
              children: [
                const _HeaderCard(
                  title: 'Acceso del equipo de registro',
                  subtitle:
                      'Aquí rotas la clave que usará el personal encargado de inscribir alumnos.\n'
                      '⚠️ Esta NO es la del Admin, es solo para Registro.',
                ),
                _SectionCard(
                  title: 'Clave de Registro',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _passCtrl,
                        obscureText: !_showPass,
                        decoration: InputDecoration(
                          labelText:
                              _hasExistingPassword
                                  ? 'Nueva clave de registro'
                                  : 'Clave inicial de registro',
                          hintText: 'Ej: REG-2026-A',
                          filled: true,
                          fillColor: const Color(0xFFF8F9FC),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFE1E6EF),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: _blue,
                              width: 1.5,
                            ),
                          ),
                          suffixIcon: IconButton(
                            tooltip: _showPass ? 'Ocultar' : 'Mostrar',
                            icon: Icon(
                              _showPass
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed:
                                () => setState(() => _showPass = !_showPass),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _orange,
                            ),
                            onPressed:
                                _saving
                                    ? null
                                    : () async {
                                      final p = _genPassword(len: 10);
                                      setState(() {
                                        _passCtrl.text = p;
                                        _dirty = true;
                                        _showPass = true;
                                      });
                                      await _save(
                                        showOkSnack: true,
                                        clearField: false,
                                      );
                                    },
                            icon: const Icon(Icons.auto_fix_high),
                            label: const Text('Generar y guardar'),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                _saving ? null : () => _copy(_passCtrl.text),
                            icon: const Icon(Icons.copy),
                            label: const Text('Copiar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _hasExistingPassword
                            ? 'La clave queda guardada en Firebase y, si generas o escribes una nueva, se mantendrá visible aquí hasta que la cambies o salgas de esta pantalla.'
                            : 'Define una clave inicial para el equipo de registro. Luego podrás rotarla cuando haga falta.',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                _SectionCard(
                  title: 'Grados (unificados)',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Estos grados son los mismos que usarán DOCENTES y ESTUDIANTES.',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream:
                            _gradosCol.orderBy('name').limit(12).snapshots(),
                        builder: (context, s) {
                          if (s.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: LinearProgressIndicator(minHeight: 3),
                            );
                          }
                          if (s.hasError) {
                            return Text(
                              'Error cargando grados: ${_friendlyFirestoreError(s.error!)}',
                              style: const TextStyle(color: Colors.red),
                            );
                          }

                          final docs = s.data?.docs ?? [];
                          if (docs.isEmpty) {
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _blue.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: const Text(
                                'No hay grados creados todavía.',
                              ),
                            );
                          }

                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children:
                                docs.map((d) {
                                  final name =
                                      (d.data()['name'] ?? '—').toString();
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _orange.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: _orange.withOpacity(0.25),
                                      ),
                                    ),
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  );
                                }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                _SectionCard(
                  title: 'Permisos',
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _permitirEditarEstudiantes,
                        onChanged:
                            (v) => setState(() {
                              _permitirEditarEstudiantes = v;
                              _dirty = true;
                            }),
                        title: const Text('Permitir editar estudiantes'),
                        subtitle: const Text(
                          'Si lo apagas, el equipo de registro no podrá editar fichas ya guardadas.',
                        ),
                        activeColor: _orange,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        value: _permitirFotoAlumno,
                        onChanged: (v) {
                          setState(() {
                            _permitirFotoAlumno = v;
                            _dirty = true;
                          });
                        },
                        title: const Text(
                          'Permitir que el alumno cambie su foto',
                        ),
                        subtitle: const Text(
                          'Si lo apagas, solo administración podrá asignar/editar la foto.',
                        ),
                        activeColor: _orange,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _saving ? null : _save,
                    icon:
                        _saving
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.save),
                    label: Text(_saving ? 'Guardando...' : 'Guardar'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// -------- UI helpers --------

class _HeaderCard extends StatelessWidget {
  final String title;
  final String subtitle;
  const _HeaderCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Container(
      padding: EdgeInsets.all(compact ? 19 : 25),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [_ARegistroState._blue, Color(0xFF3949AB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: _ARegistroState._blue.withOpacity(0.16),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 48 : 56,
            height: compact ? 48 : 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.how_to_reg_rounded,
              color: Colors.white,
              size: 29,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 19 : 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFE5E9FF),
                    fontSize: 14,
                    height: 1.45,
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

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final icon =
        title.toLowerCase().contains('clave')
            ? Icons.key_rounded
            : title.toLowerCase().contains('grado')
            ? Icons.school_outlined
            : Icons.admin_panel_settings_outlined;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5EAF2)),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: _ARegistroState._blue.withOpacity(0.035),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F2FA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _ARegistroState._blue, size: 21),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF17243A),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
