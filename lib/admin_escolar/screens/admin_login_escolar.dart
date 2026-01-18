// lib/admin_escolar/screens/admin_login_escolar.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;
import 'package:edupro/admin_escolar/screens/A_pizarra.dart';
import 'package:edupro/admin_escolar/screens/registro_equipo_screen.dart';

enum _AuthMode { login, register }

class AdminLoginEscolarScreen extends StatefulWidget {
  final Escuela escuela;
  const AdminLoginEscolarScreen({super.key, required this.escuela});

  @override
  State<AdminLoginEscolarScreen> createState() => _AdminLoginEscolarScreenState();
}

class _AdminLoginEscolarScreenState extends State<AdminLoginEscolarScreen> {
  final _codeCtrl = TextEditingController(); // código para registro
  final _db = FirebaseFirestore.instance;

  bool _loading = false;
  _AuthMode _mode = _AuthMode.login;

  bool _looksLikeEmail(String s) {
    final v = s.trim();
    return v.contains('@') && v.contains('.');
  }

  // ------------------------------------------------------------
  // BYPASS TEMPORAL (SOLO DEV): activar con --dart-define
  // ------------------------------------------------------------
  static const bool _devBypassDefine =
      bool.fromEnvironment('EDUPRO_ADMIN_BYPASS', defaultValue: false);

  bool get _devBypassEnabled => !kReleaseMode && _devBypassDefine;

  Future<void> _devQuickAccess() async {
    try {
      await _resolveSchoolIdAndLoad();
    } catch (_) {}

    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Acceso rápido (DEV)'),
        content: const Text(
          'Esto salta el login y entra directo al panel.\n'
          'Úsalo solo mientras terminas la configuración.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Entrar'),
          ),
        ],
      ),
    );

    if (ok == true) {
      _toast('Acceso rápido activado (solo DEV).');
      _goToPizarra();
    }
  }

  // ------------------------------------------------------------
  // Resolver school doc real
  // ------------------------------------------------------------
  bool _init = false;
  bool _schoolLoading = true;

  late List<String> _schoolIdCandidates;
  late String _schoolId;

  bool _schoolDocFound = true;
  Map<String, dynamic>? _schoolData;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _goToPizarra() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => APizarra(escuela: widget.escuela)),
    );
  }

  // ------------------------------------------------------------
  // Helpers: schoolId candidates
  // ------------------------------------------------------------
  String _normalizeSchoolIdLikeAGrados(Escuela e) {
    final raw = (e.nombre ?? 'school-${e.hashCode}').toString();
    var normalized = raw
        .replaceAll(RegExp(r'https?:\/\/'), '')
        .replaceAll(RegExp(r'\/\/+'), '/');
    normalized = normalized.replaceAll('/', '_');
    normalized = normalized.replaceAll(RegExp(r'[^A-Za-z0-9\-_]'), '');
    if (normalized.isEmpty) normalized = 'school-${e.hashCode}';
    return normalized;
  }

  String? _extractSchoolIdFromUrl(String? url) {
    final s = (url ?? '').trim();
    if (s.isEmpty) return null;

    final uri = Uri.tryParse(s);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last.trim();
      if (last.isNotEmpty) return last;
    }

    final m = RegExp(r'/([^/?#]+)$').firstMatch(s);
    if (m != null) return m.group(1)?.trim();

    return null;
  }

  String? _schoolIdFromLinks(Escuela e) {
    final candidates = <String?>[
      _extractSchoolIdFromUrl(e.adminLink),
      _extractSchoolIdFromUrl(e.profLink),
      _extractSchoolIdFromUrl(e.alumLink),
    ];
    for (final c in candidates) {
      if (c != null && c.isNotEmpty) return c;
    }
    return null;
  }

  List<String> _uniqueInOrder(List<String> items) {
    final out = <String>[];
    final seen = <String>{};
    for (final it in items) {
      final v = it.trim();
      if (v.isEmpty) continue;
      if (seen.add(v)) out.add(v);
    }
    return out;
  }

  Future<void> _bootstrap() async {
    if (_init) return;
    _init = true;

    final fromLink = _schoolIdFromLinks(widget.escuela);
    final primary = normalizeSchoolIdFromEscuela(widget.escuela);
    final alt = _normalizeSchoolIdLikeAGrados(widget.escuela);

    _schoolIdCandidates = _uniqueInOrder([
      if (fromLink != null) fromLink,
      primary,
      alt,
    ]);

    _schoolId = _schoolIdCandidates.isNotEmpty ? _schoolIdCandidates.first : primary;

    await _resolveSchoolIdAndLoad();
  }

  Future<void> _resolveSchoolIdAndLoad() async {
    if (mounted) setState(() => _schoolLoading = true);

    try {
      String chosen = _schoolId;

      for (final candidate in _schoolIdCandidates) {
        final d = await _db.collection('schools').doc(candidate).get();
        if (d.exists) {
          chosen = candidate;
          break;
        }
      }

      _schoolId = chosen;

      final schoolDoc = await _db.collection('schools').doc(_schoolId).get();
      _schoolDocFound = schoolDoc.exists;
      _schoolData = schoolDoc.data();
    } catch (_) {
      // no rompas el login
    } finally {
      if (mounted) setState(() => _schoolLoading = false);
    }
  }

  bool _schoolActive() {
    final v = _schoolData?['active'];
    return v == null ? true : (v == true);
  }

  void _switchMode(_AuthMode m) {
    if (!mounted) return;
    setState(() => _mode = m);
  }

  // ------------------------------------------------------------
  // ✅ Para leer el código en modo Registro, intenta auth anónimo
  // (Sirve si tus Rules requieren request.auth != null)
  // ------------------------------------------------------------
  Future<void> _ensureAnonAuthForRegistro() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return;

    try {
      await auth.signInAnonymously();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'operation-not-allowed') {
        // Si no está habilitado Anonymous, no rompas el flujo.
      }
    } catch (_) {}
  }

  // ------------------------------------------------------------
  // ✅ Lee la contraseña EXACTA como se guardó en A_registro:
  // schools/{schoolId}/config/registro.password
  // - prueba en todos los candidates
  // - si la encuentra, fija _schoolId a ese candidato
  // ------------------------------------------------------------
  Future<String> _loadRegistroPasswordAny() async {
    await _ensureAnonAuthForRegistro();

    final ordered = _uniqueInOrder([_schoolId, ..._schoolIdCandidates]);

    for (final sid in ordered) {
      final d = await _db
          .collection('schools')
          .doc(sid)
          .collection('config')
          .doc('registro')
          .get();

      final pass = (d.data()?['password'] ?? '').toString().trim();
      if (pass.isNotEmpty) {
        _schoolId = sid;
        return pass; // EXACTO, case-sensitive
      }
    }

    return '';
  }

  // ------------------------------------------------------------
  // ✅ Ir a registro SOLO si código correcto
  // ------------------------------------------------------------
  Future<void> _goToRegistro() async {
    if (_schoolLoading || _loading) return;

    setState(() => _loading = true);
    try {
      await _resolveSchoolIdAndLoad();

      if (!_schoolDocFound) {
        _toast('No se encontró el colegio.');
        return;
      }
      if (!_schoolActive()) {
        _toast('Este colegio está inactivo.');
        return;
      }

      final entered = _codeCtrl.text.trim();
      if (entered.isEmpty) {
        _toast('Escribe el código del colegio.');
        return;
      }

      String expected = '';
      try {
        expected = await _loadRegistroPasswordAny();
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          _toast(
            'No tengo permiso para leer el código de registro.\n'
            'Solución rápida: habilita Anonymous Auth o ajusta Rules para permitir leer '
            'schools/{id}/config/registro.',
          );
          return;
        }
        _toast('Error leyendo el código: ${e.code}');
        return;
      } catch (e) {
        _toast('No se pudo verificar el código: $e');
        return;
      }

      if (expected.isEmpty) {
        _toast('Aún no se ha generado el código de registro para este colegio.');
        return;
      }

      if (entered != expected) {
        _toast('Código incorrecto.');
        return;
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RegistroEquipoScreen(
            escuela: widget.escuela,
            schoolIdOverride: _schoolId,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------------------------------------------------
  // Autorización: solo admins del colegio
  // ------------------------------------------------------------
  Future<bool> _isAuthorizedForThisSchool(User user) async {
    final email = (user.email ?? '').trim().toLowerCase();
    final uid = user.uid;

    final adminEmail =
        (_schoolData?['adminEmail'] ?? '').toString().trim().toLowerCase();
    final adminUid = (_schoolData?['adminUid'] ?? '').toString().trim();

    if (!_schoolDocFound) return false;

    if (adminUid.isNotEmpty && uid == adminUid) return true;
    if (adminEmail.isNotEmpty && email.isNotEmpty && email == adminEmail) return true;

    try {
      final d = await _db
          .collection('schools')
          .doc(_schoolId)
          .collection('admins')
          .doc(uid)
          .get();

      if (d.exists) {
        final m = d.data() ?? {};
        final status = (m['status'] ?? 'active').toString();
        return status == 'active';
      }
    } catch (_) {}

    if (email.isNotEmpty) {
      try {
        final q = await _db
            .collection('schools')
            .doc(_schoolId)
            .collection('admins')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();

        if (q.docs.isNotEmpty) {
          final m = q.docs.first.data();
          final status = (m['status'] ?? 'active').toString();
          return status == 'active';
        }
      } catch (_) {}
    }

    return false;
  }

  Future<void> _denyAndSignOut() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    if (!kIsWeb) {
      try {
        final gs = GoogleSignIn.instance;
        try {
          await gs.initialize();
        } catch (_) {}
        await gs.signOut();
      } catch (_) {}
    }
  }

  Future<void> _ensureAuthorizedOrThrow(User user) async {
    final ok = await _isAuthorizedForThisSchool(user);
    if (!ok) {
      await _denyAndSignOut();
      throw FirebaseAuthException(
        code: 'not-authorized',
        message: 'Este usuario no tiene permisos para esta escuela.',
      );
    }
  }

  // ------------------------------------------------------------
  // Google login
  // ------------------------------------------------------------
  String _friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'popup-blocked':
        return 'El navegador bloqueó el popup. Permite popups para esta página.';
      case 'popup-closed-by-user':
        return 'Cerraste el popup antes de terminar.';
      case 'cancelled-popup-request':
        return 'Se canceló el popup (intenta otra vez).';
      case 'unauthorized-domain':
        return 'Dominio no autorizado en Firebase Auth (Authorized domains).';
      case 'operation-not-allowed':
        return 'Google no está habilitado en Firebase Auth.';
      case 'account-exists-with-different-credential':
        return 'Ese correo ya existe con otro método de acceso.';
      case 'canceled':
        return 'Inicio de sesión cancelado.';
      default:
        return '${e.code}${e.message != null ? ' — ${e.message}' : ''}';
    }
  }

  Future<UserCredential> _signInWithGoogle() async {
    final auth = FirebaseAuth.instance;

    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      return await auth.signInWithPopup(provider);
    }

    final gs = GoogleSignIn.instance;
    await gs.initialize();

    final googleUser = await gs.authenticate(scopeHint: const ['email']);
    final dynamic googleAuth = await googleUser.authentication;

    final String? idToken = googleAuth.idToken as String?;
    String? accessToken;
    try {
      accessToken = googleAuth.accessToken as String?;
    } catch (_) {
      accessToken = null;
    }

    if (idToken == null) {
      throw FirebaseAuthException(code: 'missing-id-token', message: 'Google no devolvió idToken.');
    }

    final credential = GoogleAuthProvider.credential(
      idToken: idToken,
      accessToken: accessToken,
    );

    return await auth.signInWithCredential(credential);
  }

  Future<void> _loginGoogle() async {
    setState(() => _loading = true);

    try {
      final cred = await _signInWithGoogle();
      await _resolveSchoolIdAndLoad();

      final user = cred.user ?? FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw FirebaseAuthException(code: 'no-user', message: 'No se obtuvo usuario de Google.');
      }

      await _ensureAuthorizedOrThrow(user);
      _goToPizarra();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'not-authorized') {
        _toast('Acceso denegado: ese Google no está autorizado para este colegio.');
      } else {
        _toast('Google login falló: ${_friendlyAuthError(e)}');
      }
    } catch (e) {
      _toast('Google login falló: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------------------------------------------------
  // UI
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final azul = const Color.fromARGB(255, 21, 101, 192);

    final rawAdminEmail = (_schoolData?['adminEmail'] ?? '').toString().trim();
    final adminEmail = _looksLikeEmail(rawAdminEmail) ? rawAdminEmail : '';
    final configured = adminEmail.isNotEmpty;

    final String statusText;
    final Color statusBg;
    final Color statusFg;

    if (_schoolLoading) {
      statusText = 'Cargando configuración del colegio...';
      statusBg = Colors.grey.shade200;
      statusFg = Colors.black87;
    } else if (!_schoolDocFound) {
      statusText =
          'No se encontró este colegio en Firestore.\n'
          'Abre este login desde la lista de Colegios (para que lleve el código correcto).';
      statusBg = Colors.red.shade50;
      statusFg = Colors.red.shade900;
    } else if (!configured) {
      // OJO: aunque no haya adminEmail, igual puede autorizar por schools/{id}/admins
      statusText =
          'Este colegio aún no tiene adminEmail configurado.\n'
          'Aún así, pueden entrar admins autorizados por lista.';
      statusBg = Colors.orange.shade50;
      statusFg = Colors.orange.shade900;
    } else {
      statusText = 'Correo Autorizado: $adminEmail';
      statusBg = Colors.green.shade50;
      statusFg = Colors.green.shade900;
    }

    final bool canInteract = !_loading && !_schoolLoading && _schoolDocFound;

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 244, 248, 245),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 90,
                    child: Image.asset(
                      'assets/LogoAdmin.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(Icons.school, size: 64),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.escuela.nombre,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Acceso • Administración Escolar',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),

                  // selector de modo
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _switchMode(_AuthMode.login),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _mode == _AuthMode.login ? azul : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Iniciar sesión',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _mode == _AuthMode.login ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _switchMode(_AuthMode.register),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _mode == _AuthMode.register ? azul : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Registro',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _mode == _AuthMode.register
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // estado del colegio
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: statusFg,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // MODO LOGIN (SOLO GOOGLE)
                  if (_mode == _AuthMode.login) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: azul,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: canInteract ? _loginGoogle : null,
                        icon: const Icon(Icons.g_mobiledata, size: 28),
                        label: Text(
                          _loading ? 'Cargando...' : 'Continuar con Google',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Solo Personal Autorizado.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, height: 1.2),
                    ),

                    // DEV bypass solo en login
                    Visibility(
                      visible: _devBypassEnabled,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: const [
                                Icon(Icons.warning_amber_rounded,
                                    size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Modo DEV: acceso rápido habilitado',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _loading ? null : _devQuickAccess,
                              icon: const Icon(Icons.bolt),
                              label: const Text('Acceso rápido (DEV)'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // MODO REGISTRO (SE MANTIENE INTACTO)
                  if (_mode == _AuthMode.register) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blueGrey.shade100),
                      ),
                      child: const Text(
                        'Ingrese el CÓDIGO que le proporciono la administración,\n'
                        'para acceder a este espacio.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _codeCtrl,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Código del colegio',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.vpn_key),
                      ),
                      onSubmitted: (_) {
                        if (!_loading) _goToRegistro();
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: azul,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: canInteract ? _goToRegistro : null,
                        child: Text(
                          _loading ? 'Verificando...' : 'Continuar a registro',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
