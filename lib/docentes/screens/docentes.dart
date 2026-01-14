// lib/docentes/screens/docentes.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';

import 'package:edupro/models/escuela.dart';
import 'package:edupro/utils/school_utils.dart' show normalizeSchoolIdFromEscuela;

import 'package:edupro/docentes/screens/paneldedocentes.dart';
import 'package:edupro/docentes/screens/crearcuentadocentes.dart';
import 'package:edupro/docentes/screens/recuperarcontrasena.dart';

class DocentesScreen extends StatefulWidget {
  final Escuela escuela;
  const DocentesScreen({Key? key, required this.escuela}) : super(key: key);

  @override
  State<DocentesScreen> createState() => _DocentesScreenState();
}

class _DocentesScreenState extends State<DocentesScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  bool _loading = false;
  bool _showPassword = false;
  bool _invalidLogin = false;
  String? _errorMessage;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late final String _schoolId;

  @override
  void initState() {
    super.initState();
    _schoolId = _cleanSchoolId(normalizeSchoolIdFromEscuela(widget.escuela));
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // Firestore no permite "/" en docId
  String _cleanSchoolId(String v) => v.trim().replaceAll('/', '_');

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  CollectionReference<Map<String, dynamic>> get _teachersColl =>
      _db.collection('schools').doc(_schoolId).collection('teachers');

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('users').doc(uid);

  /// Intenta cargar VAPID key para Web (si decides configurarlo)
  /// Ruta sugerida: app_config/notifications { vapidKey: "..." }
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

  /// ✅ REGISTRO DE PUSH (tokens + topics) para el docente logueado
  /// - Guarda token en schools/{schoolId}/members/{uid}
  /// - Intenta subscribeToTopic (best-effort)
  Future<void> _registerPushTeacher() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Permisos (en Web puede lanzar cosas si no está el SW/VAPID)
      try {
        await FirebaseMessaging.instance.requestPermission();
      } catch (_) {}

      String? token;

      if (kIsWeb) {
        // En Web normalmente necesitas VAPID + service worker (firebase-messaging-sw.js).
        final vapid = await _loadWebVapidKey();
        try {
          token = await FirebaseMessaging.instance.getToken(
            vapidKey: (vapid == null || vapid.isEmpty) ? null : vapid,
          );
        } catch (e) {
          if (kDebugMode) {
            debugPrint('FCM Web token error: $e');
          }
          // No detenemos el login por esto.
          return;
        }
      } else {
        token = await FirebaseMessaging.instance.getToken();
      }

      if (token == null || token.trim().isEmpty) return;

      // Guardar token (multi-dispositivo)
      await _db
          .collection('schools')
          .doc(_schoolId)
          .collection('members')
          .doc(user.uid)
          .set({
        'uid': user.uid,
        'role': 'teacher',         // rol real
        'audience': 'teachers',    // audiencia para notificaciones
        'tokens': FieldValue.arrayUnion([token.trim()]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Topics (best-effort)
      try {
        await FirebaseMessaging.instance.subscribeToTopic('school_$_schoolId');
        await FirebaseMessaging.instance.subscribeToTopic('school_${_schoolId}_teachers');
      } catch (_) {}

      if (kDebugMode) debugPrint('Push registrado para teacher uid=${user.uid}');
    } catch (e) {
      if (kDebugMode) debugPrint('Error registrando push: $e');
    }
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findTeacherDoc(String input) async {
    final qByName = _teachersColl
        .where('status', isEqualTo: 'active')
        .where('name', isEqualTo: input)
        .limit(1)
        .get();

    final qByPhone = _teachersColl
        .where('status', isEqualTo: 'active')
        .where('phone', isEqualTo: input)
        .limit(1)
        .get();

    final res = await Future.wait([qByName, qByPhone]);

    if (res[0].docs.isNotEmpty) return res[0].docs.first;
    if (res[1].docs.isNotEmpty) return res[1].docs.first;

    // Fallback laxo
    final fallback = await _teachersColl.where('status', isEqualTo: 'active').get();
    final q = input.toLowerCase();

    for (final d in fallback.docs) {
      final data = d.data();
      final name = (data['name'] ?? '').toString().toLowerCase();
      final phone = (data['phone'] ?? '').toString().toLowerCase();

      if (name == q || phone == q || name.contains(q) || phone.contains(q)) {
        return d;
      }
    }
    return null;
  }

  Future<void> _onLogin() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _invalidLogin = false;
      _errorMessage = null;
    });

    if (!_formKey.currentState!.validate()) return;

    final inputUser = _usernameCtrl.text.trim();
    final inputPass = _passwordCtrl.text.trim();

    setState(() => _loading = true);

    try {
      // 1) Buscar docente en Firestore
      final teacherDoc = await _findTeacherDoc(inputUser);

      if (teacherDoc == null) {
        setState(() {
          _invalidLogin = true;
          _errorMessage = 'Docente no encontrado o no activo.';
        });
        return;
      }

      final tData = teacherDoc.data();

      // 2) Debe tener authEmail
      final authEmail = (tData['authEmail'] ?? '').toString().trim().toLowerCase();
      if (authEmail.isEmpty) {
        setState(() {
          _invalidLogin = true;
          _errorMessage =
              'Este docente no tiene authEmail configurado.\n'
              'Pídele al admin que lo asigne en teachers/{docId}.';
        });
        return;
      }

      // 3) FirebaseAuth REAL
      final cred = await _auth.signInWithEmailAndPassword(
        email: authEmail,
        password: inputPass,
      );

      final user = cred.user;
      if (user == null) {
        setState(() {
          _invalidLogin = true;
          _errorMessage = 'No se pudo completar el inicio de sesión.';
        });
        return;
      }

      // 4) Guardar rol + schoolId en users/{uid}
      final displayName = (tData['name'] ?? '').toString().trim();
      await _userRef(user.uid).set({
        'uid': user.uid,
        'role': 'teacher',
        'schoolId': _schoolId,
        'teacherDocId': teacherDoc.id,
        'displayName': displayName.isEmpty ? (user.email ?? 'Docente') : displayName,
        'email': user.email ?? authEmail,
        'status': 'active',
        'lastLoginAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if ((tData['phone'] ?? '').toString().trim().isNotEmpty)
          'phone': (tData['phone'] ?? '').toString().trim(),
      }, SetOptions(merge: true));

      // ✅ 5) Registrar PUSH (NO bloquea el login si falla)
      await _registerPushTeacher();

      // 6) Entrar al panel
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PaneldedocentesScreen(escuela: widget.escuela),
        ),
      );
    } on FirebaseAuthException catch (e) {
      setState(() {
        _invalidLogin = true;
        if (e.code == 'user-not-found') {
          _errorMessage = 'Este authEmail no existe en FirebaseAuth.';
        } else if (e.code == 'wrong-password') {
          _errorMessage = 'Contraseña incorrecta.';
        } else if (e.code == 'invalid-email') {
          _errorMessage = 'authEmail inválido. Revisa teachers/{docId}.';
        } else if (e.code == 'user-disabled') {
          _errorMessage = 'Cuenta deshabilitada.';
        } else {
          _errorMessage = 'Error de autenticación: ${e.message ?? e.code}';
        }
      });
    } catch (e) {
      setState(() {
        _invalidLogin = true;
        _errorMessage = 'Error: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onCreateAccount() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CrearCuentaDocentesScreen(escuela: widget.escuela),
      ),
    );
  }

  void _onForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecuperarContrasenaScreen(escuela: widget.escuela),
      ),
    );
  }

  // ✅ BOTÓN TEMPORAL: Acceso rápido SOLO en DEBUG
  void _debugQuickAccess() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PaneldedocentesScreen(escuela: widget.escuela),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final azul = const Color.fromARGB(255, 21, 101, 192);
    final bg = const Color(0xFFF4F7FB);
    final amber = const Color(0xFFFFA000);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(''),
        backgroundColor: azul,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              Center(
                child: Column(
                  children: [
                    Image.asset('assets/logo.png', height: 96),
                    const SizedBox(height: 14),
                    Text(
                      widget.escuela.nombre ?? '',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Bienvenido al área de docentes',
                      style: TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // Card del login
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: azul.withOpacity(0.12)),
                  boxShadow: const [
                    BoxShadow(blurRadius: 14, offset: Offset(0, 10), color: Color(0x14000000)),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _usernameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Nombre de usuario o teléfono',
                          filled: true,
                          fillColor: const Color(0xFFF4F7FB),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Indica tu nombre o teléfono' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: !_showPassword,
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          filled: true,
                          fillColor: const Color(0xFFF4F7FB),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          suffixIcon: IconButton(
                            icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa tu contraseña' : null,
                        onFieldSubmitted: (_) => _loading ? null : _onLogin(),
                      ),

                      if (_invalidLogin && (_errorMessage ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
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
                                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _onLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: amber,
                            foregroundColor: Colors.black, // ✅ texto legible
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
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
                              : const Text('Iniciar sesión'),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // ✅ Botón temporal de acceso rápido (solo DEBUG)
                      if (kDebugMode) ...[
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: _loading ? null : _debugQuickAccess,
                            icon: const Icon(Icons.flash_on),
                            label: const Text('Acceso rápido (temporal)'),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Solo visible en modo DEBUG',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                          textAlign: TextAlign.center,
                        ),
                      ],

                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: _onCreateAccount,
                            child: const Text('Crear cuenta'),
                          ),
                          TextButton(
                            onPressed: _onForgotPassword,
                            child: const Text('Olvidé mi contraseña'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}
