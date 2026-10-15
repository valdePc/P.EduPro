// lib/admin_escolar/screens/admin_login_escolar.dart
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/services/edupro_two_factor_service.dart';
import 'package:edupro/services/edupro_trusted_device_service.dart';
import 'package:edupro/utils/school_utils.dart'
    show lookupSchoolPublicMeta, normalizeSchoolIdFromEscuela;
import 'package:edupro/admin_escolar/screens/A_pizarra.dart';
import 'package:edupro/admin_escolar/screens/registro_equipo_screen.dart';
import 'package:edupro/admin_escolar/services/school_registration_session.dart';

enum _AuthMode { login, register }

class AdminLoginEscolarScreen extends StatefulWidget {
  final Escuela escuela;
  const AdminLoginEscolarScreen({super.key, required this.escuela});

  @override
  State<AdminLoginEscolarScreen> createState() =>
      _AdminLoginEscolarScreenState();
}

class _AdminLoginEscolarScreenState extends State<AdminLoginEscolarScreen> {
  final _codeCtrl = TextEditingController(); // código para registro
  final _db = FirebaseFirestore.instance;
  final _fn = FirebaseFunctions.instanceFor(region: 'us-central1');

  bool _loading = false;
  _AuthMode _mode = _AuthMode.login;

  bool _looksLikeEmail(String s) {
    final v = s.trim();
    return v.contains('@') && v.contains('.');
  }

  // ------------------------------------------------------------
  // BYPASS TEMPORAL (SOLO DEV): activar con --dart-define
  // ------------------------------------------------------------
  static const bool _devBypassDefine = bool.fromEnvironment(
    'EDUPRO_ADMIN_BYPASS',
    defaultValue: false,
  );

  bool get _devBypassEnabled => !kReleaseMode && _devBypassDefine;

  Future<void> _devQuickAccess() async {
    try {
      await _resolveSchoolIdAndLoad();
    } catch (_) {}

    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
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
      MaterialPageRoute(
        builder:
            (_) =>
                APizarra(escuela: widget.escuela, schoolIdOverride: _schoolId),
      ),
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
    if (uri != null) {
      // eduproapp://<schoolId>/<module>
      if (uri.scheme.toLowerCase() == 'eduproapp' &&
          uri.host.trim().isNotEmpty) {
        return uri.host.trim();
      }

      // https://.../#/eduproapp/<schoolId>/<module>
      List<String> segs = uri.pathSegments;
      if (segs.isEmpty && uri.fragment.isNotEmpty) {
        final frag =
            uri.fragment.startsWith('/')
                ? uri.fragment.substring(1)
                : uri.fragment;
        segs = Uri.parse('/$frag').pathSegments;
      }
      final idx = segs.indexWhere((e) => e.toLowerCase() == 'eduproapp');
      if (idx >= 0 && segs.length > idx + 1) {
        final sid = segs[idx + 1].trim();
        if (sid.isNotEmpty) return sid;
      }

      // legacy: toma último segmento
      if (uri.pathSegments.isNotEmpty) {
        final last = uri.pathSegments.last.trim();
        if (last.isNotEmpty) return last;
      }
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

    _schoolId =
        _schoolIdCandidates.isNotEmpty ? _schoolIdCandidates.first : primary;

    await _resolveSchoolIdAndLoad();
  }

  Future<void> _resolveSchoolIdAndLoad() async {
    if (mounted) setState(() => _schoolLoading = true);

    try {
      String chosen = _schoolId;
      Map<String, dynamic>? publicData;
      var schoolFound = false;

      for (final candidate in _schoolIdCandidates) {
        final lookup = await lookupSchoolPublicMeta(_db, candidate);
        if (lookup != null) {
          chosen = lookup.schoolId;
          publicData = lookup.data;
          schoolFound = true;
          break;
        }
      }

      if (!schoolFound) {
        for (final candidate in _schoolIdCandidates) {
          try {
            final snap = await _db.collection('schools').doc(candidate).get();
            if (!snap.exists) continue;
            chosen = snap.id;
            publicData = snap.data();
            schoolFound = true;
            break;
          } on FirebaseException catch (e) {
            if (e.code == 'permission-denied') {
              continue;
            }
          } catch (_) {
            continue;
          }
        }
      }

      if (!schoolFound) {
        // Si la ficha pública aún no existe, dejamos el fallback visual por schoolId.
      }

      _schoolId = chosen;
      _schoolDocFound = schoolFound || chosen.trim().isNotEmpty;
      _schoolData = publicData ?? <String, dynamic>{'active': true};
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

  Future<Map<String, dynamic>> _validateRegistroAccess(String code) async {
    final callable = _fn.httpsCallable('validateSchoolRegistroAccess');
    final resp = await callable.call(<String, dynamic>{
      'schoolId': _schoolId,
      'code': code,
    });

    final raw = resp.data;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry('$key', value));
    }
    return const <String, dynamic>{};
  }

  String _rateLimitSchoolId() {
    final resolved = _schoolId.trim();
    if (resolved.isNotEmpty) return resolved;
    return normalizeSchoolIdFromEscuela(widget.escuela).trim();
  }

  Future<Map<String, dynamic>> _callAdminLoginRateLimit({
    required String operation,
    required String attemptFlow,
    String? reason,
  }) async {
    final callable = _fn.httpsCallable('adminSchoolLoginRateLimit');
    final resp = await callable.call(<String, dynamic>{
      'operation': operation,
      'attemptFlow': attemptFlow,
      'schoolId': _rateLimitSchoolId(),
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });

    final raw = resp.data;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry('$key', value));
    }
    return const <String, dynamic>{};
  }

  String _formatWaitTime(int seconds) {
    if (seconds <= 0) return 'unos segundos';
    final totalMinutes = (seconds / 60).ceil();
    if (totalMinutes < 60) {
      return '$totalMinutes minuto${totalMinutes == 1 ? '' : 's'}';
    }
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (minutes == 0) {
      return '$hours hora${hours == 1 ? '' : 's'}';
    }
    return '$hours h ${minutes} min';
  }

  String _rateLimitMessage(Map<String, dynamic> result, {String? fallback}) {
    final serverMessage = (result['message'] ?? '').toString().trim();
    if (serverMessage.isNotEmpty) return serverMessage;

    final waitSeconds = (result['waitSeconds'] as num?)?.toInt() ?? 0;
    if (waitSeconds > 0) {
      return 'Demasiados intentos fallidos. Vuelve a intentar en ${_formatWaitTime(waitSeconds)}.';
    }

    return fallback ?? 'No se pudo validar el acceso en este momento.';
  }

  Future<bool> _ensureAdminLoginIpAllowed({required String attemptFlow}) async {
    try {
      final result = await _callAdminLoginRateLimit(
        operation: 'precheck',
        attemptFlow: attemptFlow,
      );
      final allowed = result['allowed'] == true;
      if (!allowed) {
        _toast(
          _rateLimitMessage(
            result,
            fallback: 'Esta IP debe esperar antes de volver a intentar.',
          ),
        );
      }
      return allowed;
    } on FirebaseFunctionsException catch (e) {
      _toast(
        'No se pudo validar la seguridad del acceso: ${e.message ?? e.code}',
      );
      return false;
    } catch (e) {
      _toast('No se pudo validar la seguridad del acceso: $e');
      return false;
    }
  }

  Future<void> _recordAdminLoginFailure({
    required String attemptFlow,
    required String reason,
  }) async {
    try {
      final result = await _callAdminLoginRateLimit(
        operation: 'failure',
        attemptFlow: attemptFlow,
        reason: reason,
      );
      if (result['blocked'] == true) {
        _toast(
          _rateLimitMessage(
            result,
            fallback:
                'Esta IP fue bloqueada temporalmente por demasiados intentos fallidos.',
          ),
        );
      }
    } catch (_) {
      // No interrumpir el mensaje principal si el registro del fallo no responde.
    }
  }

  Future<void> _recordAdminLoginSuccess({required String attemptFlow}) async {
    try {
      await _callAdminLoginRateLimit(
        operation: 'success',
        attemptFlow: attemptFlow,
      );
    } catch (_) {
      // El acceso ya fue válido; no lo rompemos por una limpieza fallida.
    }
  }

  bool _shouldCountGoogleFailure(FirebaseAuthException e) {
    switch (e.code) {
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
      case 'canceled':
      case 'popup-blocked':
        return false;
      default:
        return true;
    }
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

      final entered = _codeCtrl.text;
      if (entered.isEmpty) {
        _toast('Escribe el código del colegio.');
        return;
      }

      try {
        final result = await _validateRegistroAccess(entered);
        final ok = result['ok'] == true;
        final configured = result['configured'] != false;
        final blocked = result['blocked'] == true;
        final message = (result['message'] ?? '').toString().trim();

        if (blocked) {
          _toast(
            message.isNotEmpty
                ? message
                : 'Esta IP debe esperar antes de volver a intentar.',
          );
          return;
        }

        if (!configured) {
          _toast(
            message.isNotEmpty
                ? message
                : 'Aún no se ha generado el código de registro para este colegio.',
          );
          return;
        }

        if (!ok) {
          _toast(message.isNotEmpty ? message : 'Código incorrecto.');
          return;
        }

        final session = await SchoolRegistrationSession.open(
          schoolId: _schoolId,
          access: result,
        );
        _codeCtrl.clear();
        if (!mounted) {
          await session.close();
          return;
        }
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (_) => RegistroEquipoScreen(
                  escuela: widget.escuela,
                  schoolIdOverride: _schoolId,
                  registrationSession: session,
                  permitirFotoAlumno: session.permitirFotoAlumno,
                  permitirEditarEstudiantes: session.permitirEditarEstudiantes,
                ),
          ),
        );
        return;
      } on FirebaseFunctionsException catch (e) {
        _toast(
          e.code == 'resource-exhausted'
              ? 'Demasiados intentos. Espera antes de volver a intentar.'
              : 'No se pudo verificar el código de registro. Revisa tus datos e intenta nuevamente.',
        );
        return;
      } catch (_) {
        _toast(
          'No se pudo verificar el código de registro. Intenta nuevamente.',
        );
        return;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------------------------------------------------
  // Autorización: solo admins del colegio
  // ------------------------------------------------------------
  Future<bool> _isAuthorizedForThisSchool(User user) async {
    final uid = user.uid;

    if (!_schoolDocFound) return false;

    try {
      final memberDoc =
          await _db
              .collection('schools')
              .doc(_schoolId)
              .collection('members')
              .doc(uid)
              .get();
      if (memberDoc.exists) {
        final m = memberDoc.data() ?? <String, dynamic>{};
        final role =
            (m['role'] ?? m['rol'] ?? m['enrol'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
        final enabled = (m['enabled'] ?? m['active'] ?? true) == true;
        if (enabled && (role == 'admin' || role == 'admin_escolar')) {
          return true;
        }
      }
    } catch (_) {}

    try {
      final d =
          await _db
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

    try {
      final userDoc = await _db.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final m = userDoc.data() ?? <String, dynamic>{};
        final role =
            (m['role'] ?? m['rol'] ?? '').toString().trim().toLowerCase();
        final enabled = (m['enabled'] ?? m['active'] ?? false) == true;
        final primarySchool = (m['schoolId'] ?? '').toString().trim();
        final schoolIds =
            (m['schoolIds'] is List)
                ? (m['schoolIds'] as List)
                    .map((e) => e.toString().trim())
                    .where((e) => e.isNotEmpty)
                    .toList()
                : const <String>[];
        final belongsToSchool =
            primarySchool == _schoolId || schoolIds.contains(_schoolId);
        if (enabled &&
            belongsToSchool &&
            (role == 'admin' || role == 'admin_escolar')) {
          return true;
        }
      }
    } catch (_) {}

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
        return 'No se pudo iniciar sesión con Google. Usa tu método de acceso habitual.';
      case 'canceled':
        return 'Inicio de sesión cancelado.';
      default:
        return 'No se pudo iniciar sesión con Google. Intenta nuevamente.';
    }
  }

  Future<UserCredential> _signInWithGoogle() async {
    final auth = FirebaseAuth.instance;

    if (kIsWeb) {
      final provider =
          GoogleAuthProvider()
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
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'Google no devolvió idToken.',
      );
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
      final ipAllowed = await _ensureAdminLoginIpAllowed(attemptFlow: 'google');
      if (!ipAllowed) return;

      final cred = await _signInWithGoogle();
      await _resolveSchoolIdAndLoad();

      final user = cred.user ?? FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'no-user',
          message: 'No se obtuvo usuario de Google.',
        );
      }

      await _ensureAuthorizedOrThrow(user);
      try {
        final deviceCheck = await EduProTrustedDeviceService.checkAccess(
          audience: 'admin_escolar',
          schoolId: _schoolId,
        );
        if (!deviceCheck.allowed) {
          await _denyAndSignOut();
          _toast(
            deviceCheck.message.isNotEmpty
                ? deviceCheck.message
                : 'Este dispositivo no está autorizado para este acceso.',
          );
          return;
        }
      } catch (e) {
        await _denyAndSignOut();
        _toast('No se pudo validar el dispositivo actual: $e');
        return;
      }
      bool twoFactorOk = false;
      try {
        twoFactorOk = await EduProTwoFactorService.ensureVerified(
          context,
          audience: 'admin_escolar',
          schoolId: _schoolId,
          schoolName: widget.escuela.nombre,
        );
      } catch (e) {
        await _denyAndSignOut();
        _toast('No se pudo completar la verificación en dos pasos: $e');
        return;
      }
      if (!twoFactorOk) {
        await _denyAndSignOut();
        _toast('Debes completar la verificación en dos pasos para continuar.');
        return;
      }
      await _recordAdminLoginSuccess(attemptFlow: 'google');
      _goToPizarra();
    } on FirebaseAuthException catch (e) {
      await _denyAndSignOut();
      if (_shouldCountGoogleFailure(e)) {
        await _recordAdminLoginFailure(attemptFlow: 'google', reason: e.code);
      }
      if (e.code == 'not-authorized') {
        _toast(
          'Acceso denegado: ese Google no está autorizado para este colegio.',
        );
      } else {
        _toast('Google login falló: ${_friendlyAuthError(e)}');
      }
    } catch (e) {
      await _denyAndSignOut();
      _toast('No se pudo validar tu acceso. Intenta nuevamente.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------------------------------------------------
  // UI (solo diseño — la lógica se queda intacta)
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // Paleta EduPro (azul + naranja)
    const azul = Color(0xFF1A237E);
    const azulDark = Color(0xFF1A237E);
    const naranja = Color.fromARGB(255, 255, 193, 7);

    final schoolName = '${widget.escuela.nombre}'.trim();

    final String statusTitle;
    final String statusText;
    final IconData statusIcon;
    final Color statusBg;
    final Color statusFg;
    final Color statusBorder;

    if (_schoolLoading) {
      statusTitle = 'Cargando';
      statusText = 'Leyendo configuración del colegio…';
      statusIcon = Icons.hourglass_top_rounded;
      statusBg = Colors.grey.shade100;
      statusFg = Colors.black87;
      statusBorder = Colors.grey.shade300;
    } else if (!_schoolDocFound) {
      statusTitle = 'Colegio no encontrado';
      statusText = 'Solo Personal Autorizado';
      'No existe este colegio en Firestore.\n'
          'Abre este login desde la lista de Colegios.';
      statusIcon = Icons.error_outline_rounded;
      statusBg = Colors.red.shade50;
      statusFg = Colors.red.shade900;
      statusBorder = Colors.red.shade200;
    } else {
      statusTitle = 'Cuenta xxx Verificada';
      statusText = 'Solo Personal Autorizado';
      statusIcon = Icons.verified_rounded;
      statusBg = Colors.green.shade50;
      statusFg = Colors.green.shade900;
      statusBorder = Colors.green.shade200;
    }

    final bool canInteract = !_loading && !_schoolLoading && _schoolDocFound;

    return Scaffold(
      body: Stack(
        children: [
          // Fondo “pro” (sin volverse “futurista”, pero sí premium)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  azul.withOpacity(0.14),
                  Colors.white,
                  naranja.withOpacity(0.12),
                ],
              ),
            ),
          ),

          // adornos suaves
          Positioned(
            top: -80,
            left: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: azul.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -90,
            right: -70,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                color: naranja.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: Material(
                      elevation: 14,
                      shadowColor: Colors.black.withOpacity(0.18),
                      color: Colors.transparent,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withOpacity(0.90),
                              Colors.white.withOpacity(0.84),
                              azulDark.withOpacity(0.12),
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.45),
                          ),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Header compacto (logo + título)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 66,
                                    height: 66,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      color: azul,
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.22),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          blurRadius: 18,
                                          offset: const Offset(0, 10),
                                          color: azul.withOpacity(0.28),
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Image.asset(
                                        'assets/logo.png',
                                        fit: BoxFit.contain,
                                        semanticLabel: 'Logotipo de EduPro',
                                        errorBuilder:
                                            (_, __, ___) => const Icon(
                                              Icons.school,
                                              size: 34,
                                              color: Colors.white,
                                            ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          schoolName.isEmpty
                                              ? 'Colegio'
                                              : schoolName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 5,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: azul.withOpacity(0.10),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                border: Border.all(
                                                  color: azul.withOpacity(0.20),
                                                ),
                                              ),
                                              child: const Text(
                                                'Reservado Para La Administración Escolar',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w800,
                                                  color: azul,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (!_schoolLoading &&
                                                _schoolDocFound &&
                                                !_schoolActive())
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.red.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                  border: Border.all(
                                                    color: Colors.red.shade200,
                                                  ),
                                                ),
                                                child: Text(
                                                  'INACTIVO',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w900,
                                                    color: Colors.red.shade800,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 14),

                              // Selector modo (más fino y compacto)
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _ModeChip(
                                        active: _mode == _AuthMode.login,
                                        label: 'Administracíon Escolar',
                                        activeColor: azul,
                                        onTap:
                                            () => _switchMode(_AuthMode.login),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _ModeChip(
                                        active: _mode == _AuthMode.register,
                                        label: 'Registro De Alumnos',
                                        activeColor: azul,
                                        onTap:
                                            () =>
                                                _switchMode(_AuthMode.register),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 12),

                              // Estado del colegio
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: statusBg,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: statusBorder),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(statusIcon, color: statusFg),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            statusTitle,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              color: statusFg,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            statusText,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: statusFg.withOpacity(0.95),
                                              height: 1.2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 14),

                              // MODO LOGIN (SOLO GOOGLE)
                              if (_mode == _AuthMode.login) ...[
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: azul,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    onPressed:
                                        canInteract ? _loginGoogle : null,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(
                                              0.18,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            Icons.g_mobiledata,
                                            size: 26,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          _loading
                                              ? 'Conectando…'
                                              : 'Continuar con Google',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black.withOpacity(0.65),
                                  ),
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
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: Colors.red.shade200,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.warning_amber_rounded,
                                              size: 18,
                                              color: Colors.red,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Modo DEV: acceso rápido habilitado',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w900,
                                                  color: Colors.red.shade800,
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
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 14,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                          onPressed:
                                              _loading ? null : _devQuickAccess,
                                          icon: const Icon(Icons.bolt),
                                          label: const Text(
                                            'Acceso rápido (DEV)',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
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
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blueGrey.shade50,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.blueGrey.shade100,
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(width: 10),
                                      const Expanded(
                                        child: Text(
                                          'Ingrese el CÓDIGO que le proporcionó la administración',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _codeCtrl,
                                  textInputAction: TextInputAction.done,
                                  decoration: InputDecoration(
                                    labelText: 'Ingrese el CÓDIGO',
                                    prefixIcon: const Icon(Icons.vpn_key),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(
                                        color: azul,
                                        width: 1.6,
                                      ),
                                    ),
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
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    onPressed:
                                        canInteract ? _goToRegistro : null,
                                    child: Text(
                                      _loading
                                          ? 'Verificando…'
                                          : 'Continuar a registro',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 12),

                              // Footer chiquito, elegante
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: naranja,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      const SizedBox(width: 8),
                                      Text(
                                        'Creado Por EduPro',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.black.withOpacity(0.55),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.verified,
                                        size: 16,
                                        color: Colors.blue,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Chip bonito para el selector de modo (solo UI)
class _ModeChip extends StatelessWidget {
  final bool active;
  final String label;
  final Color activeColor;
  final VoidCallback onTap;

  const _ModeChip({
    required this.active,
    required this.label,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: active ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}
