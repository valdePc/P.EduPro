// lib/docentes/screens/docentes.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/services/edupro_two_factor_service.dart';
import 'package:edupro/services/edupro_trusted_device_service.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

import 'package:edupro/docentes/screens/paneldedocentes.dart';

import 'package:edupro/docentes/screens/crearcuentadocentes.dart' as create;



class DocentesScreen extends StatefulWidget {
  final Escuela escuela;
  const DocentesScreen({Key? key, required this.escuela}) : super(key: key);

  @override
  State<DocentesScreen> createState() => _DocentesScreenState();
}

class _DocentesScreenState extends State<DocentesScreen> {
Future<void> _ensureTeacherUidLink({
  required User user,
  required String teacherDocId,
  required String emailLower,
}) async {
  // 1) Amarrar teachers/{teacherDocId} SOLO con campos permitidos por tus rules
  try {
    await _teachersColl.doc(teacherDocId).set({
      'authUid': user.uid,
      'emailLower': emailLower,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } catch (e) {
  }

  // 2) Crear teachers_uid/{authUid} => teacherDocId (clave para CHAT v2)
  try {
    await _db
        .collection('schools')
        .doc(_schoolId)
        .collection('teachers_uid')
        .doc(user.uid)
        .set({
      'schoolId': _schoolId,
      'teacherDocId': teacherDocId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } catch (e) {
  }
}

  bool _loading = false;
  bool _invalidLogin = false;
  String? _errorMessage;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _fn = FirebaseFunctions.instanceFor(region: 'us-central1');

  late final String _schoolId;

  @override
  void initState() {
    super.initState();

    // ✅ MISMA lógica que en crear_cuenta_docente.dart (prefijo incluido)
final rawId = normalizeSchoolIdFromEscuela(widget.escuela);
_schoolId = _cleanSchoolId(rawId);
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _signOutTeacherSession() async {
    try {
      await _auth.signOut();
    } catch (_) {}

    if (!kIsWeb) {
      try {
        final googleSignIn = GoogleSignIn.instance;
        try {
          await googleSignIn.initialize();
        } catch (_) {}
        await googleSignIn.signOut();
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>> _callSchoolAccessIp({
    required String operation,
    String? reason,
  }) async {
    final callable = _fn.httpsCallable('schoolAccessIpPing');
    final resp = await callable.call(<String, dynamic>{
      'operation': operation,
      'schoolId': _schoolId,
      'audience': 'docentes',
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
    final raw = resp.data;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry('$key', value));
    }
    return const <String, dynamic>{};
  }

  String _accessIpMessage(Map<String, dynamic> data) {
    final message = (data['message'] ?? '').toString().trim();
    if (message.isNotEmpty) return message;
    return 'Esta IP no puede entrar en este momento.';
  }

  Future<bool> _precheckSchoolAccessIp() async {
    try {
      final result = await _callSchoolAccessIp(operation: 'precheck');
      if (result['allowed'] == true) return true;
      setState(() {
        _invalidLogin = true;
        _errorMessage = _accessIpMessage(result);
      });
      return false;
    } catch (e) {
      setState(() {
        _invalidLogin = true;
        _errorMessage = 'No se pudo validar el acceso por IP: $e';
      });
      return false;
    }
  }

  Future<void> _recordSchoolAccessIpFailure(String reason) async {
    try {
      final result = await _callSchoolAccessIp(
        operation: 'failure',
        reason: reason,
      );
      if (result['blocked'] == true && mounted) {
        setState(() {
          _invalidLogin = true;
          _errorMessage = _accessIpMessage(result);
        });
      }
    } catch (_) {}
  }

  Future<void> _recordSchoolAccessIpSuccess() async {
    try {
      await _callSchoolAccessIp(operation: 'success');
    } catch (_) {}
  }

  // Firestore no permite "/" en docId
  String _cleanSchoolId(String v) => v.trim().replaceAll('/', '_');

  // ✅ Privado (detalles)
  CollectionReference<Map<String, dynamic>> get _teachersColl =>
      _db.collection('schools').doc(_schoolId).collection('teachers');

  // ✅ PUBLIC (tu captura muestra: teachers_public)
  // Aquí debe vivir el statusLower active/blocked
  CollectionReference<Map<String, dynamic>> get _teachersPublicColl =>
      _db.collection('schools').doc(_schoolId).collection('teachers_public');

  // ✅ Canoniza input (y corrige typo común: ggmail -> gmail) SOLO para búsqueda/matching
  String _canonUserInput(String s) {
    var t = s.trim();
    if (t.contains('@')) {
      t = t.toLowerCase();
      if (t.endsWith('@ggmail.com')) {
        t = t.replaceAll('@ggmail.com', '@gmail.com');
      }
    }
    return t;
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _findTeacherPublicByEmail(
    String emailLower,
  ) async {
    final snap = await _teachersPublicColl
        .where('emailLower', isEqualTo: emailLower)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first;
  }

  // -------------------------------
  // VAPID / Push
  // -------------------------------
  Future<String?> _loadWebVapidKey() async {
    try {
      final doc = await _db.collection('app_config').doc('notifications').get();
      final data = doc.data();
      final k = (data?['vapidKey'] ?? '').toString().trim();
      return k.isEmpty ? null : k;
    } catch (_) {
      return null;
    }
  }

  Future<void> _registerPushTeacher({
  required String teacherDocId,
}) async {
    try {
      final user = _auth.currentUser;
      if (teacherDocId.trim().isEmpty) return;
      if (user == null) return;
      if (_schoolId.trim().isEmpty) return;

      final membersRef = _db.collection('schools').doc(_schoolId).collection('members').doc(user.uid);

      // ✅ 1) CREA/ACTUALIZA members SIEMPRE (sin depender del token)
      try {
        await membersRef.set({
          'uid': user.uid,
          'role': 'teacher',
          'teacherDocId': teacherDocId, // 👈 AQUÍ VA
          'enabled': true,
          'audience': 'teachers',
          'tokens': <String>[],
          'updatedAt': FieldValue.serverTimestamp(),
          'lastTokenAt': FieldValue.serverTimestamp(), // ✅ obligatorio por tus reglas
        }, SetOptions(merge: true));
 } catch (e, stack) {
  return;
}
      // ✅ 2) Intentar conseguir token (si falla, igual members ya existe)
      try {
        await FirebaseMessaging.instance.requestPermission();
      } catch (_) {}

      String? token;

      if (kIsWeb) {
        final vapid = await _loadWebVapidKey();
        try {
          token = await FirebaseMessaging.instance.getToken(
            vapidKey: (vapid == null || vapid.isEmpty) ? null : vapid,
          );
        } catch (e) {
          token = null;
        }
      } else {
        try {
          token = await FirebaseMessaging.instance.getToken();
        } catch (e) {
          token = null;
        }
      }

      token = token?.trim();

      // ✅ 3) Si hay token, lo agregamos
      if (token != null && token.isNotEmpty) {
        try {
          final snap = await membersRef.get();
          final data = snap.data() ?? {};

          final current = List<String>.from((data['tokens'] ?? const []) as List);
          if (!current.contains(token)) current.add(token);

          // respeta tu regla: tokens <= 30
          if (current.length > 30) {
            current.removeRange(0, current.length - 30);
          }

          await membersRef.set({
            'tokens': current,
            'updatedAt': FieldValue.serverTimestamp(),
            'lastTokenAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (e) {
        }
      } else {
      }

      // ✅ 4) Topics (opcional)
      try {
        await FirebaseMessaging.instance.subscribeToTopic('school_$_schoolId');
        await FirebaseMessaging.instance.subscribeToTopic('school_${_schoolId}_teachers');
      } catch (e) {
      }
    } catch (e) {
    }
  }

  // -------------------------------
  // LOGIN con GOOGLE (VALIDA EN teachers_public)
  // -------------------------------
  Future<UserCredential> _signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      provider.setCustomParameters({'prompt': 'select_account'});
      return await _auth.signInWithPopup(provider);
    } else {
      final GoogleSignIn googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize();

      final account = await googleSignIn.authenticate();
      final auth = await account.authentication;

      if (auth.idToken == null || auth.idToken!.isEmpty) {
        throw Exception('Google no devolvió idToken.');
      }

      final credential = GoogleAuthProvider.credential(
        idToken: auth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    }
  }

  Future<void> _onLoginWithGoogle() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _invalidLogin = false;
      _errorMessage = null;
      _loading = true;
    });

    try {
      final ipAllowed = await _precheckSchoolAccessIp();
      if (!ipAllowed) return;

      // 1) Google Sign-In
      final cred = await _signInWithGoogle();
      final user = cred.user;
      if (user == null) {
        await _recordSchoolAccessIpFailure('google_no_user');
        setState(() {
          _invalidLogin = true;
          _errorMessage = 'No se pudo completar el inicio de sesión con Google.';
        });
        return;
      }

      final googleEmail = (user.email ?? '').trim().toLowerCase();
      if (googleEmail.isEmpty) {
        await _auth.signOut();
        await _recordSchoolAccessIpFailure('google_missing_email');
        setState(() {
          _invalidLogin = true;
          _errorMessage = 'Google no devolvió un correo. Prueba con otra cuenta.';
        });
        return;
      }

      final tdSnap = await _findTeacherPublicByEmail(googleEmail);
      if (tdSnap == null || !tdSnap.exists) {
        await _auth.signOut();
        await _recordSchoolAccessIpFailure('teacher_not_found');
        setState(() {
          _invalidLogin = true;
          _errorMessage =
              'Este correo no pertenece a un docente registrado en este colegio.';
        });
        return;
      }

      final td = tdSnap.data() ?? {};
      final tdStatusRaw =
          (td['statusLower'] ?? td['status'] ?? '').toString().trim().toLowerCase();
      final tdStatus =
          (tdStatusRaw == 'activo' || tdStatusRaw == 'activa') ? 'active' : tdStatusRaw;

      if (tdStatus != 'active') {
        await _auth.signOut();
        await _recordSchoolAccessIpFailure('teacher_inactive');
        setState(() {
          _invalidLogin = true;
          _errorMessage =
              'Tu cuenta aún no está activa. Seguimos esperando a que la administración la apruebe.';
        });
        return;
      }

      final expectedEmail = (td['emailLower'] ?? googleEmail).toString().trim().toLowerCase();
      if (_canonUserInput(googleEmail) != _canonUserInput(expectedEmail)) {
        await _auth.signOut();
        await _recordSchoolAccessIpFailure('google_email_mismatch');
        setState(() {
          _invalidLogin = true;
          _errorMessage =
              'Este correo ($googleEmail) no coincide con el correo autorizado.';
        });
        return;
      }

      // 3) Vincular uid (best effort)
// teacherDocId real = docId del docente en /teachers
// 3) Vincular uid (ESTO ES LO QUE CREA teachers_uid y arregla el chat)
final teacherDocId =
    (td['teacherDocId'] ?? td['teacherId'] ?? tdSnap.id).toString().trim().isNotEmpty
        ? (td['teacherDocId'] ?? td['teacherId'] ?? tdSnap.id).toString().trim()
        : tdSnap.id;

// (A) Seguridad extra: confirma que existe teachers/{teacherDocId} en ESTA escuela
final tSnap = await _teachersColl.doc(teacherDocId).get();
if (!tSnap.exists) {
  await _auth.signOut();
  await _recordSchoolAccessIpFailure('teacher_missing_profile');
  setState(() {
    _invalidLogin = true;
    _errorMessage =
        'Tu perfil no existe en teachers (solo en public). Pide a administración que lo cree/active.';
  });
  return;
}

// (B) Crear vínculo teachers_uid + amarre mínimo en teachers (permitido por tus rules)
await _ensureTeacherUidLink(
  user: user,
  teacherDocId: teacherDocId,
  emailLower: expectedEmail,
);

// (C) Verificación post-write (si no existe, no navegues)
final linkRef = _db
    .collection('schools')
    .doc(_schoolId)
    .collection('teachers_uid')
    .doc(user.uid);

final linkSnap = await linkRef.get();
if (!linkSnap.exists) {
  // Esto te dice 100% si fue permiso o ejecución
  await _auth.signOut();
  setState(() {
    _invalidLogin = true;
    _errorMessage =
        'No pude crear teachers_uid. Revisa permisos de rules en /teachers_uid o mira los logs de debug.';
  });
  return;
}

// 1) Amarrar teachers/{teacherDocId} SOLO con campos permitidos por tus rules
try {
  await _teachersColl.doc(teacherDocId).set({
    'authUid': user.uid,
    'emailLower': expectedEmail,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
} catch (e) {
}

// 2) ✅ Crear/actualizar teachers_uid/{authUid} (esto desbloquea el chat del docente)
try {
  await _db
      .collection('schools')
      .doc(_schoolId)
      .collection('teachers_uid')
      .doc(user.uid)
      .set({
    'schoolId': _schoolId,
    'teacherDocId': teacherDocId,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
} catch (e) {
}

// 3) ❌ NO escribas en teachers_public aquí.
// Eso debe hacerlo admin/superadmin o backend (según tus rules).

      try {
        final deviceCheck = await EduProTrustedDeviceService.checkAccess(
          audience: 'docentes',
          schoolId: _schoolId,
        );
        if (!deviceCheck.allowed) {
          await _signOutTeacherSession();
          setState(() {
            _invalidLogin = true;
            _errorMessage = deviceCheck.message.isNotEmpty
                ? deviceCheck.message
                : 'Este dispositivo no está autorizado para entrar.';
          });
          return;
        }
      } catch (e) {
        await _signOutTeacherSession();
        setState(() {
          _invalidLogin = true;
          _errorMessage = 'No se pudo validar el dispositivo actual: $e';
        });
        return;
      }

      bool twoFactorOk = false;
      try {
        twoFactorOk = await EduProTwoFactorService.ensureVerified(
          context,
          audience: 'docentes',
          schoolId: _schoolId,
          schoolName: widget.escuela.nombre,
        );
      } catch (e) {
        await _signOutTeacherSession();
        setState(() {
          _invalidLogin = true;
          _errorMessage =
              'No se pudo completar la verificación en dos pasos: $e';
        });
        return;
      }
      if (!twoFactorOk) {
        await _signOutTeacherSession();
        setState(() {
          _invalidLogin = true;
          _errorMessage =
              'Debes completar la verificación en dos pasos para continuar.';
        });
        return;
      }

      unawaited(_registerPushTeacher(teacherDocId: teacherDocId));
      await _recordSchoolAccessIpSuccess();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PaneldedocentesScreen(escuela: widget.escuela),
        ),
      );
    } catch (e) {
      await _recordSchoolAccessIpFailure('teacher_login_exception');
      await _signOutTeacherSession();
      if (!mounted) return;
      setState(() {
        _invalidLogin = true;
        _errorMessage = 'No se pudo validar tu acceso. Intenta nuevamente.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

void _onCreateAccount() {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => create.CrearCuentaDocentesScreen(escuela: widget.escuela),
    ),
  );
}

  // -------------------------------
  // UI (solo diseño — lógica intacta)
  // -------------------------------
  @override
  Widget build(BuildContext context) {
    const azul = Color.fromARGB(255, 21, 101, 192);
    const azulDark = Color(0xFF0A2D67);
    const amber = Color(0xFFFFA000);

    final schoolName = (widget.escuela.nombre ?? '').trim();

    return Scaffold(
      body: Stack(
        children: [
          // Fondo pro (suave)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  azul.withOpacity(0.16),
                  Colors.white,
                  amber.withOpacity(0.12),
                ],
              ),
            ),
          ),

          // adornos suaves
          Positioned(
            top: -90,
            left: -70,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                color: azul.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                color: amber.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
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
                          border: Border.all(color: Colors.white.withOpacity(0.45)),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Header (logo + título)
                            Row(
                              children: [
                                Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    color: azul,
                                    border: Border.all(color: Colors.white.withOpacity(0.22)),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Image.asset(
                                      'assets/logo.png',
                                      fit: BoxFit.contain,
                                      semanticLabel: 'Logotipo de EduPro',
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.school, size: 30, color: Colors.white),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        schoolName.isEmpty ? 'Colegio' : schoolName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: amber.withOpacity(0.16),
                                              borderRadius: BorderRadius.circular(999),
                                              border: Border.all(color: amber.withOpacity(0.30)),
                                            ),
                                            child: const Text(
                                              'Reservado Para Docentes',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.black87,
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

                            // Caja del formulario (más “premium”)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.grey.shade200),
                                boxShadow: [
                                  BoxShadow(
                                    blurRadius: 20,
                                    offset: const Offset(0, 12),
                                    color: Colors.black.withOpacity(0.06),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: azul.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: azul.withOpacity(0.14)),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color: azul.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          child: const Icon(Icons.verified_user, color: azul),
                                        ),
                                        const SizedBox(width: 12),
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Acceso con Google primero',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              SizedBox(height: 6),
                                              Text(
                                                'Solo podrán entrar docentes con correo previamente registrado y cuenta activa. Si aún no apareces, usa "Crear Mi Cuenta" o pide activación a la administración.',
                                                style: TextStyle(
                                                  color: Colors.black87,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 14),

                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: amber.withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: amber.withOpacity(0.24)),
                                    ),
                                    child: const Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.info_outline, color: Colors.black87),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            '',
                                            style: TextStyle(
                                              color: Colors.black87,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  if (_invalidLogin && (_errorMessage ?? '').trim().isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.red.withOpacity(0.20)),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.error_outline, color: Colors.red),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _errorMessage!,
                                              style: const TextStyle(
                                                color: Colors.red,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 16),

                                  SizedBox(
                                    width: double.infinity,
                                    height: 50,
                                    child: ElevatedButton(
                                      onPressed: _loading ? null : _onLoginWithGoogle,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: amber,
                                        foregroundColor: Colors.black,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        textStyle: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                        ),
                                      ),
                                      child: _loading
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                valueColor: AlwaysStoppedAnimation(Colors.black),
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Container(
                                                  width: 28,
                                                  height: 28,
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withOpacity(0.08),
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: const Icon(Icons.g_mobiledata, size: 26),
                                                ),
                                                const SizedBox(width: 10),
                                                const Text('Iniciar con Google'),
                                              ],
                                            ),
                                    ),
                                  ),

                                  const SizedBox(height: 10),

                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      TextButton(
                                        onPressed: _onCreateAccount,
                                        child: const Text(
                                          'Crear Mi Cuenta',
                                          style: TextStyle(fontWeight: FontWeight.w900),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Footer
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: amber,
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

class _Pill extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color bg;
  final Color fg;
  final Color bd;

  const _Pill({
    required this.text,
    required this.icon,
    required this.bg,
    required this.fg,
    required this.bd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: bd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
