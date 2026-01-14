// lib/screens/login_general.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LoginGeneralScreen extends StatefulWidget {
  const LoginGeneralScreen({super.key});

  @override
  State<LoginGeneralScreen> createState() => _LoginGeneralScreenState();
}

class _LoginGeneralScreenState extends State<LoginGeneralScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  bool _isSuperAdminRole(String role) {
    return role.trim().toLowerCase() == 'superadmin'; // ✅ solo minúscula
  }

  Future<void> _finishAuthAndEnter(User? user) async {
    final uid = user?.uid;
    if (uid == null) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(() => _error = 'No se pudo obtener UID del usuario.');
      return;
    }

    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    if (!doc.exists) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(() => _error = 'Tu usuario no tiene perfil en /users/$uid');
      return;
    }

    final data = doc.data()!;
    final enabled = data['enabled'] == true;
    final role = (data['role'] ?? '').toString();

    if (!enabled || !_isSuperAdminRole(role)) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(() => _error = 'No tienes permisos de superadmin (enabled/role).');
      return;
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/panel');
  }

  Future<void> _loginEmailPass() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final email = _emailCtrl.text.trim();
      final pass = _passCtrl.text;

      if (email.isEmpty || pass.isEmpty) {
        setState(() => _error = 'Completa correo y contraseña.');
        return;
      }

      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );

      await _finishAuthAndEnter(cred.user);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Error de autenticación');
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      UserCredential cred;

      if (kIsWeb) {
        // ✅ WEB (Chrome)
        final provider = GoogleAuthProvider();
        cred = await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        // ✅ ANDROID/iOS (google_sign_in 7.2.0)
        final gs = GoogleSignIn.instance;
        await gs.initialize();

        final googleUser = await gs.authenticate(scopeHint: const ['email']);
        final googleAuth = await googleUser.authentication;

        final idToken = googleAuth.idToken;
        if (idToken == null) {
          throw Exception('Google no devolvió idToken.');
        }

        final credential = GoogleAuthProvider.credential(idToken: idToken);
        cred = await FirebaseAuth.instance.signInWithCredential(credential);
      }

      await _finishAuthAndEnter(cred.user);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Error con Google Sign-In');
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canTap = !_loading;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 6),
                    const Text(
                      'EduPro',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: canTap ? _loginGoogle : null,
                        icon: const Icon(Icons.g_mobiledata),
                        label: const Text('Continuar con Google'),
                      ),
                    ),

                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure
                              ? Icons.visibility
                              : Icons.visibility_off),
                        ),
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],

                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: canTap ? _loginEmailPass : null,
                        child: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Iniciar sesión'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
