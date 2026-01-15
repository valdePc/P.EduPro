// lib/admin_escolar/screens/A_registro.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

import 'A_grados.dart';

class ARegistro extends StatefulWidget {
  final Escuela escuela;

  // ✅ IMPORTANTE: para usar el schoolId real que resolviste en el login
  final String? schoolIdOverride;

  const ARegistro({
    super.key,
    required this.escuela,
    this.schoolIdOverride,
  });

  @override
  State<ARegistro> createState() => _ARegistroState();
}

class _ARegistroState extends State<ARegistro> {
  static const Color _blue = Color(0xFF0D47A1);
  static const Color _orange = Color(0xFFFFA000);

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  late final String _schoolId;
  late final DocumentReference<Map<String, dynamic>> _ref;
  late final CollectionReference<Map<String, dynamic>> _gradosCol;

  final TextEditingController _passCtrl = TextEditingController();
  bool _showPass = false;

  bool _permitirFotoAlumno = true;
  bool _permitirEditarEstudiantes = true;

  bool _hydrated = false;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();

    // ✅ 1) usa override si viene; si no, calcula como antes
    final override = (widget.schoolIdOverride ?? '').trim();
    _schoolId = override.isNotEmpty
        ? override
        : normalizeSchoolIdFromEscuela(widget.escuela);

    // ✅ 2) todo en "schools"
    _ref = _db
        .collection('schools')
        .doc(_schoolId)
        .collection('config')
        .doc('registro');

    _gradosCol = _db
        .collection('schools')
        .doc(_schoolId)
        .collection('grados');

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
      builder: (_) => AlertDialog(
        title: const Text('Cambios sin guardar'),
        content: const Text('Tienes cambios pendientes. ¿Salir sin guardar?'),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copiado al portapapeles')),
    );
  }

  String _friendlyFirestoreError(Object e) {
    if (e is FirebaseException) {
      if (e.code == 'permission-denied') {
        return 'Permiso denegado por Rules. Falta permitir: schools/$_schoolId/config/registro';
      }
      return '${e.code}: ${e.message ?? e.toString()}';
    }
    return e.toString();
  }

  Future<void> _save({bool showOkSnack = true}) async {
    final pass = _passCtrl.text.trim();

    if (pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La contraseña no puede estar vacía')),
      );
      return;
    }
    if (pass.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usa al menos 4 caracteres')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _ref.set({
        'password': pass,
        'permitirFotoAlumno': _permitirFotoAlumno,
        'permitirEditarEstudiantes': _permitirEditarEstudiantes,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _dirty = false;

      if (!mounted) return;
      if (showOkSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuración de registro guardada')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando: ${_friendlyFirestoreError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openGrados() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AGrados(escuela: widget.escuela)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombre = (widget.escuela.nombre ?? '—').trim().isEmpty
        ? '—'
        : widget.escuela.nombre!.trim();

    return WillPopScope(
      onWillPop: _confirmSalirSinGuardar,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _blue,
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

            if (!_hydrated && snap.hasData) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;

                final pass = (data['password'] ?? '').toString();
                final permitirFoto = (data['permitirFotoAlumno'] is bool)
                    ? data['permitirFotoAlumno'] as bool
                    : true;
                final permitirEditar = (data['permitirEditarEstudiantes'] is bool)
                    ? data['permitirEditarEstudiantes'] as bool
                    : true;

                setState(() {
                  _passCtrl.text = pass;
                  _permitirFotoAlumno = permitirFoto;
                  _permitirEditarEstudiantes = permitirEditar;
                  _hydrated = true;
                  _dirty = false;
                });
              });
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _HeaderCard(
                  title: 'Acceso del equipo de registro',
                  subtitle:
                      'Aquí defines la contraseña que usará el personal encargado de inscribir alumnos.\n'
                      '⚠️ Esta NO es la del Admin, es solo para Registro.',
                ),
                const SizedBox(height: 14),

                _SectionCard(
                  title: 'Contraseña de Registro',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _passCtrl,
                        obscureText: !_showPass,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          hintText: 'Ej: REG-2026-A',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          suffixIcon: IconButton(
                            tooltip: _showPass ? 'Ocultar' : 'Mostrar',
                            icon: Icon(
                              _showPass ? Icons.visibility_off : Icons.visibility,
                            ),
                            onPressed: () => setState(() => _showPass = !_showPass),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: _orange),
                            onPressed: _saving
                                ? null
                                : () async {
                                    final p = _genPassword(len: 10);
                                    setState(() {
                                      _passCtrl.text = p;
                                      _dirty = true;
                                    });
                                    await _save(showOkSnack: true);
                                  },
                            icon: const Icon(Icons.auto_fix_high),
                            label: const Text('Generar y guardar'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _saving ? null : () => _copy(_passCtrl.text),
                            icon: const Icon(Icons.copy),
                            label: const Text('Copiar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tip: cambia por período (ej: “REG-2026-A”).',
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
                        stream: _gradosCol.orderBy('name').limit(12).snapshots(),
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
                                'No hay grados todavía. Crea el primero con el botón de abajo.',
                              ),
                            );
                          }

                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: docs.map((d) {
                              final name = (d.data()['name'] ?? '—').toString();
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _orange.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: _orange.withOpacity(0.25)),
                                ),
                                child: Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _orange,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _openGrados,
                          icon: const Icon(Icons.add),
                          label: const Text('Crear grado'),
                        ),
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
                        onChanged: (v) => setState(() {
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
                        title: const Text('Permitir que el alumno cambie su foto'),
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
                    icon: _saving
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Colors.grey.shade700)),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
