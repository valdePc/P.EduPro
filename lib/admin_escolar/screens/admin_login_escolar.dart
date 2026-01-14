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

class AdminLoginEscolarScreen extends StatefulWidget {
  final Escuela escuela;
  const AdminLoginEscolarScreen({super.key, required this.escuela});

  @override
  State<AdminLoginEscolarScreen> createState() => _AdminLoginEscolarScreenState();
}

class _AdminLoginEscolarScreenState extends State<AdminLoginEscolarScreen> {
  final _userCtrl = TextEditingController(); // correo
  final _passCtrl = TextEditingController();

  final _db = FirebaseFirestore.instance;

  bool _loading = false;
  bool _obscure = true;

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
    // Opcional: intenta cargar schoolData para evitar estados raros
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

  // Resolver school doc real
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
    _userCtrl.dispose();
    _passCtrl.dispose();
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

    // Intenta por URI
    final uri = Uri.tryParse(s);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last.trim();
      if (last.isNotEmpty) return last;
    }

    // Fallback regex: último segmento después de /
    final m = RegExp(r'/([^/?#]+)$').firstMatch(s);
    if (m != null) return m.group(1)?.trim();

    return null;
  }

  String? _schoolIdFromLinks(Escuela e) {
    // Prioridad: adminLink, luego prof/alum (por si alguno tiene el código)
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

    _schoolId =
        _schoolIdCandidates.isNotEmpty ? _schoolIdCandidates.first : primary;

    await _resolveSchoolIdAndLoad();
  }

  Future<void> _resolveSchoolIdAndLoad() async {
    if (mounted) setState(() => _schoolLoading = true);

    try {
      String chosen = _schoolId;

      // Busca el primer doc que exista
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

      // Prefill del correo admin si existe
final raw = (_schoolData?['adminEmail'] ?? '').toString().trim();
if (_looksLikeEmail(raw)) {
  _userCtrl.text = raw;
}

    } catch (_) {
      // no rompas el login
    } finally {
      if (mounted) setState(() => _schoolLoading = false);
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

    // 0) Si ni siquiera existe el doc del colegio => no autorizamos.
    if (!_schoolDocFound) return false;

    // 1) Admin principal por uid/email
    if (adminUid.isNotEmpty && uid == adminUid) return true;
    if (adminEmail.isNotEmpty && email.isNotEmpty && email == adminEmail) {
      return true;
    }

    // 2) Subcolección admins: schools/{schoolId}/admins/{uid}
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

    // 3) Backup: buscar por email en admins (por si el docId no es uid)
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

    // Evita “auto-login” con Google cacheado (solo mobile)
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
  // Login email/pass
  // ------------------------------------------------------------
  Future<void> _loginEmailPassword() async {
    final email = _userCtrl.text.trim().toLowerCase();
    final pass = _passCtrl.text;

    if (email.isEmpty || !email.contains('@')) {
      _toast('Escribe un correo válido.');
      return;
    }
    if (pass.trim().length < 6) {
      _toast('Contraseña inválida.');
      return;
    }

    setState(() => _loading = true);
    try {
      // Refresca schoolData por si cambiaron adminEmail
      await _resolveSchoolIdAndLoad();

      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );

      final user = cred.user ?? FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'no-user',
          message: 'No se obtuvo usuario.',
        );
      }

      await _ensureAuthorizedOrThrow(user);
      _goToPizarra();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
        _toast('Correo o contraseña incorrectos.');
      } else if (e.code == 'not-authorized') {
        _toast('Acceso denegado: este correo no está autorizado para este colegio.');
      } else {
        _toast('${e.code}${e.message != null ? ' — ${e.message}' : ''}');
      }
    } catch (e) {
      _toast('Login falló: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------------------------------------------------
  // Google login (Web: popup / Mobile: google_sign_in.instance)
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

    // Web: popup nativo de Firebase
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});
      return await auth.signInWithPopup(provider);
    }

    // Mobile: API nueva google_sign_in (singleton)
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
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'Google no devolvió idToken.',
      );
    }

    final credential = GoogleAuthProvider.credential(
      idToken: idToken,
      accessToken: accessToken, // puede ser null
    );

    return await auth.signInWithCredential(credential);
  }

Future<void> _loginGoogle() async {
  setState(() => _loading = true);

  try {
    // ✅ En Web, el popup debe dispararse "pegado" al click, sin awaits antes.
    final cred = await _signInWithGoogle();

    // Ahora sí, refresca config del colegio (opcional, pero útil)
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
      statusText =
          'Este colegio aún no tiene adminEmail configurado.\n'
          'Ve a ColeAdmin → “Acceso principal”.';
      statusBg = Colors.orange.shade50;
      statusFg = Colors.orange.shade900;
    } else {
      statusText = 'Correo autorizado: $adminEmail';
      statusBg = Colors.green.shade50;
      statusFg = Colors.green.shade900;
    }

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
                      'assets/logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.school, size: 64),
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
                  TextField(
                    controller: _userCtrl,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.mail),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    onSubmitted: (_) {
                      if (!_loading) _loginEmailPassword();
                    },
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: azul,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: (_loading || _schoolLoading || !_schoolDocFound)
                          ? null
                          : _loginEmailPassword,
                      child: Text(
                        _loading ? 'Entrando...' : 'Entrar',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: const [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('o'),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: (_loading || _schoolLoading || !_schoolDocFound)
                          ? null
                          : _loginGoogle,
                      icon: const Icon(Icons.login),
                      label: Text(_loading ? 'Cargando...' : 'Continuar con Google'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Solo pueden entrar correos autorizados para este colegio.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, height: 1.2),
                  ),
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}
