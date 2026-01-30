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

  // 🎨 Paleta EduPro (azul + naranja)
  static const Color _blue = Color(0xFF0D47A1);
  static const Color _orange = Color(0xFFFFA000);

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

    final fs = FirebaseFirestore.instance;

    // ✅ intenta /users primero
    DocumentSnapshot<Map<String, dynamic>> doc =
        await fs.collection('users').doc(uid).get();

    // ✅ fallback: /Users (U mayúscula)
    if (!doc.exists) {
      doc = await fs.collection('Users').doc(uid).get();
    }

    if (!doc.exists) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(() => _error =
          'Tu usuario no tiene perfil en /users/$uid ni en /Users/$uid');
      return;
    }

    final data = doc.data()!;
    final enabled = data['enabled'] == true;
    final role = (data['role'] ?? '').toString().trim();

    if (!enabled || !_isSuperAdminRole(role)) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;

      // ✅ mensaje más útil para depurar
      setState(() => _error =
          'Sin permisos. enabled=$enabled, role="$role" (requiere superadmin).');
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
    final textTheme = Theme.of(context).textTheme;

    final card = _LoginCard(
      blue: _blue,
      orange: _orange,
      loading: _loading,
      obscure: _obscure,
      error: _error,
      emailCtrl: _emailCtrl,
      passCtrl: _passCtrl,
      onToggleObscure: () => setState(() => _obscure = !_obscure),
      onGoogle: canTap ? _loginGoogle : null,
      onEmailPass: canTap ? _loginEmailPass : null,
      titleStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: 0.2,
      ),
      subtitleStyle: textTheme.bodyMedium?.copyWith(
        color: Colors.white.withOpacity(0.78),
        height: 1.2,
      ),
    );

    return Scaffold(
      body: Stack(
        children: [
          // Fondo premium (gradiente + “burbujas” suaves)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0D47A1),
                  Color(0xFF0B3A86),
                  Color(0xFF041B3A),
                ],
              ),
            ),
          ),
          Positioned(
            top: -80,
            left: -60,
            child: _GlowBlob(color: _orange.withOpacity(0.22), size: 220),
          ),
          Positioned(
            bottom: -90,
            right: -60,
            child: _GlowBlob(color: Colors.white.withOpacity(0.10), size: 260),
          ),
          Positioned(
            top: 120,
            right: -40,
            child: _GlowBlob(color: _orange.withOpacity(0.12), size: 180),
          ),

          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 880;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      child: wide
                          ? Row(
                              children: [
                                Expanded(
                                  child: _LeftBrandPanel(
                                    blue: _blue,
                                    orange: _orange,
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(child: card),
                              ],
                            )
                          : SingleChildScrollView(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _TopMiniBrand(blue: _blue, orange: _orange),
                                  const SizedBox(height: 12),
                                  card,
                                ],
                              ),
                            ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  final Color blue;
  final Color orange;
  final bool loading;
  final bool obscure;
  final String? error;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final VoidCallback onToggleObscure;
  final VoidCallback? onGoogle;
  final VoidCallback? onEmailPass;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;

  const _LoginCard({
    required this.blue,
    required this.orange,
    required this.loading,
    required this.obscure,
    required this.error,
    required this.emailCtrl,
    required this.passCtrl,
    required this.onToggleObscure,
    required this.onGoogle,
    required this.onEmailPass,
    required this.titleStyle,
    required this.subtitleStyle,
  });

  @override
  Widget build(BuildContext context) {
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            blurRadius: 28,
            offset: const Offset(0, 14),
            color: Colors.black.withOpacity(0.30),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.94),
            border: Border.all(color: Colors.white.withOpacity(0.45)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header compacto (logo + textos)
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: blue,
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 14,
                            offset: const Offset(0, 8),
                            color: blue.withOpacity(0.25),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Image.asset(
                          'assets/logo.png', // ✅ tu logo de EduPro
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.school_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('EduPro', style: titleStyle),
                          const SizedBox(height: 2),
                          Text(
                            'Acceso Administración',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.black.withOpacity(0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Google (bonito y sobrio)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: onGoogle,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      side: BorderSide(color: Colors.black.withOpacity(0.10)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Icono “G” (sin assets extra)
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.g_mobiledata, size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Continuar con Google',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.black.withOpacity(0.12))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'o con correo',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black.withOpacity(0.55),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.black.withOpacity(0.12))),
                  ],
                ),

                const SizedBox(height: 14),

                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Correo',
                    hintText: 'tu@correo.com',
                    prefixIcon: const Icon(Icons.mail_outline),
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.03),
                    border: inputBorder,
                    enabledBorder: inputBorder,
                    focusedBorder: inputBorder.copyWith(
                      borderSide: BorderSide(color: blue.withOpacity(0.55)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: passCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    hintText: '••••••••',
                    prefixIcon: const Icon(Icons.lock_outline),
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.03),
                    border: inputBorder,
                    enabledBorder: inputBorder,
                    focusedBorder: inputBorder.copyWith(
                      borderSide: BorderSide(color: orange.withOpacity(0.75)),
                    ),
                    suffixIcon: IconButton(
                      onPressed: loading ? null : onToggleObscure,
                      icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                    ),
                  ),
                ),

                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: (error == null)
                      ? const SizedBox(height: 0)
                      : Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.red.withOpacity(0.18)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    error!,
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),

                const SizedBox(height: 14),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: onEmailPass,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: orange,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: loading
                          ? const SizedBox(
                              key: ValueKey('loading'),
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Iniciar sesión',
                              key: ValueKey('text'),
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  'Solo usuarios con rol superadmin',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.black.withOpacity(0.45),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LeftBrandPanel extends StatelessWidget {
  final Color blue;
  final Color orange;

  const _LeftBrandPanel({required this.blue, required this.orange});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
        color: Colors.white.withOpacity(0.10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo grande
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: blue,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                  color: Colors.black.withOpacity(0.25),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Image.asset(
                'assets/logo.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.school_rounded, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Bienvenido a EduPro',
            style: t.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Gestión escolar moderna, clara y segura.\nAccede con tu cuenta autorizada.',
            style: t.bodyMedium?.copyWith(
              color: Colors.white.withOpacity(0.82),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              _ChipInfo(
                label: 'Seguro',
                icon: Icons.shield_outlined,
                color: orange,
              ),
              const SizedBox(width: 10),
              _ChipInfo(
                label: 'Rápido',
                icon: Icons.flash_on_outlined,
                color: Colors.white,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChipInfo extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _ChipInfo({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color.withOpacity(0.95)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.90),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopMiniBrand extends StatelessWidget {
  final Color blue;
  final Color orange;

  const _TopMiniBrand({required this.blue, required this.orange});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Column(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: blue,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                blurRadius: 18,
                offset: const Offset(0, 10),
                color: Colors.black.withOpacity(0.25),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Image.asset(
              'assets/logo.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.school_rounded, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'EduPro',
          style: t.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Acceso Administración',
          style: t.bodyMedium?.copyWith(
            color: Colors.white.withOpacity(0.78),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final Color color;
  final double size;

  const _GlowBlob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            blurRadius: 80,
            spreadRadius: 10,
            color: color,
          ),
        ],
      ),
    );
  }
}
